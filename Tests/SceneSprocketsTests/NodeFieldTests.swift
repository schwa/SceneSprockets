import AVFAudio
import Metal
import MetalSprocketsParticles
import SceneSprocketsAudio
import SwiftECS
import Testing
import simd
@testable import SceneSprockets
import SceneSprocketsShaderMaterial

// #279: display fields are stored in the World for nodes in a graph.

private enum RevisionChange: Equatable {
    case none, transform, structure
}

private func revisionChange(_ graph: SceneGraph, _ body: () throws -> Void) rethrows -> RevisionChange {
    let before = graph.revision
    try body()
    let after = graph.revision
    if after.structure != before.structure {
        return .structure
    }
    return after.transform != before.transform ? .transform : .none
}

private struct AttachedNode {
    let graph: SceneGraph
    let node: SceneGraph.Node
    let entity: Entity

    init() {
        let root = SceneGraph.Node()
        node = SceneGraph.Node(parent: root)
        graph = SceneGraph(root: root)
        entity = graph.world[node.id]!
    }
}

@Test
func displayFieldsLiveInTheWorld() {
    let attached = AttachedNode()
    let node = attached.node
    let entity = attached.entity
    node.label = "a"
    node.isVisible = false
    node.isActive = false
    node.opacity = 0.5
    node.pivot = simd_float4x4(translation: [1, 0, 0])
    node.categoryBitMask = 2
    node.lightCategoryBitMask = 4
    node.renderingOrder = 3
    #expect(entity[NodeLabelComponent.self]?.value == "a")
    #expect(entity[NodeIsVisibleComponent.self]?.value == false)
    #expect(entity[NodeIsActiveComponent.self]?.value == false)
    #expect(entity[NodeOpacityComponent.self]?.value == 0.5)
    #expect(entity[NodePivotComponent.self]?.value == simd_float4x4(translation: [1, 0, 0]))
    #expect(entity[NodeCategoryBitMaskComponent.self]?.value == 2)
    #expect(entity[NodeLightCategoryBitMaskComponent.self]?.value == 4)
    #expect(entity[NodeRenderingOrderComponent.self]?.value == 3)
}

@Test
func directWorldWritesShowInNodeAndBumpTheSameRevision() {
    let attached = AttachedNode()
    let (graph, node, entity) = (attached.graph, attached.node, attached.entity)
    #expect(revisionChange(graph) { entity.set(NodeLabelComponent(value: "b")) } == .none)
    #expect(node.label == "b")
    #expect(revisionChange(graph) { entity.set(NodeIsVisibleComponent(value: false)) } == .structure)
    #expect(node.isVisible == false)
    #expect(revisionChange(graph) { entity.set(NodeIsActiveComponent(value: false)) } == .structure)
    #expect(node.isActive == false)
    #expect(revisionChange(graph) { entity.set(NodeOpacityComponent(value: 0.25)) } == .transform)
    #expect(node.opacity == 0.25)
    #expect(revisionChange(graph) { entity.set(NodeCategoryBitMaskComponent(value: 8)) } == .structure)
    #expect(node.categoryBitMask == 8)
    #expect(revisionChange(graph) { entity.set(NodeLightCategoryBitMaskComponent(value: 16)) } == .structure)
    #expect(node.lightCategoryBitMask == 16)
    #expect(revisionChange(graph) { entity.set(NodeRenderingOrderComponent(value: 5)) } == .structure)
    #expect(node.renderingOrder == 5)
}

@Test
func nodeSettersBumpTheSameRevisionAsBefore() {
    let attached = AttachedNode()
    let (graph, node) = (attached.graph, attached.node)
    #expect(revisionChange(graph) { node.label = "c" } == .none)
    #expect(revisionChange(graph) { node.isVisible = false } == .structure)
    #expect(revisionChange(graph) { node.opacity = 0.5 } == .transform)
    #expect(revisionChange(graph) { node.pivot = simd_float4x4(translation: [0, 1, 0]) } == .transform)
    #expect(revisionChange(graph) { node.renderingOrder = 1 } == .structure)
}

@Test
func directPivotWriteChangesComposedTransform() {
    let attached = AttachedNode()
    let (graph, node, entity) = (attached.graph, attached.node, attached.entity)
    node.transform = simd_float4x4(translation: [5, 0, 0])
    let pivot = NodePivotComponent(value: simd_float4x4(translation: [1, 0, 0]))
    #expect(revisionChange(graph) { entity.set(pivot) } == .transform)
    #expect(node.composedTransform.columns.3.xyz == [4, 0, 0])
}

// #276
@Test
func physicsBodyAndLevelsOfDetailLiveInTheWorld() {
    let attached = AttachedNode()
    let (graph, node, entity) = (attached.graph, attached.node, attached.entity)
    let body = SceneGraph.PhysicsBody(type: .dynamic, shape: .sphere(radius: 1))
    #expect(revisionChange(graph) { node.physicsBody = body } == .structure)
    #expect(entity[NodePhysicsBodyComponent.self]?.value == body)
    #expect(revisionChange(graph) { node.levelsOfDetail = [.init(mesh: nil, distance: 10)] } == .structure)
    #expect(entity[NodeLevelsOfDetailComponent.self]?.value.map(\.distance) == [10])

    #expect(revisionChange(graph) { entity.set(NodePhysicsBodyComponent(value: nil)) } == .structure)
    #expect(node.physicsBody == nil)
    #expect(revisionChange(graph) { entity.set(NodeLevelsOfDetailComponent(value: [])) } == .structure)
    #expect(node.levelsOfDetail.isEmpty)
}

