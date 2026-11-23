import CoreGraphics
import GeometryLite3D
import Metal
import MetalSupport
import simd
import SwiftMesh
import SwiftUI

extension SceneGraph {
    /// Parametric geometry, like SceneKit's SCNBox, SCNSphere, SCNText and so on. Sizes are full extents, centered on
    /// the origin, except text (baseline on y = 0, starting at x = 0, extruded towards +z) and plane (XY).
    public enum Shape: Sendable, Hashable, Codable {
        /// `chamferRadius` rounds the edges and corners, like SCNBox; it is clamped to half the smallest side.
        case box(width: Float = 1, height: Float = 1, length: Float = 1, chamferRadius: Float = 0)
        /// `segmentCount` is the number of segments around the equator (half as many from pole to pole). A geodesic
        /// sphere is a subdivided icosahedron, like SCNSphere's isGeodesic; `segmentCount` picks its subdivision level.
        case sphere(radius: Float = 0.5, segmentCount: Int = 64, isGeodesic: Bool = false)
        /// `cornerRadius` rounds the corners, like SCNPlane; it is clamped to half the smaller side.
        case plane(width: Float = 1, height: Float = 1, cornerRadius: Float = 0)
        case cylinder(radius: Float = 0.5, height: Float = 1, segmentCount: Int = 32)
        /// A pointed cone when topRadius is 0.
        case cone(topRadius: Float = 0, bottomRadius: Float = 0.5, height: Float = 1, segmentCount: Int = 32)
        /// `height` includes the caps. `segmentCount` is the number of segments around the axis.
        case capsule(capRadius: Float = 0.25, height: Float = 1, segmentCount: Int = 64)
        case torus(ringRadius: Float = 0.5, pipeRadius: Float = 0.25, ringSegmentCount: Int = 64, pipeSegmentCount: Int = 32)
        case text(String, fontName: String = "Helvetica", fontSize: Float = 1, extrusionDepth: Float = 0.1)
        /// A cylinder with a round hole along its axis, like SCNTube.
        case tube(innerRadius: Float = 0.25, outerRadius: Float = 0.5, height: Float = 1, segmentCount: Int = 48)
        /// A rectangular base at y = -height/2 and an apex at y = height/2, like SCNPyramid but centered.
        case pyramid(width: Float = 1, height: Float = 1, length: Float = 1)
        /// A large flat XZ plane facing +y, a finite stand-in for SCNFloor (no reflections).
        case floor(width: Float = 100, length: Float = 100)
        /// A path extruded along +z from z = 0, like SCNShape. `path` is a SwiftUI Path description
        /// (Path(_: String)), so the shape stays Codable; y points up as on screen.
        case extrudedPath(String, extrusionDepth: Float = 0.1)
        /// The Utah teapot, scaled so its widest side is `diameter`, centered at the origin.
        case teapot(diameter: Float = 1)

        enum CodingKeys: CodingKey {
            case box, sphere, plane, cylinder, cone, capsule, torus, text, tube, pyramid, floor, extrudedPath, teapot
        }

