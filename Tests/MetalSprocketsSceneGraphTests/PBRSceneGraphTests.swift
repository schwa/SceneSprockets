import Metal
import MetalSprocketsPBR
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphPBR

@Test
func pbrModelIsBuiltFromSceneGraph() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = try PBRSceneMaterial(device: device, baseColor: [1, 0, 0, 1], metallic: 0, roughness: 0.5)

    let root = SceneGraph.Node()
    let translation = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [2, 3, 4, 1]))
    root.addChild(SceneGraph.Node(transform: translation, content: .mesh(box, material: material)))
    root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))

    let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: SceneGraph(root: root).meshEntries())

    let instances = model.opaqueInstances
    #expect(instances.count == 2)
    #expect(instances.contains { $0.worldMatrix.columns.3 == SIMD4<Float>(2, 3, 4, 1) })
    #expect(model.bounds.max.x > 2)
}

@Test
func pbrPrimitiveHonorsIndexTypeAndPrimitiveType() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var mesh = MetalMesh(mesh: .box(), device: device)
    let indices: [UInt16] = [9, 9, 0, 1, 2, 3]
    let buffer = try #require(device.makeBuffer(bytes: indices, length: indices.count * 2, options: .storageModeShared))
    mesh.submeshes = [MetalMesh.Submesh(indexBuffer: buffer, indexBufferOffset: 4, indexCount: 4, indexType: .uint16, primitiveType: .line)]

    let node = SceneGraph.Node(content: .mesh(mesh, material: try PBRSceneMaterial(device: device)))
    let primitive = pbrPrimitiveInput(entry: SceneGraph(root: node).meshEntries()[0], attributes: mesh.vertexAttributeData(), skinned: false)
    #expect(primitive.indices == [0, 1, 2, 3])
    #expect(primitive.primitiveType == .line)
}

@Test
func pbrModelIsReusedUntilStructureChanges() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = try PBRSceneMaterial(device: device)
    let root = SceneGraph.Node()
    let node = SceneGraph.Node(parent: root, content: .mesh(box, material: material))
    let sceneGraph = SceneGraph(root: root)
    let renderer = PBRMaterialRenderer(device: device)

    let first = try renderer.model(for: sceneGraph.meshEntries(), structureRevision: sceneGraph.revision.structure)
    node.trs.translation = [1, 0, 0]
    let second = try renderer.model(for: sceneGraph.meshEntries(), structureRevision: sceneGraph.revision.structure)
    #expect(first === second)

    root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    let third = try renderer.model(for: sceneGraph.meshEntries(), structureRevision: sceneGraph.revision.structure)
    #expect(third !== second)
    #expect(third.opaqueInstances.count == 2)
}

@Test
func morphTargetsReachPBRPrimitiveAndPose() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let up = SceneGraph.MorphTarget(positionDeltas: Array(repeating: [0, 1, 0], count: box.vertexCount))
    let node = SceneGraph.Node(content: .mesh(box, material: try PBRSceneMaterial(device: device)))
    node.morphTargets = [up]
    node.morphWeights = [0.5]
    let entries = SceneGraph(root: node).meshEntries()

    let primitive = pbrPrimitiveInput(entry: entries[0], attributes: box.vertexAttributeData(), skinned: false)
    let targets = try #require(primitive.morphTargets).targets
    #expect(targets.count == 1)
    #expect(targets[0].positionOffsets?.count == box.vertexCount)
    #expect(targets[0].positionOffsets?[0] == [0, 1, 0])
    #expect(pbrPose(for: entries).morphWeights == [[0.5]])
}

@Test
func morphTargetsWithWrongVertexCountAreIgnored() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let node = SceneGraph.Node(content: .mesh(box, material: try PBRSceneMaterial(device: device)))
    node.morphTargets = [SceneGraph.MorphTarget(positionDeltas: [[0, 1, 0]])]
    let primitive = pbrPrimitiveInput(entry: SceneGraph(root: node).meshEntries()[0], attributes: box.vertexAttributeData(), skinned: false)
    #expect(primitive.morphTargets == nil)
}

@Test
func pbrModelIsBuiltForEachBufferLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for layout in [MetalMesh.BufferLayout.interleaved, .separateBuffers] {
        let box = MetalMesh(mesh: .box(), device: device, bufferLayout: layout)
        let node = SceneGraph.Node(content: .mesh(box, material: try PBRSceneMaterial(device: device)))
        let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: SceneGraph(root: node).meshEntries())
        #expect(model.opaqueInstances.count == 1)
    }
}

@Test
func pbrLightDirectionFollowsNodeRotation() {
    // Rotate -90° about X: the node's -Z axis points down (-Y).
    let angle = -Float.pi / 2
    let rotation = simd_float4x4(simd_quatf(angle: angle, axis: [1, 0, 0]))
    let light = pbrLight(worldTransform: rotation, light: Light(type: .directional))
    #expect(light.type == .directional)
    #expect(simd_distance(light.direction, [0, -1, 0]) < 0.001)
}
