import MetalSprocketsAnimation
import simd

// The blending, playback and state logic is shared with MetalSprocketsGLTF through MetalSprocketsAnimation (#589).

extension SceneGraph {
    /// The contribution of one clip to a mix.
    public struct AnimationLayer: Sendable, Equatable {
        /// How a layer combines with the other layers.
        public typealias Mode = AnimationBlendMode

        /// The index of the clip in ``AnimationMixer/clips``.
        public var clip: Int
        /// The time in the clip, in seconds.
        public var time: Float
        /// The weight of the layer, from 0 (no effect) to 1.
        public var weight: Float
        /// How the layer combines with the other layers.
        public var mode: Mode

        /// Creates a layer.
        ///
        /// - Parameters:
        ///   - clip: The index of the clip in ``AnimationMixer/clips``.
        ///   - time: The time in the clip, in seconds.
        ///   - weight: The weight of the layer, from 0 to 1.
        ///   - mode: How the layer combines with the other layers.
        public init(clip: Int, time: Float, weight: Float = 1, mode: Mode = .override) {
            self.clip = clip
            self.time = time
            self.weight = weight
            self.mode = mode
        }
    }

    /// A mixer that blends layers of clips into the nodes that the clips target.
    ///
    /// The mixer records rest values from the nodes when you create it, or when you call ``captureRest()``. For a layer
    /// that does not animate a node, the node has its rest value.
    public final class AnimationMixer {
        /// The clips that layers refer to by index.
        public let clips: [AnimationClip]

        struct Key: Hashable {
            var node: ObjectIdentifier
            var path: AnimationClip.Path
        }

        private var nodes: [ObjectIdentifier: Node] = [:]
        private var rest: [Key: [Float]] = [:]

        /// Creates a mixer and records the rest values of the nodes that the clips target.
        public init(clips: [AnimationClip]) {
            self.clips = clips
            captureRest()
        }

        /// Records every targeted node's current translation, rotation, scale and morph weights as its rest value.
        public func captureRest() {
            rest = [:]
            for clip in clips {
                for channel in clip.channels {
                    let node = channel.target
                    nodes[ObjectIdentifier(node)] = node
                    rest[Key(node: ObjectIdentifier(node), path: channel.path)] = Self.value(of: node, path: channel.path)
                }
            }
        }

        /// Sets every targeted node from `layers`. With `rootMotionNode`, that node's x and z translation stay at rest.
        public func apply(_ layers: [AnimationLayer], rootMotionNode: Node? = nil) {
            let active = layers.filter { clips.indices.contains($0.clip) && $0.weight > 0 }
            var values = rest
            for (key, value) in blendedValues(active.filter { $0.mode == .override }) {
                values[key] = value
            }
            for layer in active where layer.mode == .additive {
                AnimationBlending.addDeltas(sampled(layer), weight: layer.weight, to: &values, rest: { self.rest[$0] }, kind: Self.kind)
            }
            if let rootMotionNode {
                let key = Key(node: ObjectIdentifier(rootMotionNode), path: .translation)
                if let restValue = rest[key], var translation = values[key], translation.count == 3 {
                    translation[0] = restValue[0]
                    translation[2] = restValue[2]
                    values[key] = translation
                }
            }
            for (key, value) in values {
                guard let node = nodes[key.node] else {
                    continue
                }
                key.path.set(value, on: node)
            }
        }

        /// The translation the override layers give `node`, before root motion is removed.
        public func rootTranslation(layers: [AnimationLayer], node: Node) -> SIMD3<Float> {
            let key = Key(node: ObjectIdentifier(node), path: .translation)
            let overrides = layers.filter { clips.indices.contains($0.clip) && $0.weight > 0 && $0.mode == .override }
            let value = blendedValues(overrides)[key] ?? rest[key] ?? [0, 0, 0]
            return value.count == 3 ? SIMD3(value[0], value[1], value[2]) : .zero
        }

        private func sampled(_ layer: AnimationLayer) -> [Key: [Float]] {
            // Within one clip a later channel for the same target wins.
            var result: [Key: [Float]] = [:]
            for channel in clips[layer.clip].channels {
                result[Key(node: ObjectIdentifier(channel.target), path: channel.path)] = channel.sampler.sample(at: layer.time, isRotation: channel.path == .rotation)
            }
            return result
        }

