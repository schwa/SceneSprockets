import AVFAudio
@testable import SceneSprockets
import SceneSprocketsAudio
import simd
import Testing

// #51
@Test
func audioPlayersFollowTheirNodes() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
    buffer.frameLength = 4_410
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
    let audio = SceneAudio(mixer: SpatialAudioMixer(engine: engine))

    let root = SceneGraph.Node()
    let parent = SceneGraph.Node(parent: root, trs: .init(translation: [1, 0, 0]))
    let emitter = SceneGraph.Node(parent: parent, trs: .init(translation: [0, 2, 0]))
    let player = AudioPlayer(buffer: buffer)
    emitter.audioPlayers = [player]
    let sceneGraph = SceneGraph(root: root)

    try audio.update(sceneGraph: sceneGraph, listener: simd_float4x4(diagonal: [1, 1, 1, 1]))
    #expect(player.position == [1, 2, 0])
    #expect(player.isPlaying)

    parent.trs.translation = [-3, 0, 0]
    emitter.isVisible = false
    try audio.update(sceneGraph: sceneGraph, listener: simd_float4x4(diagonal: [1, 1, 1, 1]))
    #expect(!player.isPlaying)

    emitter.isVisible = true
    try audio.update(sceneGraph: sceneGraph, listener: simd_float4x4(diagonal: [1, 1, 1, 1]))
    #expect(player.position == [-3, 2, 0])

    emitter.audioPlayers = []
    try audio.update(sceneGraph: sceneGraph, listener: simd_float4x4(diagonal: [1, 1, 1, 1]))
    #expect(!audio.mixer.isAttached(player))
}
