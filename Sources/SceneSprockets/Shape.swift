import CoreGraphics
import GeometryLite3D
import Metal
import simd
import SwiftMesh
import SwiftUI

extension SceneGraph {
    /// Parametric geometry, like SceneKit's SCNBox, SCNSphere, SCNText and so on. Sizes are full extents, centered on
    /// the origin, except text (baseline on y = 0, starting at x = 0, extruded towards +z) and plane (XY).
    public enum Shape: Sendable, Equatable, Codable {
        case box(width: Float = 1, height: Float = 1, length: Float = 1)
        case sphere(radius: Float = 0.5)
        case plane(width: Float = 1, height: Float = 1)
        case cylinder(radius: Float = 0.5, height: Float = 1)
        /// A pointed cone when topRadius is 0.
        case cone(topRadius: Float = 0, bottomRadius: Float = 0.5, height: Float = 1)
        /// `height` includes the caps.
        case capsule(capRadius: Float = 0.25, height: Float = 1)
        case torus(ringRadius: Float = 0.5, pipeRadius: Float = 0.25)
        case text(String, fontName: String = "Helvetica", fontSize: Float = 1, extrusionDepth: Float = 0.1)
        /// A cylinder with a round hole along its axis, like SCNTube.
        case tube(innerRadius: Float = 0.25, outerRadius: Float = 0.5, height: Float = 1)
        /// A rectangular base at y = -height/2 and an apex at y = height/2, like SCNPyramid but centered.
        case pyramid(width: Float = 1, height: Float = 1, length: Float = 1)
        /// A large flat XZ plane facing +y, a finite stand-in for SCNFloor (no reflections).
        case floor(width: Float = 100, length: Float = 100)
        /// A path extruded along +z from z = 0, like SCNShape. `path` is a SwiftUI Path description
        /// (Path(_: String)), so the shape stays Codable; y points up as on screen.
        case extrudedPath(String, extrusionDepth: Float = 0.1)
        /// The Utah teapot, scaled so its widest side is `diameter`, centered at the origin.
        case teapot(diameter: Float = 1)

        /// Returns the shape as a SwiftMesh mesh, with normals and texture coordinates.
        public func mesh() -> Mesh {
            // SwiftMesh defaults to flat normals; curved shapes need smooth ones (#118).
            let smooth: MeshAttributes = [.smoothNormals, .textureCoordinates]
            return switch self {
            case let .box(width, height, length):
                .box(extents: [width, height, length])
            case let .sphere(radius):
                .sphere(extents: SIMD3(repeating: radius * 2), latitudeSegments: 32, longitudeSegments: 64, attributes: smooth)
            case let .plane(width, height):
                .quad(extents: [width, height])
            case let .cylinder(radius, height):
                .cylinder(height: height, radius: radius, attributes: smooth)
            case let .cone(topRadius, bottomRadius, height):
                // swiftlint:disable:next void_function_in_ternary - both branches return a mesh
                topRadius == 0 ? .cone(height: height, radius: bottomRadius, attributes: smooth) : .conicalFrustum(height: height, topRadius: topRadius, bottomRadius: bottomRadius, attributes: smooth)
            case let .capsule(capRadius, height):
                .capsule(segments: 64, height: height, radius: capRadius, latitudeSegments: 16, attributes: smooth)
            case let .torus(ringRadius, pipeRadius):
                .torus(majorSegments: 64, minorSegments: 32, majorRadius: ringRadius, minorRadius: pipeRadius, attributes: smooth)
            case let .text(string, fontName, fontSize, extrusionDepth):
                // SwiftMesh leaves hole corners of n-gon caps without normals, so triangulate before adding them (#101).
                Mesh.extrudedText(string, fontName: fontName, size: CGFloat(fontSize), depth: extrusionDepth, attributes: []).triangulated().withFlatNormals()
            case let .tube(innerRadius, outerRadius, height):
                Self.tube(innerRadius: innerRadius, outerRadius: outerRadius, height: height)
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

        private static func pyramid(width: Float, height: Float, length: Float) -> Mesh {
            let (x, y, z) = (width / 2, height / 2, length / 2)
            let positions: [SIMD3<Float>] = [[-x, -y, -z], [x, -y, -z], [x, -y, z], [-x, -y, z], [0, y, 0]]
            let faces = [[0, 1, 2, 3], [3, 2, 4], [2, 1, 4], [1, 0, 4], [0, 3, 4]]
            return Mesh(positions: positions, faces: faces).withFlatNormals()
        }

        /// Always has texture coordinates (renderers such as Blinn-Phong need them); text gets a planar XY mapping.
        public func metalMesh(device: MTLDevice) -> MetalMesh {
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
    public convenience init(parent: SceneGraph.Node? = nil, label: String? = nil, shape: SceneGraph.Shape, material: any Material, device: MTLDevice, trs: Transform3D = .identity) {
        self.init(parent: parent, label: label ?? shape.label, trs: trs, content: .mesh(shape.metalMesh(device: device), material: material))
        shapeStorage = (shape, device)
    }

    /// The shape this node's mesh was built from; nil for other nodes. Setting it on a mesh node rebuilds the mesh.
    public var shape: SceneGraph.Shape? {
        get { shapeStorage?.shape }
        set {
            guard let newValue else {
                shapeStorage = nil
                return
            }
            guard case let .mesh(mesh, materials, castsShadow, receivesShadow) = content, newValue != shapeStorage?.shape else {
                return
            }
            let device = shapeStorage?.device ?? mesh.vertexBuffer.device
            shapeStorage = (newValue, device)
            content = .mesh(newValue.metalMesh(device: device), materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
            if subdivisionLevel > 0 {
                subdivisionBase = nil
                applySubdivision()
            }
        }
    }
}
