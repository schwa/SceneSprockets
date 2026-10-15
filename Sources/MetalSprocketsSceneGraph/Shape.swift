import CoreGraphics
import GeometryLite3D
import Metal
import SwiftMesh
import simd

extension SceneGraph {
    // Parametric geometry, like SceneKit's SCNBox, SCNSphere, SCNText and so on. Sizes are full extents, centered on
    // the origin, except text (baseline on y = 0, starting at x = 0, extruded towards +z) and plane (XY).
    public enum Shape: Sendable, Equatable {
        case box(width: Float = 1, height: Float = 1, length: Float = 1)
        case sphere(radius: Float = 0.5)
        case plane(width: Float = 1, height: Float = 1)
        case cylinder(radius: Float = 0.5, height: Float = 1)
        // A pointed cone when topRadius is 0.
        case cone(topRadius: Float = 0, bottomRadius: Float = 0.5, height: Float = 1)
        // `height` includes the caps.
        case capsule(capRadius: Float = 0.25, height: Float = 1)
        case torus(ringRadius: Float = 0.5, pipeRadius: Float = 0.25)
        case text(String, fontName: String = "Helvetica", fontSize: Float = 1, extrusionDepth: Float = 0.1)

        public func mesh() -> Mesh {
            switch self {
            case let .box(width, height, length):
                .box(extents: [width, height, length])
            case let .sphere(radius):
                .sphere(extents: SIMD3(repeating: radius * 2))
            case let .plane(width, height):
                .quad(extents: [width, height])
            case let .cylinder(radius, height):
                .cylinder(height: height, radius: radius)
            case let .cone(topRadius, bottomRadius, height):
                topRadius == 0 ? .cone(height: height, radius: bottomRadius) : .conicalFrustum(height: height, topRadius: topRadius, bottomRadius: bottomRadius)
            case let .capsule(capRadius, height):
                .capsule(height: height, radius: capRadius)
            case let .torus(ringRadius, pipeRadius):
                .torus(majorRadius: ringRadius, minorRadius: pipeRadius)
            case let .text(string, fontName, fontSize, extrusionDepth):
                .extrudedText(string, fontName: fontName, size: CGFloat(fontSize), depth: extrusionDepth)
            }
        }

        // Always has texture coordinates (renderers such as Blinn-Phong need them); text gets a planar XY mapping.
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
            }
        }
    }
}

extension SceneGraph.Node {
    // A mesh node for `shape`. Set `shape` later to rebuild its mesh, keeping the materials.
    public convenience init(parent: SceneGraph.Node? = nil, label: String? = nil, shape: SceneGraph.Shape, material: any Material, device: MTLDevice, trs: Transform3D = .identity) {
        self.init(parent: parent, label: label ?? shape.label, trs: trs, content: .mesh(shape.metalMesh(device: device), material: material))
        shapeStorage = (shape, device)
    }

    // The shape this node's mesh was built from; nil for other nodes. Setting it on a mesh node rebuilds the mesh.
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