        private struct ArgumentKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue _: Int) { nil }
        }

        // The synthesized format, but arguments missing from older archives take their defaults (#80).
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let key = container.allKeys.first, container.allKeys.count == 1 else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected exactly one shape case"))
            }
            let arguments = try container.nestedContainer(keyedBy: ArgumentKey.self, forKey: key)
            func value<T: Decodable>(_ name: String, _ defaultValue: T) throws -> T {
                try arguments.decodeIfPresent(T.self, forKey: ArgumentKey(stringValue: name)) ?? defaultValue
            }
            func required<T: Decodable>(_ name: String) throws -> T {
                try arguments.decode(T.self, forKey: ArgumentKey(stringValue: name))
            }
            self = switch key {
            case .box: .box(width: try required("width"), height: try required("height"), length: try required("length"), chamferRadius: try value("chamferRadius", 0))
            case .sphere: .sphere(radius: try required("radius"), segmentCount: try value("segmentCount", 64), isGeodesic: try value("isGeodesic", false))
            case .plane: .plane(width: try required("width"), height: try required("height"), cornerRadius: try value("cornerRadius", 0))
            case .cylinder: .cylinder(radius: try required("radius"), height: try required("height"), segmentCount: try value("segmentCount", 32))
            case .cone: .cone(topRadius: try required("topRadius"), bottomRadius: try required("bottomRadius"), height: try required("height"), segmentCount: try value("segmentCount", 32))
            case .capsule: .capsule(capRadius: try required("capRadius"), height: try required("height"), segmentCount: try value("segmentCount", 64))
            case .torus: .torus(ringRadius: try required("ringRadius"), pipeRadius: try required("pipeRadius"), ringSegmentCount: try value("ringSegmentCount", 64), pipeSegmentCount: try value("pipeSegmentCount", 32))
            case .text: .text(try required("_0"), fontName: try required("fontName"), fontSize: try required("fontSize"), extrusionDepth: try required("extrusionDepth"))
            case .tube: .tube(innerRadius: try required("innerRadius"), outerRadius: try required("outerRadius"), height: try required("height"), segmentCount: try value("segmentCount", 48))
            case .pyramid: .pyramid(width: try required("width"), height: try required("height"), length: try required("length"))
            case .floor: .floor(width: try required("width"), length: try required("length"))
            case .extrudedPath: .extrudedPath(try required("_0"), extrusionDepth: try required("extrusionDepth"))
            case .teapot: .teapot(diameter: try required("diameter"))
            }
        }

        /// Returns the shape as a SwiftMesh mesh, with normals and texture coordinates.
        public func mesh() -> Mesh {
            // SwiftMesh defaults to flat normals; curved shapes need smooth ones (#118).
            let smooth: MeshAttributes = [.smoothNormals, .textureCoordinates]
            return switch self {
            case let .box(width, height, length, chamferRadius):
                // swiftlint:disable:next void_function_in_ternary - both branches return a mesh
                chamferRadius > 0 ? Self.chamferedBox(extents: [width, height, length], radius: chamferRadius) : .box(extents: [width, height, length])
            case let .sphere(radius, segmentCount, isGeodesic):
                // swiftlint:disable:next void_function_in_ternary - both branches return a mesh
                isGeodesic ? .icoSphere(extents: SIMD3(repeating: radius * 2), subdivisions: Self.geodesicSubdivisions(segmentCount: segmentCount), attributes: smooth) : .sphere(extents: SIMD3(repeating: radius * 2), latitudeSegments: max(segmentCount / 2, 2), longitudeSegments: max(segmentCount, 3), attributes: smooth)
            case let .plane(width, height, cornerRadius):
                // swiftlint:disable:next void_function_in_ternary - both branches return a mesh
                cornerRadius > 0 ? Self.roundedPlane(width: width, height: height, cornerRadius: cornerRadius) : .quad(extents: [width, height])
            case let .cylinder(radius, height, segmentCount):
                .cylinder(segments: max(segmentCount, 3), height: height, radius: radius, attributes: smooth)
            case let .cone(topRadius, bottomRadius, height, segmentCount):
                // swiftlint:disable:next void_function_in_ternary - both branches return a mesh
                topRadius == 0 ? .cone(segments: max(segmentCount, 3), height: height, radius: bottomRadius, attributes: smooth) : .conicalFrustum(segments: max(segmentCount, 3), height: height, topRadius: topRadius, bottomRadius: bottomRadius, attributes: smooth)
            case let .capsule(capRadius, height, segmentCount):
                .capsule(segments: max(segmentCount, 3), height: height, radius: capRadius, latitudeSegments: max(segmentCount / 4, 2), attributes: smooth)
            case let .torus(ringRadius, pipeRadius, ringSegmentCount, pipeSegmentCount):
                .torus(majorSegments: max(ringSegmentCount, 3), minorSegments: max(pipeSegmentCount, 3), majorRadius: ringRadius, minorRadius: pipeRadius, attributes: smooth)
            case let .text(string, fontName, fontSize, extrusionDepth):
                // SwiftMesh leaves hole corners of n-gon caps without normals, so triangulate before adding them (#101).
                Mesh.extrudedText(string, fontName: fontName, size: CGFloat(fontSize), depth: extrusionDepth, attributes: []).triangulated().withFlatNormals()
            case let .tube(innerRadius, outerRadius, height, segmentCount):
                Self.tube(innerRadius: innerRadius, outerRadius: outerRadius, height: height, segments: max(segmentCount, 3))
            case let .pyramid(width, height, length):
                Self.pyramid(width: width, height: height, length: length)
            case let .floor(width, length):
                Mesh(positions: [[-width / 2, 0, -length / 2], [-width / 2, 0, length / 2], [width / 2, 0, length / 2], [width / 2, 0, -length / 2]], faces: [[0, 1, 2, 3]]).withFlatNormals()
            case let .extrudedPath(description, extrusionDepth):
                // Same as text: triangulate the n-gon caps before adding normals (#101).
                Mesh.extruded(SwiftUI.Path(description) ?? SwiftUI.Path(), depth: extrusionDepth, attributes: []).triangulated().withFlatNormals()
            case let .teapot(diameter):
                .teapot(diameter: diameter, attributes: smooth)
            }
        }

        // Faces wind counter-clockwise seen from outside.
        private static func tube(innerRadius: Float, outerRadius: Float, height: Float, segments: Int = 48) -> Mesh {
            let halfHeight = height / 2
            var positions: [SIMD3<Float>] = []
            // Rings: outer bottom, outer top, inner bottom, inner top.
            for (radius, y) in [(outerRadius, -halfHeight), (outerRadius, halfHeight), (innerRadius, -halfHeight), (innerRadius, halfHeight)] {
                for segment in 0..<segments {
                    let angle = 2 * Float.pi * Float(segment) / Float(segments)
                    positions.append([radius * cos(angle), y, radius * sin(angle)])
                }
            }
            func index(_ ring: Int, _ segment: Int) -> Int {
                ring * segments + segment % segments
            }
            var faces: [[Int]] = []
            for segment in 0..<segments {
                let next = segment + 1
                faces.append([index(0, segment), index(1, segment), index(1, next), index(0, next)])
                faces.append([index(2, segment), index(2, next), index(3, next), index(3, segment)])
                faces.append([index(1, segment), index(3, segment), index(3, next), index(1, next)])
                faces.append([index(0, segment), index(0, next), index(2, next), index(2, segment)])
            }
            // Smooth round walls, hard rims.
            return Mesh(positions: positions, faces: faces).withSmoothNormals(creaseAngle: .pi / 4)
        }

        // Each subdivision quadruples the faces; 64 segments gives level 3 (1280 triangles).
        static func geodesicSubdivisions(segmentCount: Int) -> Int {
            min(max(Int((log2(Float(max(segmentCount, 1)) / 6)).rounded()), 0), 6)
        }

        // A grid on each face of the box, with `cornerSegments` rows along every rounded edge, pushed out from an inner
        // box by `radius`. Grid points are shared between faces, so smooth normals run across the rounded edges.
        private static func chamferedBox(extents: SIMD3<Float>, radius: Float, cornerSegments: Int = 6) -> Mesh {
            let half = extents / 2
            let radius = min(radius, half.min())
            let inner = half - radius
            // Coordinates along one axis: an arc from -half to -inner, then from inner to half.
            func samples(_ axis: Int) -> [Float] {
                let low = (0...cornerSegments).map { -inner[axis] - radius * (1 - Float($0) / Float(cornerSegments)) }
                let high = low.reversed().map { -$0 }
                return inner[axis] > 0 ? low + high : low + high.dropFirst()
            }
            var positions: [SIMD3<Float>] = []
            var indexByPoint: [SIMD3<Float>: Int] = [:]
            func index(_ point: SIMD3<Float>) -> Int {
                if let index = indexByPoint[point] {
                    return index
                }
                let core = simd_clamp(point, -inner, inner)
                let offset = point - core
                let length = simd_length(offset)
                positions.append(length > 0 ? core + offset / length * radius : point)
                indexByPoint[point] = positions.count - 1
                return positions.count - 1
            }
            var faces: [[Int]] = []
            for axis in 0..<3 {
                let (uAxis, vAxis) = ((axis + 1) % 3, (axis + 2) % 3)
                let (us, vs) = (samples(uAxis), samples(vAxis))
                for sign: Float in [-1, 1] {
                    func point(_ i: Int, _ j: Int) -> Int {
                        var point = SIMD3<Float>.zero
                        point[axis] = sign * half[axis]
                        point[uAxis] = us[i]
                        point[vAxis] = vs[j]
                        return index(point)
                    }
                    for i in 0..<(us.count - 1) {
                        for j in 0..<(vs.count - 1) {
                            let quad = [point(i, j), point(i + 1, j), point(i + 1, j + 1), point(i, j + 1)]
                            // u x v points along +axis, so flip the winding on the negative face.
                            faces.append(sign > 0 ? quad : quad.reversed())
                        }
                    }
                }
            }
            return Mesh(positions: positions, faces: faces).withSmoothNormals(creaseAngle: .pi / 4)
        }

        // A fan in the XY plane facing +z, like quad.
        private static func roundedPlane(width: Float, height: Float, cornerRadius: Float, cornerSegments: Int = 8) -> Mesh {
            let radius = min(cornerRadius, min(width, height) / 2)
            let inner = SIMD2(width / 2 - radius, height / 2 - radius)
            var positions: [SIMD3<Float>] = [.zero]
            for (corner, center) in [SIMD2(inner.x, -inner.y), inner, SIMD2(-inner.x, inner.y), -inner].enumerated() {
                for step in 0...cornerSegments {
                    let angle = (Float(corner) - 1 + Float(step) / Float(cornerSegments)) * .pi / 2
                    positions.append(SIMD3(center + radius * SIMD2(cos(angle), sin(angle)), 0))
                }
            }
            let rimCount = positions.count - 1
            let faces = (0..<rimCount).map { [0, 1 + $0, 1 + ($0 + 1) % rimCount] }
            return Mesh(positions: positions, faces: faces).withFlatNormals()
        }

        private static func pyramid(width: Float, height: Float, length: Float) -> Mesh {
            let (x, y, z) = (width / 2, height / 2, length / 2)
            let positions: [SIMD3<Float>] = [[-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z], [0, y, 0]]
            let faces = [[0, 1, 2, 3], [3, 2, 4], [2, 1, 4], [1, 0, 4], [0, 3, 4]]
            return Mesh(positions: positions, faces: faces).withFlatNormals()
        }

        /// Always has texture coordinates (renderers such as Blinn-Phong need them); text gets a planar XY mapping.
        ///
        /// Equal shapes share one mesh: building one, text especially, is slow (#515).
        public func metalMesh() -> MetalMesh {
            if let mesh = ShapeMeshCache.shared[self] {
                return mesh
            }
            let mesh = makeMetalMesh()
            ShapeMeshCache.shared[self] = mesh
            return mesh
        }

        private func makeMetalMesh() -> MetalMesh {
            let device = _MTLCreateSystemDefaultDevice()
            let metalMesh = MetalMesh(mesh: mesh(), device: device, label: label)
            guard !metalMesh.vertexDescriptor.attributes.contains(where: { $0.semantic == .texcoord(0) }) else {
                return metalMesh
            }
            let positions = metalMesh.positions()
            let lower = positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let upper = positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            let size = simd_max(upper - lower, SIMD3(repeating: .ulpOfOne))
            let textureCoordinates = positions.map { SIMD2(($0.x - lower.x) / size.x, 1 - ($0.y - lower.y) / size.y) }
            let submeshes = metalMesh.submeshes.map { MetalMesh.SubmeshIndices(label: $0.label, indices: $0.indices, primitiveType: $0.primitiveType) }
            return MetalMesh(device: device, attributes: metalMesh.vertexAttributeData() + [.textureCoordinates(textureCoordinates)], submeshes: submeshes, label: label)
        }

        var label: String {
            switch self {
            case .box: "Box"
            case .sphere: "Sphere"
            case .plane: "Plane"
            case .cylinder: "Cylinder"
            case .cone: "Cone"
            case .capsule: "Capsule"
            case .torus: "Torus"
            case .text(let string, _, _, _): "Text \"\(string)\""
            case .tube: "Tube"
            case .pyramid: "Pyramid"
            case .floor: "Floor"
            case .extrudedPath: "Extruded Path"
            case .teapot: "Teapot"
            }
        }
    }
}

