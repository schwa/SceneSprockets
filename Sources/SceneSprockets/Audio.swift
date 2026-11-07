import GeometryLite3D
import SceneSprocketsAudio
import simd

/// Plays every node's audio players in 3D, like SCNView's audioEngine and audioListener. Call `update` each frame
/// with the listener's world transform (usually the camera); players on hidden nodes are paused, and players that
/// leave the graph are detached.
public final class SceneAudio {
    /// The mixer that plays and positions the players.
    public let mixer: SpatialAudioMixer

    /// Creates scene audio that plays through a mixer.
    public init(mixer: SpatialAudioMixer = SpatialAudioMixer()) {
        self.mixer = mixer
    }

    /// Moves each player to its node, and attaches, plays, pauses or detaches players to match the scene graph.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene graph whose nodes have the audio players.
    ///   - listener: The world transform of the listener, usually the camera.
    /// - Throws: An error if the audio engine cannot start.
    public func update(sceneGraph: SceneGraph, listener: simd_float4x4) throws {
        mixer.listenerTransform = listener
        var visible: [ObjectIdentifier: (player: AudioPlayer, position: SIMD3<Float>)] = [:]
        sceneGraph.visit { node, worldTransform in
            for player in node.audioPlayers {
                visible[ObjectIdentifier(player)] = (player, worldTransform.columns.3.xyz)
            }
        }
        var all: [ObjectIdentifier: AudioPlayer] = [:]
        sceneGraph.visit(includeHidden: true) { node, _ in
            for player in node.audioPlayers {
                all[ObjectIdentifier(player)] = player
            }
        }
        for player in mixer.attachedPlayers where all[ObjectIdentifier(player)] == nil {
            mixer.detach(player)
        }
        for player in all.values {
            mixer.attach(player)
        }
        for player in all.values {
            guard let entry = visible[ObjectIdentifier(player)] else {
                mixer.pause(player)
                continue
            }
            player.position = entry.position
            try mixer.play(player)
        }
    }
}
