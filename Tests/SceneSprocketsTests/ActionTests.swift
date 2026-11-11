@testable import SceneSprockets
import simd
import Testing

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
    node.run(.group([.move(by: [1, 0, 0], duration: 1), .scale(to: [3, 3, 3], duration: 2)])) { finished = true }
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
    let rotated = node.trs.rotation.quaternion.act([1, 0, 0])
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
    let child = root.addChild(SceneGraph.Node())
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

// #90
@Test
func reversedUndoesRelativeActions() {
    let node = SceneGraph.Node()
    let action = SceneGraph.Action.sequence([
        .move(by: [1, 2, 0], duration: 1),
        .group([.rotate(by: 1, around: [0, 1, 0], duration: 0.5), .scale(by: 2, duration: 1)]),
        .hide()
    ])
    run(.sequence([action, action.reversed()]), on: node, steps: [1, 1, 1, 1])
    #expect(near(node.trs.translation, .zero))
    #expect(near(node.trs.scale, .one))
    #expect(abs(node.trs.rotation.quaternion.angle) < 1e-4)
    #expect(node.isVisible)
}

@Test
func reversedSwapsEaseInAndOut() {
    let node = SceneGraph.Node()
    // easeIn reversed is easeOut: half way through, a move back by 1 has covered 0.75.
    run(.move(by: [1, 0, 0], duration: 1).timingMode(.easeIn).reversed(), on: node, steps: [0.5])
    #expect(near(node.trs.translation, [-0.75, 0, 0]))
}

@Test
func speedScalesActionAndNodeTime() {
    let node = SceneGraph.Node()
    run(.sequence([.move(by: [1, 0, 0], duration: 1).speed(2), .move(by: [0, 1, 0], duration: 1)]), on: node, steps: [0.75])
    // The first move takes 0.5; the 0.25 left over runs the second at normal speed.
    #expect(near(node.trs.translation, [1, 0.25, 0]))

    let slow = SceneGraph.Node()
    slow.actionSpeed = 0.5
    run(.move(by: [1, 0, 0], duration: 1), on: slow, steps: [1])
    #expect(near(slow.trs.translation, [0.5, 0, 0]))
}

@Test
func waitWithRangeStaysInRange() {
    for _ in 0..<20 {
        let node = SceneGraph.Node()
        run(.sequence([.wait(duration: 1, withRange: 1), .hide()]), on: node, steps: [0.49])
        #expect(node.isVisible)
        let graph = SceneGraph(root: node)
        graph.advanceActions(by: 1.02)
        #expect(!node.isVisible)
    }
}

@Test
func actionForKeyReturnsRunningAction() {
    let node = SceneGraph.Node()
    node.run(.wait(duration: 3), forKey: "pause")
    #expect(node.action(forKey: "pause")?.duration == 3)
    #expect(node.action(forKey: "other") == nil)
}

@Test
func eulerRotationsAndCustomTiming() {
    let node = SceneGraph.Node()
    run(.rotateTo(x: 0, y: .pi / 2, z: 0, duration: 1), on: node, steps: [1])
    #expect(near(node.trs.rotation.quaternion.act([0, 0, 1]), [1, 0, 0]))

    let spun = SceneGraph.Node()
    run(.rotateBy(x: .pi / 2, y: 0, z: 0, duration: 1), on: spun, steps: [1])
    #expect(near(spun.trs.rotation.quaternion.act([0, 1, 0]), [0, 0, 1]))

    let stepped = SceneGraph.Node()
    run(.move(by: [1, 0, 0], duration: 1).timingMode(.custom { $0 < 0.5 ? 0 : 1 }), on: stepped, steps: [0.4])
    #expect(near(stepped.trs.translation, .zero))
}