        private func blendedValues(_ layers: [AnimationLayer]) -> [Key: [Float]] {
            AnimationBlending.blendedValues(layers.map { ($0.weight, sampled($0)) }, rest: { rest[$0] }, kind: Self.kind)
        }

        private static func kind(_ key: Key) -> AnimationValueKind {
            switch key.path {
            case .rotation: .rotation
            case .scale: .scale
            default: .linear
            }
        }

        private static func value(of node: Node, path: AnimationClip.Path) -> [Float] {
            let trs = node.transform
            switch path {
            case .translation:
                return [trs.translation.x, trs.translation.y, trs.translation.z]
            case .rotation:
                return [trs.rotation.quaternion.vector.x, trs.rotation.quaternion.vector.y, trs.rotation.quaternion.vector.z, trs.rotation.quaternion.vector.w]
            case .scale:
                return [trs.scale.x, trs.scale.y, trs.scale.z]
            case .weights:
                return node.morphWeights
            case .property(let property):
                return property.get(node)
            }
        }
    }

    /// A controller that plays clips by index, with cross-fades, blends and additive clips.
    ///
    /// Each clip has its own speed and looping. ``blend(_:parameter:speed:syncsPhase:)`` mixes clips by one parameter
    /// and can keep their cycles in phase. The controller is a value: call `advance(by:)` each frame, then apply its
    /// layers with an ``AnimationMixer``.
    public struct AnimationController: Sendable {
        /// A clip that the controller plays, with its time and weight.
        public typealias Track = AnimationPlayback.Track

        var playback: AnimationPlayback

        /// The duration of each clip, in seconds, by clip index.
        public var durations: [Float] { playback.durations }
        /// The override tracks that play now, including tracks that fade out.
        public var tracks: [Track] { playback.tracks }
        /// The shared fraction of the cycle of a phase-synced blend, or `nil` when no synced blend plays.
        public var syncedPhase: Float? { playback.syncedPhase }
        /// The additive tracks that play on top of the override tracks.
        public var additiveTracks: [Track] { playback.additiveTracks }
        /// How far the root node moved (x, z) during the last advance(by:mixer:rootMotionNode:).
        public private(set) var rootMotion: SIMD3<Float> = .zero

        /// Creates a controller for clips with these durations, in seconds.
        public init(durations: [Float]) {
            playback = AnimationPlayback(durations: durations)
        }

        /// Creates a controller for these clips.
        public init(clips: [AnimationClip]) {
            self.init(durations: clips.map(\.duration))
        }

        /// Fades `clip` in and every other track out over `fadeDuration` (0 cuts).
        public mutating func play(_ clip: Int, fadeDuration: Float = 0.25, speed: Float = 1, loops: Bool = true, restarts: Bool = false) {
            playback.play(clip, fadeDuration: fadeDuration, speed: speed, loops: loops, restarts: restarts)
        }

        /// Plays `clips` together, weighted by `parameter` along them. With `syncsPhase`, all clips stay at the same
        /// fraction of their cycle, and the cycle lasts the weighted mix of their durations.
        public mutating func blend(_ clips: [Int], parameter: Float, speed: Float = 1, syncsPhase: Bool = true) {
            playback.blend(clips, parameter: parameter, speed: speed, syncsPhase: syncsPhase)
        }

        /// Weights for `count` clips evenly spaced along `parameter` (clamped to 0...1); they sum to 1.
        public static func blendWeights(parameter: Float, count: Int) -> [Float] {
            AnimationPlayback.blendWeights(parameter: parameter, count: count)
        }

        /// Adds `clip` on top of the playing clips at `weight` (0 removes it).
        public mutating func setAdditive(_ clip: Int, weight: Float, speed: Float = 1) {
            playback.setAdditive(clip, weight: weight, speed: speed)
        }

        /// Advances like advance(by:), and measures how far the clips moved `rootMotionNode` horizontally.
        public mutating func advance(by seconds: Float, mixer: AnimationMixer, rootMotionNode node: Node) {
            let before = playback.tracks
            advance(by: seconds)
            rootMotion = playback.rootMotion(since: before) { clip, time in
                mixer.rootTranslation(layers: [AnimationLayer(clip: clip, time: time)], node: node)
            }
        }