// #275
@Test
func skinAndMorphDataLiveInTheWorld() {
    let attached = AttachedNode()
    let (graph, node, entity) = (attached.graph, attached.node, attached.entity)
    let skin = SceneGraph.Skin(joints: [node], inverseBindMatrices: [.identity])
    let vertex = SceneGraph.SkinVertex(joints: [0, 0, 0, 0], weights: [1, 0, 0, 0])
    let target = SceneGraph.MorphTarget(name: "smile")

    #expect(revisionChange(graph) { node.skin = skin } == .structure)
    #expect(entity[NodeSkinComponent.self]?.value === skin)
    #expect(revisionChange(graph) { node.skinVertices = [vertex] } == .structure)
    #expect(entity[NodeSkinVerticesComponent.self]?.value == [vertex])
    #expect(revisionChange(graph) { node.morphTargets = [target] } == .structure)
    #expect(entity[NodeMorphTargetsComponent.self]?.value == [target])
    #expect(revisionChange(graph) { node.morphWeights = [0.5] } == .transform)
    #expect(entity[NodeMorphWeightsComponent.self]?.value == [0.5])

    #expect(revisionChange(graph) { entity.set(NodeMorphWeightsComponent(value: [1])) } == .transform)
    #expect(node.morphWeights == [1])
    #expect(revisionChange(graph) { entity.set(NodeSkinComponent(value: nil)) } == .structure)
    #expect(node.skin == nil)
}

// #278
@Test
func actionStateLivesInTheWorldAndSurvivesMoves() {
    let root = SceneGraph.Node()
    let first = SceneGraph.Node(parent: root)
    let second = SceneGraph.Node(parent: root)
    let node = SceneGraph.Node(parent: first)
    let graph = SceneGraph(root: root)
    node.run(.move(by: [10, 0, 0], duration: 1), forKey: "move")
    #expect(graph.world[node.id]?[NodeRunningActionsComponent.self]?.value.count == 1)
    #expect(revisionChange(graph) { node.actionSpeed = 2 } == .none)
    #expect(graph.world[node.id]?[NodeActionSpeedComponent.self]?.value == 2)

    second.addChild(node)
    #expect(node.hasAction(forKey: "move"))
    graph.world[node.id]?.set(NodeActionSpeedComponent(value: 1))
    #expect(node.actionSpeed == 1)
    graph.advanceActions(by: 0.5)
    #expect(abs(node.transform.columns.3.x - 5) < 1e-4)
}

// #281
@Test
func constraintsAndAccelerationStatesLiveInTheWorld() {
    let attached = AttachedNode()
    let (graph, node, entity) = (attached.graph, attached.node, attached.entity)
    node.constraints = [.acceleration()]
    #expect(entity[NodeConstraintsComponent.self]?.value.count == 1)
    graph.applyConstraints(pointOfView: .identity, deltaTime: 1 / 60)
    #expect(entity[NodeAccelerationStatesComponent.self]?.value.isEmpty == false)
    // Replacing constraints directly in the World resets their smoothing state, as the setter does.
    entity.set(NodeConstraintsComponent(value: [.billboard()]))
    #expect(node.constraints.count == 1)
    #expect(node.accelerationStates.isEmpty)
}

@Test
func subdivisionLivesInTheWorld() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let triangles = SceneGraph.Shape.box().metalMesh(device: device).submeshes.reduce(0) { $0 + $1.indexCount / 3 }
    let root = SceneGraph.Node()
    let node = SceneGraph.Node(shape: .box(), material: try ShaderMaterial.normals(), device: device)
    root.addChild(node)
    let graph = SceneGraph(root: root)
    let entity = try #require(graph.world[node.id])
    func triangleCount() -> Int {
        guard case let .mesh(mesh, _, _, _) = node.content else {
            return 0
        }
        return mesh.submeshes.reduce(0) { $0 + $1.indexCount / 3 }
    }

    node.subdivisionLevel = 1
    #expect(entity[NodeSubdivisionLevelComponent.self]?.value == 1)
    #expect(entity[NodeSubdivisionBaseComponent.self]?.value != nil)
    #expect(triangleCount() == triangles * 4)
    // A direct World write subdivides too.
    entity.set(NodeSubdivisionLevelComponent(value: 0))
    #expect(triangleCount() == triangles)
}

// #277
@Test
func particleSystemsAndAudioPlayersLiveInTheWorld() throws {
    let attached = AttachedNode()
    let (graph, node, entity) = (attached.graph, attached.node, attached.entity)
    let description = ParticleSystem("Glow") { EmitterDescription("Glow") { RateModule(birthRate: 10) } }
    let system = SceneParticleSystem(description, seed: 1)
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let player = AudioPlayer(buffer: try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)))

    #expect(revisionChange(graph) { node.particleSystems = [system] } == .none)
    #expect(entity[NodeParticleSystemsComponent.self]?.value.first === system)
    #expect(revisionChange(graph) { node.audioPlayers = [player] } == .none)
    #expect(entity[NodeAudioPlayersComponent.self]?.value.first === player)
    let copy = node.clone()
    #expect(copy.particleSystems.first === system)
    #expect(copy.audioPlayers.isEmpty)

    entity.set(NodeParticleSystemsComponent(value: []))
    #expect(node.particleSystems.isEmpty)
    entity.set(NodeAudioPlayersComponent(value: []))
    #expect(node.audioPlayers.isEmpty)
}

@Test
func displayFieldsSurviveDetach() {
    let attached = AttachedNode()
    let (graph, node) = (attached.graph, attached.node)
    node.label = "kept"
    node.opacity = 0.3
    node.pivot = simd_float4x4(translation: [2, 0, 0])
    node.removeFromParent()
    #expect(graph.world[node.id] == nil)
    #expect(node.world == nil)
    #expect(node.label == "kept")
    #expect(node.opacity == 0.3)
    #expect(node.composedTransform.columns.3.xyz == [-2, 0, 0])
}
