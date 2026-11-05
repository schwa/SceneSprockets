import SwiftECS
import Testing
import simd
@testable import SceneSprockets

// #265: nodes under a SceneGraph's root store transform, content and hierarchy in the graph's World.

private func translation(_ node: SceneGraph.Node) -> SIMD3<Float> {
    node.transform.columns.3.xyz
}

private func siblingIndex(_ node: SceneGraph.Node, in world: World) -> Int? {
    world[node.id]?[SiblingIndexComponent.self]?.index
}

@Test
func nodeOutsideGraphHasNoEntity() {
    let node = SceneGraph.Node(transform: simd_float4x4(translation: [1, 2, 3]))
    #expect(node.world == nil)
    #expect(translation(node) == [1, 2, 3])
}

@Test
func graphGivesSubtreeEntitiesWithValues() throws {
    let root = SceneGraph.Node(label: "root")
    let child = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [1, 0, 0]))
    let graph = SceneGraph(root: root)
    #expect(root.world === graph.world)
    #expect(child.world === graph.world)
    let entity = try #require(graph.world[child.id])
    #expect(entity[NodeTransformComponent.self]?.value.matrix.columns.3.xyz == [1, 0, 0])
    #expect(entity.parent?.id == root.id)
}

@Test
func nodeWritesGoToWorldAndWorldWritesShowInNode() throws {
    let root = SceneGraph.Node()
    let graph = SceneGraph(root: root)
    root.transform = simd_float4x4(translation: [4, 5, 6])
    let entity = try #require(graph.world[root.id])
    #expect(entity[NodeTransformComponent.self]?.value.matrix.columns.3.xyz == [4, 5, 6])
    entity.set(NodeTransformComponent(value: .matrix(simd_float4x4(translation: [7, 8, 9]))))
    #expect(translation(root) == [7, 8, 9])
}

@Test
func cachedStorageSurvivesOtherEntitiesMoving() {
    let root = SceneGraph.Node()
    let first = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [1, 0, 0]))
    let second = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [2, 0, 0]))
    let third = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [3, 0, 0]))
    _ = SceneGraph(root: root)
    // Removing `first` swap-removes its row, so `third` moves into it.
    first.removeFromParent()
    #expect(translation(second) == [2, 0, 0])
    #expect(translation(third) == [3, 0, 0])
    third.transform = simd_float4x4(translation: [30, 0, 0])
    #expect(translation(second) == [2, 0, 0])
    #expect(translation(third) == [30, 0, 0])
}

// #270: other entities changing the World must not invalidate a node's cached refs; its own move must.
@Test
func cachedRefsSurviveUnrelatedStructuralChanges() throws {
    let root = SceneGraph.Node()
    let node = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [1, 0, 0]))
    let graph = SceneGraph(root: root)
    _ = node.transform
    let ref = try #require(node.localTransformStorage.ref)
    let epoch = node.localTransformStorage.refEpoch
    let other = SceneGraph.Node(parent: root)
    other.removeFromParent()
    _ = node.transform
    #expect(node.localTransformStorage.refEpoch == epoch)
    #expect(node.localTransformStorage.ref?.entityID == ref.entityID)

    // Adding an app component moves the entity; the node must follow it.
    struct Extra: Component {}
    try #require(graph.world[node.id]).set(Extra())
    node.transform = simd_float4x4(translation: [2, 0, 0])
    #expect(node.localTransformStorage.refEpoch != epoch)
    #expect(graph.world[node.id]?[NodeTransformComponent.self]?.value.matrix.columns.3.x == 2)
}

@Test
func removedNodeKeepsValuesAndLosesEntity() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root, label: "child")
    let graph = SceneGraph(root: root)
    child.transform = simd_float4x4(translation: [1, 2, 3])
    child.removeFromParent()
    #expect(child.world == nil)
    #expect(graph.world[child.id] == nil)
    #expect(translation(child) == [1, 2, 3])
}

@Test
func moveInsideGraphKeepsEntity() throws {
    struct AppComponent: Component {
        var value: Int
    }
    let root = SceneGraph.Node()
    let first = SceneGraph.Node(parent: root)
    let second = SceneGraph.Node(parent: root)
    let child = SceneGraph.Node(parent: first)
    let graph = SceneGraph(root: root)
    try #require(graph.world[child.id]).set(AppComponent(value: 42))
    second.addChild(child)
    let entity = try #require(graph.world[child.id])
    #expect(entity[AppComponent.self]?.value == 42)
    #expect(entity.parent?.id == second.id)
}

@Test
func siblingIndicesFollowChildOrder() {
    let root = SceneGraph.Node()
    let graph = SceneGraph(root: root)
    let first = SceneGraph.Node(parent: root)
    let second = SceneGraph.Node(parent: root)
    let inserted = SceneGraph.Node()
    root.insertChild(inserted, at: 0)
    #expect([inserted, first, second].map { siblingIndex($0, in: graph.world) } == [0, 1, 2])
    first.removeFromParent()
    #expect([inserted, second].map { siblingIndex($0, in: graph.world) } == [0, 1])
}

@Test
func movingSubtreeBetweenGraphsMovesEntities() {
    let loadedRoot = SceneGraph.Node()
    let loadedChild = SceneGraph.Node(parent: loadedRoot, transform: simd_float4x4(translation: [1, 0, 0]))
    let loaded = SceneGraph(root: loadedRoot)
    let scene = SceneGraph(root: SceneGraph.Node())
    scene.root.addChild(loadedRoot)
    #expect(loaded.world[loadedChild.id] == nil)
    #expect(loadedChild.world === scene.world)
    #expect(translation(loadedChild) == [1, 0, 0])
}

@Test
func replacingRootDetachesOldRoot() {
    let oldRoot = SceneGraph.Node(transform: simd_float4x4(translation: [1, 0, 0]))
    let graph = SceneGraph(root: oldRoot)
    graph.root = SceneGraph.Node()
    #expect(oldRoot.world == nil)
    #expect(translation(oldRoot) == [1, 0, 0])
}

@Test
func destroyedEntityLeavesNodeDetachedWithDefaults() throws {
    let root = SceneGraph.Node()
    let light = Light(type: .point)
    let child = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [1, 0, 0]), content: .light(light))
    let graph = SceneGraph(root: root)
    _ = try graph.world.destroy(try #require(graph.world[child.id]))
    #expect(child.world == nil)
    #expect(child.transform == .identity)
    if case .empty = child.content {} else {
        Issue.record("Expected empty content")
    }
}
