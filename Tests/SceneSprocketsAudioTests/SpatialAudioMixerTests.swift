import AVFAudio
import SceneSprocketsAudio
import simd
import Testing

// #104: the audio engine works on its own, without a scene graph.
@Test
func spatialAudioMixerRunsStandalone() throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_410))
    buffer.frameLength = 4_410
    let engine = AVAudioEngine()
    try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1_024)
    let mixer = SpatialAudioMixer(engine: engine)
    let player = AudioPlayer(buffer: buffer)

    mixer.attach(player)
    #expect(mixer.isAttached(player))
    player.position = [1, 2, 3]
    mixer.listenerTransform = matrix_identity_float4x4
    try mixer.play(player)
    #expect(player.isPlaying)
    #expect(player.position == [1, 2, 3])
    mixer.pause(player)
    #expect(!player.isPlaying)
    mixer.detach(player)
    #expect(!mixer.isAttached(player))
}
