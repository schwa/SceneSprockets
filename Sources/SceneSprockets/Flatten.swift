import GeometryLite3D
import Metal
import MetalSupport
import simd
import SwiftMesh

extension SceneGraph.Node {
    /// Like SCNNode.flattenedClone(): a node with this node's label and transform whose one mesh holds every visible
    /// mesh in the subtree, with child transforms baked into positions, normals and tangents. Each source submesh
    /// keeps its material. Lights, cameras and other content are dropped. Nil when the meshes have different vertex
    /// layouts, or when any is skinned or morphed. Runs on the CPU; vertex buffers must be CPU-visible.
    public func flattenedClone() -> SceneGraph.Node? {
        var parts: [(mesh: MetalMesh, materials: [any Material], transform: simd_float4x4, castsShadow: Bool, receivesShadow: Bool)] = []
        func collect(_ node: SceneGraph.Node, transform: simd_float4x4) -> Bool {
            guard node.isShown else {
                return true
            }
            if case let .mesh(mesh, materials, castsShadow, receivesShadow) = node.content {
                guard node.skin == nil, node.morphTargets.isEmpty else {
                    return false
                }
                parts.append((mesh, materials, transform, castsShadow, receivesShadow))
            }
            return node.children.allSatisfy { collect($0, transform: transform * $0.transform) }
        }
        guard collect(self, transform: matrix_identity_float4x4) else {
            return nil
        }
        let flat = SceneGraph.Node(label: label)
        flat.localTransform = localTransform
        guard let first = parts.first else {
            return flat
        }
        let layout = first.mesh.cpuReadable().vertexAttributeData().map { ($0.semantic, $0.format) }
        var attributes = layout.map { MergedAttribute(semantic: $0.0, format: $0.1) }
        var submeshes: [MetalMesh.SubmeshIndices] = []
        var materials: [any Material] = []
        var vertexCount = 0
        for part in parts {
            let readable = part.mesh.cpuReadable()
            let data = readable.vertexAttributeData()
            guard data.map(\.semantic) == layout.map(\.0), data.map(\.format) == layout.map(\.1) else {
                return nil
            }
            for (index, attribute) in data.enumerated() {
                attributes[index].append(attribute.bytes, transform: part.transform)
            }
            for (index, submesh) in readable.submeshes.enumerated() {
                submeshes.append(MetalMesh.SubmeshIndices(label: submesh.label, indices: submesh.indices.map { $0 + UInt32(vertexCount) }, primitiveType: submesh.primitiveType))
                if let material = index < part.materials.count ? part.materials[index] : part.materials.last {
                    materials.append(material)
                }
            }
            vertexCount += part.mesh.vertexCount
        }
        let data = attributes.map { MetalMesh.VertexAttributeData(semantic: $0.semantic, format: $0.format, bytes: $0.bytes, count: vertexCount) }
        let mesh = MetalMesh(device: first.mesh.vertexBuffer.device, attributes: data, submeshes: submeshes, label: label)
        flat.content = .mesh(mesh, materials: materials, castsShadow: parts.contains(where: \.castsShadow), receivesShadow: parts.contains(where: \.receivesShadow))
        return flat
    }
}

// One vertex attribute of a flattened mesh. Float3 positions, normals and tangents (float3, or float4 with the
// handedness in w) are transformed; everything else is copied.
private struct MergedAttribute {
    var semantic: VertexDescriptor.Attribute.Semantic
    var format: MTLVertexFormat
    var bytes: [UInt8] = []

    mutating func append(_ source: [UInt8], transform: simd_float4x4) {
        let linear = simd_float3x3(transform.columns.0.xyz, transform.columns.1.xyz, transform.columns.2.xyz)
        let components = format == .float3 ? 3 : format == .float4 ? 4 : 0
        let transformed: ((SIMD3<Float>) -> SIMD3<Float>)? = switch (semantic, components) {
        case (.position, 3): { (transform * SIMD4($0, 1)).xyz }
        case (.normal, 3): { simd_normalize(linear.inverse.transpose * $0) }
        case (.tangent, 3), (.tangent, 4): { simd_normalize(linear * $0) }
        default: nil
        }
        guard let transformed, transform != matrix_identity_float4x4 else {
            bytes += source
            return
        }
        var floats = source.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        let mirrored = linear.determinant < 0
        for start in stride(from: 0, to: floats.count - components + 1, by: components) {
            let value = transformed(SIMD3(floats[start], floats[start + 1], floats[start + 2]))
            floats[start] = value.x
            floats[start + 1] = value.y
            floats[start + 2] = value.z
            if components == 4, mirrored {
                floats[start + 3] = -floats[start + 3]
            }
        }
        bytes += floats.withUnsafeBytes { Array($0) }
    }
}
