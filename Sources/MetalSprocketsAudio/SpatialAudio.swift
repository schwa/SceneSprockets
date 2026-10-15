import AVFAudio
import simd

// A sound with a 3D position, like SCNAudioPlayer. Attach it to a SpatialAudioMixer to hear it. Only mono buffers are
// positioned; AVAudioEnvironmentNode passes stereo through.
public final class AudioPlayer {
    public let buffer: AVAudioPCMBuffer
    public var loops: Bool
    // 0...1.
    public var volume: Float {
        didSet { playerNode.volume = volume }
    }

    // World position.
    public var position: SIMD3<Float> {
        get {
            let position = playerNode.position
            return [position.x, position.y, position.z]
        }
        set {
            playerNode.position = AVAudio3DPoint(x: newValue.x, y: newValue.y, z: newValue.z)
        }
    }

    public var isPlaying: Bool {
        playerNode.isPlaying
    }

    let playerNode = AVAudioPlayerNode()
    var isScheduled = false

    public init(buffer: AVAudioPCMBuffer, loops: Bool = true, volume: Float = 1) {
        self.buffer = buffer
        self.loops = loops
        self.volume = volume
        playerNode.volume = volume
    }

    // Loads a whole file into memory.
    public convenience init(url: URL, loops: Bool = true, volume: Float = 1) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioError.bufferCreationFailed
        }
        try file.read(into: buffer)
        self.init(buffer: buffer, loops: loops, volume: volume)
    }
}

public enum AudioError: Error {
    case bufferCreationFailed
}

// AVAudioEngine plus an AVAudioEnvironmentNode that positions attached players around a listener.
public final class SpatialAudioMixer {
    public let engine: AVAudioEngine
    public let environment = AVAudioEnvironmentNode()
    private var attached: [ObjectIdentifier: AudioPlayer] = [:]

    // Pass an engine in manual rendering mode for offline use (tests); otherwise the engine's output is used.
    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
    }

    public var attachedPlayers: [AudioPlayer] {
        Array(attached.values)
    }

    // The listener's world transform: its position, -Z forward and +Y up.
    public var listenerTransform: simd_float4x4 = matrix_identity_float4x4 {
        didSet {
            let matrix = listenerTransform
            environment.listenerPosition = AVAudio3DPoint(x: matrix.columns.3.x, y: matrix.columns.3.y, z: matrix.columns.3.z)
            let forward = -simd_normalize(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
            let up = simd_normalize(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
            environment.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z), up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))
        }
    }

    public func isAttached(_ player: AudioPlayer) -> Bool {
        attached[ObjectIdentifier(player)] != nil
    }

    public func attach(_ player: AudioPlayer) {
        guard !isAttached(player) else {
            return
        }
        engine.attach(player.playerNode)
        engine.connect(player.playerNode, to: environment, format: player.buffer.format)
        attached[ObjectIdentifier(player)] = player
    }

    // Stops the player and removes it from the engine.
    public func detach(_ player: AudioPlayer) {
        guard attached.removeValue(forKey: ObjectIdentifier(player)) != nil else {
            return
        }
        player.playerNode.stop()
        engine.detach(player.playerNode)
        player.isScheduled = false
    }

    // Starts the engine if needed, then plays (or resumes) an attached player.
    public func play(_ player: AudioPlayer) throws {
        guard isAttached(player) else {
            return
        }
        if !engine.isRunning {
            try engine.start()
        }
        if !player.isScheduled {
            player.playerNode.scheduleBuffer(player.buffer, at: nil, options: player.loops ? .loops : [])
            player.isScheduled = true
        }
        if !player.playerNode.isPlaying {
            player.playerNode.play()
        }
    }

    public func pause(_ player: AudioPlayer) {
        player.playerNode.pause()
    }
}
