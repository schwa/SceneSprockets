@testable import SceneSprockets
import simd
import Testing

private typealias Clip = SceneGraph.AnimationClip

private func moveClip(_ node: SceneGraph.Node, from start: SIMD3<Float>, to end: SIMD3<Float>, duration: Float = 1) -> Clip {
    Clip(name: "move", channels: [.init(target: node, path: .translation, sampler: .init(times: [0, duration], values: [start.x, start.y, start.z, end.x, end.y, end.z], interpolation: .linear))])
}

private func isClose(_ lhs: SIMD3<Float>, _ rhs: SIMD3<Float>) -> Bool {
    simd_distance(lhs, rhs) < 0.0001
}

@Test
func overrideLayersBlendByNormalizedWeight() {
    let node = SceneGraph.Node()
    let left = moveClip(node, from: [-2, 0, 0], to: [-2, 0, 0])
    let right = moveClip(node, from: [2, 4, 0], to: [2, 4, 0])
    let mixer = SceneGraph.AnimationMixer(clips: [left, right])
    mixer.apply([.init(clip: 0, time: 0, weight: 3), .init(clip: 1, time: 0, weight: 1)])
    #expect(isClose(node.trs.translation, [-1, 1, 0]))
}

@Test
func nodesMissingFromALayerBlendTowardRest() {
    let animated = SceneGraph.Node()
    let other = SceneGraph.Node()
    other.trs.translation = [0, 0, 8]
    let clipA = moveClip(animated, from: [4, 0, 0], to: [4, 0, 0])
    let clipB = moveClip(other, from: [0, 0, 0], to: [0, 0, 0])
    let mixer = SceneGraph.AnimationMixer(clips: [clipA, clipB])
    mixer.apply([.init(clip: 0, time: 0, weight: 0.5), .init(clip: 1, time: 0, weight: 0.5)])
    #expect(isClose(animated.trs.translation, [2, 0, 0]))
    #expect(isClose(other.trs.translation, [0, 0, 4]))
}

@Test
func rotationsBlendAlongShortestArc() {
    let node = SceneGraph.Node()
    let start = simd_quatf(angle: 0, axis: [0, 1, 0])
    // -q is the same rotation as q; blending must not cancel out.
    let end = simd_quatf(vector: -simd_quatf(angle: .pi / 2, axis: [0, 1, 0]).vector)
    func hold(_ rotation: simd_quatf) -> Clip {
        let values = [rotation.vector.x, rotation.vector.y, rotation.vector.z, rotation.vector.w]
        return Clip(channels: [.init(target: node, path: .rotation, sampler: .init(times: [0], values: values, interpolation: .step))])
    }
    let mixer = SceneGraph.AnimationMixer(clips: [hold(start), hold(end)])
    mixer.apply([.init(clip: 0, time: 0, weight: 1), .init(clip: 1, time: 0, weight: 1)])
    let expected = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
    #expect(abs(abs(simd_dot(node.trs.rotation.vector, expected.vector)) - 1) < 0.0001)
}

@Test
func additiveLayerAddsOffsetFromRest() {
    let node = SceneGraph.Node()
    let base = moveClip(node, from: [1, 0, 0], to: [1, 0, 0])
    let bob = moveClip(node, from: [0, 0, 0], to: [0, 2, 0])
    let mixer = SceneGraph.AnimationMixer(clips: [base, bob])
    mixer.apply([.init(clip: 0, time: 0), .init(clip: 1, time: 1, weight: 0.5, mode: .additive)])
    #expect(isClose(node.trs.translation, [1, 1, 0]))
}

@Test
func rootMotionKeepsHorizontalTranslationAtRest() {
    let root = SceneGraph.Node()
    root.trs.translation = [0, 0, 0]
    let mixer = SceneGraph.AnimationMixer(clips: [moveClip(root, from: [0, 0, 0], to: [4, 1, 6], duration: 2)])
    mixer.apply([.init(clip: 0, time: 1)], rootMotionNode: root)
    #expect(isClose(root.trs.translation, [0, 0.5, 0]))
    #expect(isClose(mixer.rootTranslation(layers: [.init(clip: 0, time: 1)], node: root), [2, 0.5, 3]))
}

@Test
func controllerCrossFades() {
    var controller = SceneGraph.AnimationController(durations: [1, 1])
    controller.play(0, fadeDuration: 0)
    controller.play(1, fadeDuration: 1)
    controller.advance(by: 0.5)
    let weights = Dictionary(uniqueKeysWithValues: controller.layers.map { ($0.clip, $0.weight) })
    #expect(abs((weights[0] ?? 0) - 0.5) < 0.0001)
    #expect(abs((weights[1] ?? 0) - 0.5) < 0.0001)
    controller.advance(by: 1)
    #expect(controller.layers.map(\.clip) == [1])
}

@Test
func blendWeightsShareBetweenNeighbours() {
    #expect(SceneGraph.AnimationController.blendWeights(parameter: 0.75, count: 3) == [0, 0.5, 0.5])
    #expect(SceneGraph.AnimationController.blendWeights(parameter: 2, count: 2) == [0, 1])
}

@Test
func phaseSyncedBlendKeepsClipsInStep() {
    var controller = SceneGraph.AnimationController(durations: [1, 2])
    controller.blend([0, 1], parameter: 0.5)
    controller.advance(by: 0.75)
    // Cycle = 0.5 * 1 + 0.5 * 2 = 1.5 s, so 0.75 s is half way through both clips.
    let times = Dictionary(uniqueKeysWithValues: controller.tracks.map { ($0.clip, $0.time) })
    #expect(abs((times[0] ?? 0) - 0.5) < 0.0001)
    #expect(abs((times[1] ?? 0) - 1) < 0.0001)
}

@Test
func stateMachineTransitionsOnParameter() {
    let controller = SceneGraph.AnimationController(durations: [1, 1])
    var machine = SceneGraph.AnimationStateMachine(
        controller: controller,
        states: [.init("idle", clip: 0), .init("walk", clip: 1)],
        transitions: [
            .init(from: "idle", to: "walk", fadeDuration: 0) { $0.parameters["speed", default: 0] > 0.5 },
            .init(from: "walk", to: "idle", fadeDuration: 0) { $0.parameters["speed", default: 0] <= 0.5 }
        ],
        initial: "idle"
    )
    machine.advance(by: 0.1)
    #expect(machine.currentState == "idle")
    machine.parameters["speed"] = 1
    machine.advance(by: 0.1)
    #expect(machine.currentState == "walk")
    #expect(machine.controller.layers.map(\.clip) == [1])
}
