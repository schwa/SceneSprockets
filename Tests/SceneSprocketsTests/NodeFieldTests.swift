import AVFAudio
import MetalSprocketsParticles
import SceneSprocketsAudio
import SwiftECS
import Testing
import simd
@testable import SceneSprockets

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
