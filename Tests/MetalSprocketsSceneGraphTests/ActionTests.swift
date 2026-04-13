import Testing
import simd
@testable import MetalSprocketsSceneGraph

private func near(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Bool {
    simd_distance(a, b) < 1e-4
}

private func run(_ action: SceneGraph.Action, on node: SceneGraph.Node, steps: [Float]) {
    let graph = SceneGraph(root: node)
    node.run(action)
    for step in steps {
        graph.advanceActions(by: step)
    }
}

@Test
func moveByIsSpreadOverDuration() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    node.run(.move(by: [4, 0, 0], duration: 2))
    graph.advanceActions(by: 0.5)
    #expect(near(node.trs.translation, [1, 0, 0]))
    graph.advanceActions(by: 5)
    #expect(near(node.trs.translation, [4, 0, 0]))
    #expect(!node.hasActions)
}

@Test
func moveToStartsFromCurrentPosition() {
    let node = SceneGraph.Node()
    node.trs.translation = [2, 0, 0]
    run(.move(to: [4, 0, 0], duration: 1), on: node, steps: [0.5])
    #expect(near(node.trs.translation, [3, 0, 0]))
}

@Test
func sequenceCarriesLeftoverTime() {
    let node = SceneGraph.Node()
    run(.sequence([.move(by: [1, 0, 0], duration: 1), .move(by: [0, 1, 0], duration: 1)]), on: node, steps: [1.5])
    #expect(near(node.trs.translation, [1, 0.5, 0]))
}

@Test
func groupRunsInParallelAndFinishesWithLongest() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    var finished = false
    node.run(.group([.move(by: [1, 0, 0], duration: 1), .scale(to: [3, 3, 3], duration: 2)]), completion: { finished = true })
    graph.advanceActions(by: 1)
    #expect(near(node.trs.translation, [1, 0, 0]))
    #expect(near(node.trs.scale, [2, 2, 2]))
    #expect(!finished)
    graph.advanceActions(by: 1)
    #expect(finished)
    #expect(near(node.trs.scale, [3, 3, 3]))
}

@Test
func repeatAndRotate() {
    let node = SceneGraph.Node()
    run(.repeat(.rotate(by: .pi / 2, around: [0, 1, 0], duration: 1), count: 2), on: node, steps: [1, 1, 1])
    let rotated = node.trs.rotation.act([1, 0, 0])
    #expect(near(rotated, [-1, 0, 0]))
}

@Test
func repeatForeverKeepsRunning() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    node.run(.repeatForever(.move(by: [1, 0, 0], duration: 1)), forKey: "spin")
    for _ in 0..<10 {
        graph.advanceActions(by: 0.5)
    }
    #expect(near(node.trs.translation, [5, 0, 0]))
    #expect(node.hasAction(forKey: "spin"))
    node.removeAction(forKey: "spin")
    #expect(!node.hasActions)
}

@Test
func timingModeEasesProgress() {
    let node = SceneGraph.Node()
    run(.move(by: [1, 0, 0], duration: 1).timingMode(.easeIn), on: node, steps: [0.5])
    #expect(near(node.trs.translation, [0.25, 0, 0]))
}

@Test
func instantActionsAndHiddenNodes() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    let graph = SceneGraph(root: root)
    var calls = 0
    child.run(.sequence([.hide(), .wait(duration: 1), .unhide(), .run { _ in calls += 1 }, .removeFromParent()]))
    graph.advanceActions(by: 0.5)
    #expect(!child.isVisible)
    graph.advanceActions(by: 0.5)
    #expect(child.isVisible)
    #expect(calls == 1)
    #expect(child.parent == nil)
}

@Test
func runningSameKeyReplaces() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    node.run(.move(by: [1, 0, 0], duration: 1), forKey: "move")
    node.run(.move(by: [0, 1, 0], duration: 1), forKey: "move")
    graph.advanceActions(by: 1)
    #expect(near(node.trs.translation, [0, 1, 0]))
}
