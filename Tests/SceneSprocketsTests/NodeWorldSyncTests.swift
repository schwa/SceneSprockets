import Observation
import SwiftECS
import Testing
import simd
@testable import SceneSprockets

// #266: writes made directly to the World keep revisions and observation in step with the Node API.

// The onChange callback runs synchronously on the test's thread.
private final class ChangeCount: @unchecked Sendable {
    var value = 0
}

private func setTransformInWorld(_ node: SceneGraph.Node, in graph: SceneGraph, translation: SIMD3<Float>) throws {
    let entity = try #require(graph.world[node.id])
    entity.set(NodeTransformComponent(value: .matrix(simd_float4x4(translation: translation))))
}

@Test
func directTransformWriteChangesRevision() throws {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    let graph = SceneGraph(root: root)
    let before = graph.revision
    try setTransformInWorld(child, in: graph, translation: [1, 0, 0])
    #expect(graph.revision.transform != before.transform)
    #expect(graph.revision.structure == before.structure)
}

@Test
func directContentWriteChangesStructureRevision() throws {
    let root = SceneGraph.Node()
    let graph = SceneGraph(root: root)
    let before = graph.revision
    try #require(graph.world[root.id]).set(NodeContentComponent(value: .light(Light(type: .point))))
    #expect(graph.revision.structure != before.structure)
}

@Test
func directTransformWriteNotifiesNodeObservers() throws {
    let root = SceneGraph.Node()
    let graph = SceneGraph(root: root)
    let changes = ChangeCount()
    withObservationTracking {
        _ = root.transform
    } onChange: {
        changes.value += 1
    }
    try setTransformInWorld(root, in: graph, translation: [1, 0, 0])
    #expect(changes.value == 1)
}

@Test
func readingOneNodeDoesNotObserveOtherNodes() throws {
    let root = SceneGraph.Node()
    let first = SceneGraph.Node(parent: root)
    let second = SceneGraph.Node(parent: root)
    let graph = SceneGraph(root: root)
    let changes = ChangeCount()
    withObservationTracking {
        _ = first.transform
        _ = first.content
    } onChange: {
        changes.value += 1
    }
    second.transform = simd_float4x4(translation: [1, 0, 0])
    try setTransformInWorld(second, in: graph, translation: [2, 0, 0])
    #expect(changes.value == 0)
}

@Test
func nodeWriteStillNotifiesObservers() {
    let root = SceneGraph.Node()
    _ = SceneGraph(root: root)
    let changes = ChangeCount()
    withObservationTracking {
        _ = root.transform
    } onChange: {
        changes.value += 1
    }
    root.transform = simd_float4x4(translation: [1, 0, 0])
    #expect(changes.value == 1)
}