extension SceneGraph.Node {
    /// A mesh node for `shape`. Set `shape` later to rebuild its mesh, keeping the materials.
    public convenience init(label: String? = nil, shape: SceneGraph.Shape, material: any SceneMaterial, transform: Transform3D = .identity) {
        let mesh = shape.metalMesh()
        self.init(label: label ?? shape.label, transform: transform, content: .mesh(mesh, material: material))
        shapeStorage = (shape, mesh, nil)
    }

    /// The shape this node's mesh was built from; nil for other nodes. Setting it on a mesh node rebuilds the mesh.
    ///
    /// Setting `content` to another mesh, or to a light, camera or nothing, ends the shape. Changing only the materials
    /// or shadow flags, or the subdivision level, keeps it.
    public var shape: SceneGraph.Shape? {
        get {
            guard let shapeStorage else {
                return nil
            }
            let mesh: MetalMesh
            switch content {
            case let .mesh(contentMesh, _, _, _), let .instancedMesh(contentMesh, _, _, _, _):
                mesh = contentMesh
            default:
                return nil
            }
            let isShapeMesh = mesh.hasSameBuffers(as: shapeStorage.mesh) || shapeStorage.subdivided.map(mesh.hasSameBuffers(as:)) == true
            return isShapeMesh ? shapeStorage.shape : nil
        }
        set {
            guard let newValue else {
                shapeStorage = nil
                return
            }
            guard newValue != shape else {
                return
            }
            switch content {
            case let .mesh(_, materials, castsShadow, receivesShadow):
                let mesh = newValue.metalMesh()
                shapeStorage = (newValue, mesh, nil)
                content = .mesh(mesh, materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
            case let .instancedMesh(_, materials, transforms, castsShadow, receivesShadow):
                let mesh = newValue.metalMesh()
                shapeStorage = (newValue, mesh, nil)
                content = .instancedMesh(mesh, materials: materials, transforms: transforms, castsShadow: castsShadow, receivesShadow: receivesShadow)
            default:
                return
            }
            if subdivisionLevel > 0 {
                subdivisionBase = nil
                applySubdivision()
            }
        }
    }
}

// Built shape meshes, shared by every node with an equal shape.
final class ShapeMeshCache: @unchecked Sendable {
    static let shared = ShapeMeshCache()
    // Dropped wholesale past this many entries, so changing shapes cannot grow it forever.
    private static let limit = 256
    private let lock = NSLock()
    private var meshes: [SceneGraph.Shape: MetalMesh] = [:]

    subscript(shape: SceneGraph.Shape) -> MetalMesh? {
        get {
            lock.withLock { meshes[shape] }
        }
        set {
            lock.withLock {
                if meshes.count >= Self.limit {
                    meshes.removeAll()
                }
                meshes[shape] = newValue
            }
        }
    }
}

extension MetalMesh {
    // Whether both meshes read the same vertex buffers, so they are the same geometry.
    func hasSameBuffers(as other: MetalMesh) -> Bool {
        vertexCount == other.vertexCount
            && vertexBuffers.count == other.vertexBuffers.count
            && vertexBuffers.allSatisfy { index, buffer in other.vertexBuffers[index] === buffer }
            && vertexBufferOffsets == other.vertexBufferOffsets
    }
}
