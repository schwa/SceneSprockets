import AVFAudio
import simd

extension SceneGraph {
    // A sound attached to a node, like SCNAudioPlayer: it plays from the node's world position. Add it to a node's
    // `audioPlayers` and drive the graph with a SceneAudio. Only mono buffers are positioned; AVAudioEnvironmentNode
    // passes stereo through.
    public final class AudioPlayer {
        public let buffer: AVAudioPCMBuffer
        public var loops: Bool
        // 0...1.
        public var volume: Float {
            didSet { playerNode.volume = volume }
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

        // The world position last set by SceneAudio.update.
        public var position: SIMD3<Float> {
            let position = playerNode.position
            return [position.x, position.y, position.z]
        }
    }

    public enum AudioError: Error {
        case bufferCreationFailed
    }
}

// Plays every node's audio players in 3D, like SCNView's audioEngine and audioListener. Call `update` each frame
// with the listener's world transform (usually the camera); players on hidden nodes are paused.
public final class SceneAudio {
    public let engine: AVAudioEngine
    public let environment = AVAudioEnvironmentNode()
    private var attached: [ObjectIdentifier: SceneGraph.AudioPlayer] = [:]

    // Pass an engine in manual rendering mode for offline use (tests); otherwise the engine's output is used.
    public init(engine: AVAudioEngine = AVAudioEngine()) {
        self.engine = engine
        engine.attach(environment)
        engine.connect(environment, to: engine.mainMixerNode, format: nil)
    }

    public func update(sceneGraph: SceneGraph, listener: simd_float4x4) throws {
        let position = listener.columns.3
        environment.listenerPosition = AVAudio3DPoint(x: position.x, y: position.y, z: position.z)
        let forward = -simd_normalize(SIMD3(listener.columns.2.x, listener.columns.2.y, listener.columns.2.z))
        let up = simd_normalize(SIMD3(listener.columns.1.x, listener.columns.1.y, listener.columns.1.z))
        environment.listenerVectorOrientation = AVAudio3DVectorOrientation(forward: AVAudio3DVector(x: forward.x, y: forward.y, z: forward.z), up: AVAudio3DVector(x: up.x, y: up.y, z: up.z))

        var visible: [ObjectIdentifier: (player: SceneGraph.AudioPlayer, position: SIMD3<Float>)] = [:]
        sceneGraph.visit { node, worldTransform in
            for player in node.audioPlayers {
                visible[ObjectIdentifier(player)] = (player, SIMD3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z))
            }
        }
        var all = visible.mapValues(\.player)
        sceneGraph.visit(includeHidden: true) { node, _ in
            for player in node.audioPlayers {
                all[ObjectIdentifier(player)] = player
            }
        }
        // Detach players that left the graph.
        for (key, player) in attached where all[key] == nil {
            player.playerNode.stop()
            engine.detach(player.playerNode)
            attached[key] = nil
            player.isScheduled = false
        }
        for (key, player) in all where attached[key] == nil {
            engine.attach(player.playerNode)
            engine.connect(player.playerNode, to: environment, format: player.buffer.format)
            attached[key] = player
        }
        if !engine.isRunning {
            try engine.start()
        }
        for (key, player) in attached {
            guard let entry = visible[key] else {
                player.playerNode.pause()
                continue
            }
            player.playerNode.position = AVAudio3DPoint(x: entry.position.x, y: entry.position.y, z: entry.position.z)
            if !player.isScheduled {
                player.playerNode.scheduleBuffer(player.buffer, at: nil, options: player.loops ? .loops : [])
                player.isScheduled = true
            }
            if !player.playerNode.isPlaying {
                player.playerNode.play()
            }
        }
    }

}
