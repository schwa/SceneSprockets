import GeometryLite3D
import Metal
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphBlinnPhong

private struct Tag: MetalSprocketsSceneGraph.Material {
    var name: String
}

// #77: flattenedClone merges a subtree's meshes into one node, with transforms baked into the vertices.
@Test
func flattenedCloneMergesMeshes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node(label: "Group", trs: .init(translation: [10, 0, 0]))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [-2, 0, 0]), content: .mesh(box, material: Tag(name: "a")))
    let right = SceneGraph.Node(parent: root, trs: .init(translation: [2, 0, 0], scale: [1, 3, 1]))
    _ = SceneGraph.Node(parent: right, content: .mesh(box, material: Tag(name: "b")))
    _ = SceneGraph.Node(parent: root, content: .light(Light(type: .point)))

    let flat = try #require(root.flattenedClone())
    #expect(flat.label == "Group")
    #expect(flat.children.isEmpty)
    #expect(flat.transform == root.transform)
    guard case let .mesh(mesh, materials, _, _) = flat.content else {
        Issue.record("No mesh")
        return
    }
    #expect(mesh.vertexCount == box.vertexCount * 2)
    #expect(mesh.submeshes.count == box.submeshes.count * 2)
    #expect(materials.compactMap { ($0 as? Tag)?.name } == Array(repeating: "a", count: box.submeshes.count) + Array(repeating: "b", count: box.submeshes.count))
    // In the group's space: the left box spans x -2.5...-1.5, the right one is 3 tall around x = 2.
    let positions = mesh.positions()
    let lower = positions.reduce(SIMD3<Float>(repeating: .infinity)) { simd_min($0, $1) }
    let upper = positions.reduce(SIMD3<Float>(repeating: -.infinity)) { simd_max($0, $1) }
    #expect(simd_distance(lower, [-2.5, -1.5, -0.5]) < 1e-4)
    #expect(simd_distance(upper, [2.5, 1.5, 0.5]) < 1e-4)
    // Normals stay unit length under the non-uniform scale.
    let normals = try #require(mesh.vertexAttributeData().first { $0.semantic == .normal })
    let normalValues = normals.bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    for index in stride(from: 0, to: normalValues.count, by: 3) {
        #expect(abs(simd_length(SIMD3(normalValues[index], normalValues[index + 1], normalValues[index + 2])) - 1) < 1e-4)
    }
}

@Test
func flattenedCloneRejectsMixedLayoutsAndSkins() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let positionsOnly = MetalMesh(device: device, attributes: [.init(semantic: .position, format: .float3, values: box.positions())], submeshes: [.init(indices: [0, 1, 2])])
    let mixed = SceneGraph.Node()
    _ = SceneGraph.Node(parent: mixed, content: .mesh(box, material: Tag(name: "a")))
    _ = SceneGraph.Node(parent: mixed, content: .mesh(positionsOnly, material: Tag(name: "b")))
    #expect(mixed.flattenedClone() == nil)

    let skinned = SceneGraph.Node(content: .mesh(box, material: Tag(name: "a")))
    skinned.skin = SceneGraph.Skin(joints: [SceneGraph.Node()], inverseBindMatrices: [matrix_identity_float4x4])
    #expect(skinned.flattenedClone() == nil)

    let empty = try #require(SceneGraph.Node(label: "Empty").flattenedClone())
    guard case .empty = empty.content else {
        Issue.record("Expected no content")
        return
    }
}
