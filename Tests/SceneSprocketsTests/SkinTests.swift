import Metal
import MetalSprocketsPBR
import SwiftMesh
import Testing
import simd
@testable import SceneSprockets
@testable import SceneSprocketsPBR

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
}

@Test
func jointMatricesFollowJointWorldTransforms() {
    let root = SceneGraph.Node(transform: translation(0, 1, 0))
    let joint = SceneGraph.Node(parent: root, transform: translation(2, 0, 0))
    // Bind pose: joint at (2, 1, 0).
    let skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [translation(-2, -1, 0)])
    #expect(skin.jointMatrices() == [matrix_identity_float4x4])

    joint.trs.translation = [3, 0, 0]
    #expect(skin.jointMatrices()[0].columns.3 == SIMD4<Float>(1, 0, 0, 1))
}

@Test
func skinnedMeshBuildsPBRSkin() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let joint = SceneGraph.Node(parent: root, label: "joint", transform: translation(0, 5, 0))
    let skinned = SceneGraph.Node(parent: root, content: .mesh(box, material: try PBRSceneMaterial(device: device)))
    skinned.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
    skinned.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: [0, 0, 0, 0], weights: [1, 0, 0, 0]), count: box.vertexCount)

    let entries = SceneGraph(root: root).meshEntries()
    let layout = PBRNodeLayout(entries: entries)
    let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: entries, layout: layout)

    #expect(model.skins.count == 1)
    let jointIndex = try #require(model.skins.first?.joints.first)
    #expect(layout.pose().worldMatrices[jointIndex].columns.3 == SIMD4<Float>(0, 5, 0, 1))
    #expect(model.opaqueInstances.first?.skinIndex == 0)
}

@Test
func skinVerticesWithWrongCountAreIgnored() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let joint = SceneGraph.Node(parent: root)
    let skinned = SceneGraph.Node(parent: root, content: .mesh(box, material: try PBRSceneMaterial(device: device)))
    skinned.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
    skinned.skinVertices = [SceneGraph.SkinVertex(joints: [0, 0, 0, 0], weights: [1, 0, 0, 0])]

    let entries = SceneGraph(root: root).meshEntries()
    let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: entries, layout: PBRNodeLayout(entries: entries))
    #expect(model.skins.isEmpty)
    #expect(model.opaqueInstances.first?.skinIndex == nil)
}
