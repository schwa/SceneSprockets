import AVFAudio
import simd

/// A sound with a 3D position, like SceneKit's `SCNAudioPlayer`.
///
/// Attach the player to a ``SpatialAudioMixer`` to hear it. The mixer positions only mono buffers. Stereo buffers play
/// without positioning.
public final class AudioPlayer {
    /// The audio that the player plays.
    public let buffer: AVAudioPCMBuffer
    /// Whether the player repeats the buffer. Changes apply the next time the buffer is scheduled.
    public var loops: Bool
    /// The volume, from 0 (silent) to 1 (full).
    public var volume: Float {
        didSet { playerNode.volume = volume }
    }

    /// The position of the sound in world space.
    public var position: SIMD3<Float> {
        get {
            let position = playerNode.position
            return [position.x, position.y, position.z]
        }
        set {
            playerNode.position = AVAudio3DPoint(x: newValue.x, y: newValue.y, z: newValue.z)
        }
    }

    /// Whether the player is playing now.
    public var isPlaying: Bool {
        playerNode.isPlaying
    }

    let playerNode = AVAudioPlayerNode()
    var isScheduled = false

    /// Creates a player for a buffer that is already in memory.
    ///
    /// - Parameters:
    ///   - buffer: The audio to play. Use a mono buffer to hear it at ``position``.
    ///   - loops: Whether the player repeats the buffer.
    ///   - volume: The volume, from 0 to 1.
    public init(buffer: AVAudioPCMBuffer, loops: Bool = true, volume: Float = 1) {
        self.buffer = buffer
        self.loops = loops
        self.volume = volume
        playerNode.volume = volume
    }

    /// Creates a player that loads a whole audio file into memory.
    ///
    /// - Parameters:
    ///   - url: The audio file to load.
    ///   - loops: Whether the player repeats the audio.
    ///   - volume: The volume, from 0 to 1.
    /// - Throws: An `AVAudioFile` error if the file cannot be read, or ``AudioError/bufferCreationFailed``.
    public convenience init(url: URL, loops: Bool = true, volume: Float = 1) throws {
        let file = try AVAudioFile(forReading: url)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw AudioError.bufferCreationFailed
        }
        try file.read(into: buffer)
        self.init(buffer: buffer, loops: loops, volume: volume)
    }
}

/// Errors from loading audio.
public enum AudioError: Error {
    /// The audio buffer for the file could not be allocated.
    case bufferCreationFailed
}

/// An audio engine that positions attached players around a listener.
///
/// The mixer connects an `AVAudioEnvironmentNode` to the engine's main mixer. Set ``listenerTransform`` from the camera
/// each frame. `SceneView` does this for the scene graph's audio.
public final class SpatialAudioMixer {
    /// The engine that plays the attached players.
    public let engine: AVAudioEngine
    /// The node that positions the attached players. Change its rendering algorithm or reverb here.
    public let environment = AVAudioEnvironmentNode()
    private var attached: [ObjectIdentifier: AudioPlayer] = [:]

    /// Creates a mixer.
    ///
    /// - Parameter engine: The engine to use. For offline rendering, for example in tests, pass an engine in manual
    ///   rendering mode. By default, the mixer plays through the engine's output.
    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
    }

    /// The players that are attached to the mixer, in no particular order.
    public var attachedPlayers: [AudioPlayer] {
        Array(attached.values)
    }

    /// The world transform of the listener.
    ///
    /// The mixer uses the translation as the listener position, -Z as forward and +Y as up, like a camera.
    public var listenerTransform: simd_float4x4 = matrix_identity_float4x4 {
        didSet {
            let matrix = listenerTransform
            environment.listenerPosition = AVAudio3DPoint(x: matrix.columns.3.x, y: matrix.columns.3.y, z: matrix.columns.3.z)
            let forward = -simd_normalize(SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
            let up = simd_normalize(SIMD3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z))
            environment.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z), up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))
        }
    }

    /// Returns whether the player is attached to this mixer.
    public func isAttached(_ player: AudioPlayer) -> Bool {
        attached[ObjectIdentifier(player)] != nil
    }

    /// Connects the player to the mixer so that it can play. Attaching an attached player does nothing.
    public func attach(_ player: AudioPlayer) {
        guard !isAttached(player) else {
            return
        }
        engine.attach(player.playerNode)
        engine.connect(player.playerNode, to: environment, format: player.buffer.format)
        attached[ObjectIdentifier(player)] = player
    }

    /// Stops the player and removes it from the engine.
    public func detach(_ player: AudioPlayer) {
        guard attached.removeValue(forKey: ObjectIdentifier(player)) != nil else {
            return
        }
        player.playerNode.stop()
        engine.detach(player.playerNode)
        player.isScheduled = false
    }

    /// Plays or resumes an attached player, and starts the engine if it is stopped.
    ///
    /// A player that is not attached does not play.
    ///
    /// - Throws: An `AVAudioEngine` error if the engine cannot start.
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

    /// Pauses the player. Call ``play(_:)`` to resume it.
    public func pause(_ player: AudioPlayer) {
        player.playerNode.pause()
    }
}
