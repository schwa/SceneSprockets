import Testing
import simd
@testable import SceneSprockets

private typealias Clip = SceneGraph.AnimationClip

@Test
func linearTranslationIsInterpolated() {
    let node = SceneGraph.Node()
    let sampler = Clip.Sampler(times: [0, 2], values: [0, 0, 0, 10, 0, 0], interpolation: .linear)
    let clip = Clip(name: "move", channels: [.init(target: node, path: .translation, sampler: sampler)])
    #expect(clip.duration == 2)

    clip.apply(at: 0.5)
    #expect(simd_distance(node.trs.translation, [2.5, 0, 0]) < 0.0001)

    clip.apply(at: 5)
    #expect(node.trs.translation == [10, 0, 0])
    clip.apply(at: -1)
    #expect(node.trs.translation == [0, 0, 0])
}

@Test
func stepInterpolationHoldsPreviousKey() {
    let node = SceneGraph.Node()
    let sampler = Clip.Sampler(times: [0, 1, 2], values: [1, 1, 1, 2, 2, 2, 3, 3, 3], interpolation: .step)
    let clip = Clip(name: "scale", channels: [.init(target: node, path: .scale, sampler: sampler)])
    clip.apply(at: 1.9)
    #expect(node.trs.scale == [2, 2, 2])
}

@Test
func rotationUsesSlerp() {
    let node = SceneGraph.Node()
    let start = simd_quatf(angle: 0, axis: [0, 1, 0])
    let end = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
    let values = [start.vector, end.vector].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    let clip = Clip(name: "turn", channels: [.init(target: node, path: .rotation, sampler: .init(times: [0, 1], values: values, interpolation: .linear))])
    clip.apply(at: 0.5)
    let expected = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
    #expect(simd_distance(node.trs.rotation.vector, expected.vector) < 0.0001)
}

@Test
func cubicSplineMatchesHermite() {
    // glTF cubic spline: per key [in-tangent, value, out-tangent].
    let node = SceneGraph.Node()
    let values: [Float] = [
        0, 0, 0, 0, 0, 0, 3, 0, 0,
        3, 0, 0, 1, 0, 0, 0, 0, 0,
    ]
    let clip = Clip(name: "curve", channels: [.init(target: node, path: .translation, sampler: .init(times: [0, 1], values: values, interpolation: .cubicSpline))])
    clip.apply(at: 0.5)
    // Hermite at t=0.5 with p0=0, m0=3, p1=1, m1=3: 0.5*0 + 0.125*3 + 0.5*1 - 0.125*3 = 0.5
    #expect(abs(node.trs.translation.x - 0.5) < 0.0001)
    clip.apply(at: 1)
    #expect(abs(node.trs.translation.x - 1) < 0.0001)
}

@Test
func weightsChannelSetsMorphWeights() {
    let node = SceneGraph.Node()
    let clip = Clip(name: "blend", channels: [.init(target: node, path: .weights, sampler: .init(times: [0, 1], values: [0, 1, 1, 0], interpolation: .linear))])
    clip.apply(at: 0.25)
    #expect(node.morphWeights == [0.25, 0.75])
}

@Test
func loopingWrapsTime() {
    let node = SceneGraph.Node()
    let clip = Clip(name: "move", channels: [.init(target: node, path: .translation, sampler: .init(times: [0, 2], values: [0, 0, 0, 10, 0, 0], interpolation: .linear))])
    clip.apply(at: 5, looping: true)
    #expect(simd_distance(node.trs.translation, [5, 0, 0]) < 0.0001)
}

@Test
func playerAdvancesAndStopsAtEnd() {
    let node = SceneGraph.Node()
    let clip = Clip(name: "move", channels: [.init(target: node, path: .translation, sampler: .init(times: [0, 2], values: [0, 0, 0, 10, 0, 0], interpolation: .linear))])
    let player = SceneGraph.AnimationPlayer(clip: clip, isLooping: false)
    player.advance(by: 1)
    #expect(simd_distance(node.trs.translation, [5, 0, 0]) < 0.0001)
    player.advance(by: 5)
    #expect(node.trs.translation == [10, 0, 0])
    #expect(!player.isPlaying)
}