        /// Moves clip times and fades forward; fully faded-out tracks are dropped.
        public mutating func advance(by seconds: Float) {
            playback.advance(by: seconds)
        }

        /// Override weights normalized to sum to 1, then the additive tracks.
        public var layers: [AnimationLayer] {
            playback.layers.map { AnimationLayer(clip: $0.clip, time: $0.time, weight: $0.weight, mode: $0.mode) }
        }
    }

    /// A state machine that chooses which clip plays, from named states and transitions.
    ///
    /// The state machine plays its clips with an ``AnimationController``.
    public struct AnimationStateMachine {
        /// A named state that plays one clip.
        public struct State: Sendable {
            /// The name of the state. Transitions refer to it.
            public var name: String
            /// The index of the clip that the state plays.
            public var clip: Int
            /// The playback speed of the clip.
            public var speed: Float
            /// Whether the clip repeats.
            public var loops: Bool

            /// Creates a state.
            ///
            /// - Parameters:
            ///   - name: The name of the state.
            ///   - clip: The index of the clip that the state plays.
            ///   - speed: The playback speed of the clip.
            ///   - loops: Whether the clip repeats.
            public init(_ name: String, clip: Int, speed: Float = 1, loops: Bool = true) {
                self.name = name
                self.clip = clip
                self.speed = speed
                self.loops = loops
            }
        }

        /// The values that a transition condition can test.
        public typealias Context = AnimationStateContext

        /// A change from one state to another when a condition is true.
        public struct Transition {
            /// The name of the state that the transition leaves, or `nil` to leave any state.
            public var from: String?
            /// The name of the state that the transition enters.
            public var to: String
            /// The duration of the cross-fade, in seconds. 0 cuts.
            public var fadeDuration: Float
            /// The test that starts the transition.
            public var condition: (Context) -> Bool

            /// Creates a transition.
            ///
            /// - Parameters:
            ///   - from: The name of the state that the transition leaves, or `nil` for any state.
            ///   - to: The name of the state that the transition enters.
            ///   - fadeDuration: The duration of the cross-fade, in seconds.
            ///   - condition: The test that starts the transition.
            public init(from: String?, to: String, fadeDuration: Float = 0.25, when condition: @escaping (Context) -> Bool) {
                self.from = from
                self.to = to
                self.fadeDuration = fadeDuration
                self.condition = condition
            }
        }

        /// The states, by name.
        public let states: [String: State]
        /// The transitions, in the order that the state machine tests them.
        public let transitions: [Transition]
        /// Values that transition conditions can test, by name. Set them from your game logic.
        public var parameters: [String: Float] = [:]
        private var core: AnimationStates
        /// The name of the current state.
        public var currentState: String { core.currentState }
        /// The time since the current state started, in seconds.
        public var stateTime: Float { core.stateTime }
        /// The controller that plays the clips. Apply its layers with an ``AnimationMixer``.
        public var controller: AnimationController

        /// Creates a state machine in its initial state.
        ///
        /// The state machine tests transitions in order and takes the first one whose condition is true.
        ///
        /// - Parameters:
        ///   - controller: The controller that plays the clips.
        ///   - states: The states. Their names must be different.
        ///   - transitions: The transitions, in the order to test them.
        ///   - initial: The name of the first state. It must be one of `states`.
        public init(controller: AnimationController, states: [State], transitions: [Transition], initial: String) {
            self.states = Dictionary(states.map { ($0.name, $0) }) { first, _ in first }
            self.transitions = transitions
            var controller = controller
            core = AnimationStates(states: self.states.mapValues { .init(clip: $0.clip, speed: $0.speed, loops: $0.loops) }, initial: initial, playback: &controller.playback)
            self.controller = controller
        }

        /// The values that transition conditions test now.
        public var context: Context {
            core.context(parameters: parameters, playback: controller.playback)
        }

        /// Takes at most one transition, then advances the controller.
        public mutating func advance(by seconds: Float) {
            let context = context
            let transition = transitions.first { core.canTake(from: $0.from, to: $0.to) && $0.condition(context) }
            core.advance(by: seconds, transitionTo: transition.map { ($0.to, $0.fadeDuration) }, playback: &controller.playback)
            controller.advance(by: seconds)
        }
    }
}
