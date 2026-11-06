import Observation
@testable import SceneSprockets
import simd
import Testing

// #155
private final class Flag: @unchecked Sendable {
    var isSet = false
}

private func changes(_ read: () -> Void, after change: () -> Void) -> Bool {
    let flag = Flag()
    withObservationTracking(read) {
        flag.isSet = true
    }
    change()
    return flag.isSet
}

@Test
func nodePropertiesAreObservable() {
    let node = SceneGraph.Node(label: "A")
    #expect(changes({ _ = node.label }, after: { node.label = "B" }))
    #expect(changes({ _ = node.transform }, after: { node.transform = .init(diagonal: [2, 2, 2, 1]) }))
    #expect(changes({ _ = node.trs }, after: { node.trs.translation = [1, 0, 0] }))
    #expect(changes({ _ = node.content }, after: { node.content = .light(Light(type: .point)) }))
    #expect(changes({ _ = node.isVisible }, after: { node.isVisible = false }))
    #expect(changes({ _ = node.children }, after: { node.addChild(SceneGraph.Node()) }))
}

@Test
func unrelatedChangesDoNotInvalidate() {
    let node = SceneGraph.Node(label: "A")
    #expect(!changes({ _ = node.label }, after: { node.opacity = 0.5 }))
}

@Test
func sceneGraphRootIsObservable() {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    #expect(changes({ _ = sceneGraph.root }, after: { sceneGraph.root = SceneGraph.Node() }))
    #expect(changes({ _ = sceneGraph.fog }, after: { sceneGraph.fog = SceneGraph.Fog() }))
}

// Rendering reads (traversal, bounds) fill caches, which must not count as changes.
@Test
func renderingReadsDoNotInvalidate() {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(label: "Child"))
    let sceneGraph = SceneGraph(root: root)
    #expect(!changes({ _ = root.label; _ = root.children }, after: { _ = sceneGraph.nodesWithWorldTransforms(); _ = sceneGraph.bounds; _ = sceneGraph.meshEntries() }))
}
