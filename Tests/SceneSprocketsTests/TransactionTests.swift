@testable import SceneSprockets
import simd
import Testing

@Test
func transactionAnimatesTranslation() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    var completed = false
    SceneGraph.Transaction.animate(duration: 2, timingMode: .linear) {
        node.trs.translation = [4, 0, 0]
    } completion: {
        completed = true
    }
    #expect(node.trs.translation == .zero)
    graph.advanceActions(by: 1)
    #expect(simd_distance(node.trs.translation, [2, 0, 0]) < 1e-4)
    #expect(!completed)
    graph.advanceActions(by: 1)
    #expect(simd_distance(node.trs.translation, [4, 0, 0]) < 1e-4)
    #expect(completed)
}

@Test
func transactionAnimatesMorphWeightsAndRotation() {
    let node = SceneGraph.Node()
    node.morphWeights = [0, 1]
    let graph = SceneGraph(root: node)
    let target = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
    SceneGraph.Transaction.animate(duration: 1, timingMode: .linear) {
        node.morphWeights = [1, 0]
        node.trs.rotation = target
    }
    graph.advanceActions(by: 0.5)
    #expect(node.morphWeights == [0.5, 0.5])
    graph.advanceActions(by: 0.5)
    #expect(abs(simd_dot(node.trs.rotation.vector, target.vector)) > 0.9999)
}

@Test
func zeroDurationAndWithoutAnimationApplyImmediately() {
    let node = SceneGraph.Node()
    SceneGraph.Transaction.animate(duration: 0) {
        node.trs.translation = [1, 0, 0]
    }
    #expect(node.trs.translation == [1, 0, 0])
    SceneGraph.Transaction.animate(duration: 1) {
        SceneGraph.Transaction.withoutAnimation {
            node.trs.translation = [2, 0, 0]
        }
    }
    #expect(node.trs.translation == [2, 0, 0])
    #expect(!node.hasActions)
}

@Test
func multipleChangesAnimateFromFirstOldValue() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    SceneGraph.Transaction.animate(duration: 1, timingMode: .linear) {
        node.trs.translation = [1, 0, 0]
        node.trs.translation = [2, 0, 0]
    }
    graph.advanceActions(by: 0.5)
    #expect(simd_distance(node.trs.translation, [1, 0, 0]) < 1e-4)
}