// #89
private func slide(_ node: SceneGraph.Node) -> Clip {
    Clip(name: "slide", channels: [.init(target: node, path: .translation, sampler: .init(times: [0, 1], values: [0, 0, 0, 10, 0, 0], interpolation: .linear))])
}

@Test
func playerRepeatsAndAutoreverses() {
    let node = SceneGraph.Node()
    let player = SceneGraph.AnimationPlayer(clip: slide(node), isLooping: false)
    player.repeatCount = 2
    player.autoreverses = true
    player.advance(by: 1.5)
    // Half way back in the first cycle.
    #expect(simd_distance(node.trs.translation, [5, 0, 0]) < 1e-4)
    player.advance(by: 1)
    // Half way out in the second cycle.
    #expect(simd_distance(node.trs.translation, [5, 0, 0]) < 1e-4)
    #expect(player.isPlaying)
    player.advance(by: 10)
    #expect(!player.isPlaying)
    #expect(node.trs.translation == [0, 0, 0])
}

@Test
func playerTimingModeEasesEachPass() {
    let node = SceneGraph.Node()
    let player = SceneGraph.AnimationPlayer(clip: slide(node), isLooping: true)
    player.timingMode = .easeIn
    player.advance(by: 0.5)
    #expect(simd_distance(node.trs.translation, [2.5, 0, 0]) < 1e-4)
}

@Test
func eventsFireWhenPassedInBothDirections() {
    let node = SceneGraph.Node()
    var clip = slide(node)
    var fired: [Bool] = []
    clip.events = [.init(time: 0.5) { fired.append($0) }]
    let player = SceneGraph.AnimationPlayer(clip: clip, isLooping: true)
    player.autoreverses = true
    player.advance(by: 0.4)
    #expect(fired.isEmpty)
    player.advance(by: 0.2)
    #expect(fired == [false])
    // Through the end and back past 0.5, then into the next cycle past 0.5 again.
    player.advance(by: 2)
    #expect(fired == [false, true, false])
}

@Test
func propertyPathsAnimateLights() {
    let node = SceneGraph.Node(content: .light(Light(type: .point, color: [1, 1, 1], intensity: 0)))
    let clip = Clip(name: "flicker", channels: [
        .init(target: node, path: .property(.lightIntensity), sampler: .init(times: [0, 1], values: [0, 4], interpolation: .linear)),
        .init(target: node, path: .property(.lightColor), sampler: .init(times: [0, 1], values: [1, 0, 0, 0, 0, 1], interpolation: .linear)),
    ])
    clip.apply(at: 0.5)
    guard case let .light(light) = node.content else {
        Issue.record("Expected a light")
        return
    }
    #expect(light.intensity == 2)
    #expect(light.color == [0.5, 0, 0.5])
    // The mixer captures and blends property paths too.
    let mixer = SceneGraph.AnimationMixer(clips: [clip])
    mixer.apply([.init(clip: 0, time: 1)])
    if case let .light(light) = node.content {
        #expect(light.intensity == 4)
    }
}

@Test
func animatingBumpsTransformRevisionOnly() {
    let root = SceneGraph.Node()
    let node = SceneGraph.Node(parent: root)
    let sceneGraph = SceneGraph(root: root)
    let before = sceneGraph.revision
    let clip = Clip(name: "move", channels: [.init(target: node, path: .translation, sampler: .init(times: [0, 1], values: [0, 0, 0, 1, 0, 0], interpolation: .linear))])
    clip.apply(at: 0.5)
    #expect(sceneGraph.revision.structure == before.structure)
    #expect(sceneGraph.revision.transform != before.transform)
}
