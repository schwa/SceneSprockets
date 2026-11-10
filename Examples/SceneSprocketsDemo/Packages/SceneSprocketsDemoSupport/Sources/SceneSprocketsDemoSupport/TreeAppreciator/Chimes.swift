import AVFoundation
import os

// A tiny synth: decaying sine chimes with a simple echo, over soft wind noise.
final class Chimes: @unchecked Sendable {
    private struct Voice {
        var frequency: Double
        var phase: Double = 0
        var age: Double
        var duration: Double
        var volume: Double
    }

    private struct State {
        var voices: [Voice] = []
        var echo = [Float](repeating: 0, count: 48_000)
        var echoIndex = 0
        var wind: Float = 0
        var windTime: Double = 0
        var isMuted = false
    }

    private let engine = AVAudioEngine()
    private let state = OSAllocatedUnfairLock(initialState: State())
    private var started = false

    var isMuted: Bool {
        get { state.withLock { $0.isMuted } }
        set { state.withLock { $0.isMuted = newValue } }
    }

    func start() {
        guard !started else {
            return
        }
        started = true
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate
        let echoLength = Int(sampleRate * 0.28)
        let mono = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let source = AVAudioSourceNode(format: mono) { [state] _, _, frameCount, bufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
            guard let pointer = buffers.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return noErr
            }
            // Only touched on the render thread, inside the lock.
            nonisolated(unsafe) let output = pointer
            state.withLock { state in
                for frame in 0..<Int(frameCount) {
                    var sample: Float = 0
                    for index in state.voices.indices {
                        var voice = state.voices[index]
                        if voice.age >= 0 {
                            let envelope = min(voice.age / 0.01, 1) * exp(-voice.age / voice.duration * 5)
                            let tone = sin(voice.phase) + 0.25 * sin(voice.phase * 2.01)
                            sample += Float(tone * envelope * voice.volume)
                            voice.phase += 2 * .pi * voice.frequency / sampleRate
                        }
                        voice.age += 1 / sampleRate
                        state.voices[index] = voice
                    }
                    // Brownish noise with a slow swell.
                    state.windTime += 1 / sampleRate
                    state.wind = state.wind * 0.995 + Float.random(in: -1...1) * 0.005
                    let swell = Float(0.6 + 0.4 * sin(state.windTime * 0.5))
                    let delayed = state.echo[state.echoIndex]
                    state.echo[state.echoIndex] = sample + delayed * 0.38
                    state.echoIndex = (state.echoIndex + 1) % echoLength
                    let mixed = sample + delayed * 0.45 + state.wind * 1.2 * swell
                    output[frame] = state.isMuted ? 0 : mixed * 0.5
                }
                state.voices.removeAll { $0.age > $0.duration }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: mono)
        try? engine.start()
    }

    private func tone(_ frequency: Double, delay: Double = 0, duration: Double = 1.6, volume: Double = 0.18) {
        state.withLock { $0.voices.append(Voice(frequency: frequency, age: -delay, duration: duration, volume: volume)) }
    }

    private static let pentatonic: [Double] = [0, 2, 4, 7, 9]

    private func note(_ index: Int, root: Double = 392) -> Double {
        let octave = Double(index / 5)
        return root * pow(2, Self.pentatonic[index % 5] / 12 + octave)
    }

    func found(_ count: Int) {
        tone(note(count), delay: 0)
        tone(note(count + 2), delay: 0.12)
        tone(note(count + 4), delay: 0.24, duration: 2.2)
    }

    func miss() {
        tone(147, duration: 0.6, volume: 0.1)
    }

    func hint() {
        tone(note(5), duration: 1.2, volume: 0.08)
    }

    func complete() {
        for (index, step) in [0, 2, 4, 5, 7, 9].enumerated() {
            tone(note(step, root: 262), delay: Double(index) * 0.16, duration: 2.6, volume: 0.14)
        }
    }
}
