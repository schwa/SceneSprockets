import simd

extension SceneGraph {
    /// The contribution of one clip to a mix.
    public struct AnimationLayer: Sendable, Equatable {
        /// How a layer combines with the other layers.
        public enum Mode: Sendable, Equatable {
            /// The layer blends with the other override layers by normalized weight.
            case override
            /// The layer adds the clip's offset from the rest pose, scaled by the weight, on top of the override layers.
            case additive
        }

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
                addDeltas(of: layer, to: &values)
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
                Self.set(value, on: node, path: key.path)
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
            let totalWeight = layers.reduce(0) { $0 + $1.weight }
            guard totalWeight > 0 else {
                return [:]
            }
            var contributions: [Key: [(weight: Float, value: [Float])]] = [:]
            for layer in layers {
                for (key, value) in sampled(layer) {
                    contributions[key, default: []].append((layer.weight / totalWeight, value))
                }
            }
            var result: [Key: [Float]] = [:]
            for (key, list) in contributions {
                var list = list
                let covered = list.reduce(0) { $0 + $1.weight }
                if covered < 1 - 1e-6, let restValue = rest[key] {
                    list.append((1 - covered, restValue))
                }
                result[key] = Self.blend(list, isRotation: key.path == .rotation)
            }
            return result
        }

        private func addDeltas(of layer: AnimationLayer, to values: inout [Key: [Float]]) {
            let weight = layer.weight
            for (key, sample) in sampled(layer) {
                guard let restValue = rest[key], let base = values[key], sample.count == restValue.count, base.count == restValue.count else {
                    continue
                }
                switch key.path {
                case .rotation where restValue.count == 4:
                    let restRotation = simd_quatf(vector: SIMD4(restValue[0], restValue[1], restValue[2], restValue[3]))
                    let sampledRotation = simd_quatf(vector: SIMD4(sample[0], sample[1], sample[2], sample[3]))
                    let baseRotation = simd_quatf(vector: SIMD4(base[0], base[1], base[2], base[3]))
                    let delta = simd_slerp(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), restRotation.inverse * sampledRotation, weight)
                    let result = simd_normalize(baseRotation * delta).vector
                    values[key] = [result.x, result.y, result.z, result.w]
                case .scale:
                    values[key] = (0..<3).map { index in
                        restValue[index] == 0 ? base[index] : base[index] * pow(sample[index] / restValue[index], weight)
                    }
                default:
                    values[key] = (0..<restValue.count).map { base[$0] + (sample[$0] - restValue[$0]) * weight }
                }
            }
        }

        // Weighted average; rotations use normalized linear interpolation on the first value's side.
        private static func blend(_ list: [(weight: Float, value: [Float])], isRotation: Bool) -> [Float] {
            guard list.count > 1 else {
                return list.first?.value ?? []
            }
            let count = list.map(\.value.count).min() ?? 0
            let reference = list[0].value
            var result = [Float](repeating: 0, count: count)
            var totalWeight: Float = 0
            for (weight, value) in list {
                var sign: Float = 1
                if isRotation {
                    let dot = zip(reference.prefix(count), value.prefix(count)).reduce(0) { $0 + $1.0 * $1.1 }
                    sign = dot < 0 ? -1 : 1
                }
                for index in 0..<count {
                    result[index] += value[index] * weight * sign
                }
                totalWeight += weight
            }
            if isRotation {
                let length = sqrt(result.reduce(0) { $0 + $1 * $1 })
                return length > 0 ? result.map { $0 / length } : reference
            }
            return totalWeight > 0 ? result.map { $0 / totalWeight } : reference
        }

        private static func value(of node: Node, path: AnimationClip.Path) -> [Float] {
            let trs = node.trs
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

        private static func set(_ value: [Float], on node: Node, path: AnimationClip.Path) {
            path.set(value, on: node)
        }
    }

    /// A controller that plays clips by index, with cross-fades, blends and additive clips.
    ///
    /// Each clip has its own speed and looping. ``blend(_:parameter:speed:syncsPhase:)`` mixes clips by one parameter
    /// and can keep their cycles in phase. The controller is a value: call `advance(by:)` each frame, then apply its
    /// layers with an ``AnimationMixer``.
    public struct AnimationController: Sendable {
        /// A clip that the controller plays, with its time and weight.
        public struct Track: Sendable, Equatable {
            /// The index of the clip.
            public var clip: Int
            /// The time in the clip, in seconds.
            public var time: Float = 0
            /// The playback speed. 1 is normal speed.
            public var speed: Float = 1
            /// Whether the clip repeats.
            public var loops = true
            /// The current weight of the track. It changes during a cross-fade.
            public internal(set) var weight: Float
            var targetWeight: Float
            var fadeRate: Float = 0
        }

        /// The duration of each clip, in seconds, by clip index.
        public let durations: [Float]
        /// The override tracks that play now, including tracks that fade out.
        public private(set) var tracks: [Track] = []
        /// The shared fraction of the cycle of a phase-synced blend, or `nil` when no synced blend plays.
        public private(set) var syncedPhase: Float?
        /// The additive tracks that play on top of the override tracks.
        public private(set) var additiveTracks: [Track] = []
        /// How far the root node moved (x, z) during the last advance(by:mixer:rootMotionNode:).
        public private(set) var rootMotion: SIMD3<Float> = .zero

        /// Creates a controller for clips with these durations, in seconds.
        public init(durations: [Float]) {
            self.durations = durations
        }

        /// Creates a controller for these clips.
        public init(clips: [AnimationClip]) {
            self.init(durations: clips.map(\.duration))
        }

        /// Fades `clip` in and every other track out over `fadeDuration` (0 cuts).
        public mutating func play(_ clip: Int, fadeDuration: Float = 0.25, speed: Float = 1, loops: Bool = true, restarts: Bool = false) {
            guard durations.indices.contains(clip) else {
                return
            }
            syncedPhase = nil
            let rate: Float = fadeDuration > 0 ? 1 / fadeDuration : .infinity
            for index in tracks.indices {
                tracks[index].targetWeight = 0
                tracks[index].fadeRate = rate
            }
            if let index = tracks.firstIndex(where: { $0.clip == clip }) {
                tracks[index].targetWeight = 1
                tracks[index].speed = speed
                tracks[index].loops = loops
                if restarts {
                    tracks[index].time = 0
                }
            } else {
                tracks.append(Track(clip: clip, speed: speed, loops: loops, weight: 0, targetWeight: 1, fadeRate: rate))
            }
            if fadeDuration <= 0 {
                for index in tracks.indices {
                    tracks[index].weight = tracks[index].targetWeight
                }
                tracks.removeAll { $0.weight <= 0 }
            }
        }

        /// Plays `clips` together, weighted by `parameter` along them. With `syncsPhase`, all clips stay at the same
        /// fraction of their cycle, and the cycle lasts the weighted mix of their durations.
        public mutating func blend(_ clips: [Int], parameter: Float, speed: Float = 1, syncsPhase: Bool = true) {
            let clips = clips.filter { durations.indices.contains($0) }
            let weights = Self.blendWeights(parameter: parameter, count: clips.count)
            var blended: [Track] = []
            for (clip, weight) in zip(clips, weights) {
                var track = tracks.first { $0.clip == clip } ?? Track(clip: clip, weight: weight, targetWeight: weight)
                track.weight = weight
                track.targetWeight = weight
                track.fadeRate = 0
                track.speed = speed
                track.loops = true
                blended.append(track)
            }
            tracks = blended
            if syncsPhase {
                let phase = syncedPhase ?? blended.first.map { durations[$0.clip] > 0 ? $0.time / durations[$0.clip] : 0 } ?? 0
                syncedPhase = phase
                applyPhase(phase)
            } else {
                syncedPhase = nil
            }
        }

        /// Weights for `count` clips evenly spaced along `parameter` (clamped to 0...1); they sum to 1.
        public static func blendWeights(parameter: Float, count: Int) -> [Float] {
            guard count > 1 else {
                return count == 1 ? [1] : []
            }
            let position = min(max(parameter, 0), 1) * Float(count - 1)
            let lower = min(Int(position), count - 2)
            let fraction = position - Float(lower)
            var weights = [Float](repeating: 0, count: count)
            weights[lower] = 1 - fraction
            weights[lower + 1] = fraction
            return weights
        }

        /// Adds `clip` on top of the playing clips at `weight` (0 removes it).
        public mutating func setAdditive(_ clip: Int, weight: Float, speed: Float = 1) {
            guard durations.indices.contains(clip) else {
                return
            }
            if weight <= 0 {
                additiveTracks.removeAll { $0.clip == clip }
            } else if let index = additiveTracks.firstIndex(where: { $0.clip == clip }) {
                additiveTracks[index].weight = weight
                additiveTracks[index].speed = speed
            } else {
                additiveTracks.append(Track(clip: clip, speed: speed, weight: weight, targetWeight: weight))
            }
        }

        /// Advances like advance(by:), and measures how far the clips moved `rootMotionNode` horizontally.
        public mutating func advance(by seconds: Float, mixer: AnimationMixer, rootMotionNode node: Node) {
            let before = tracks
            advance(by: seconds)
            func translation(_ clip: Int, _ time: Float) -> SIMD3<Float> {
                mixer.rootTranslation(layers: [AnimationLayer(clip: clip, time: time)], node: node)
            }
            var motion = SIMD3<Float>.zero
            var totalWeight: Float = 0
            for track in tracks {
                guard let old = before.first(where: { $0.clip == track.clip }) else {
                    continue
                }
                let duration = durations[track.clip]
                var delta = translation(track.clip, track.time) - translation(track.clip, old.time)
                // Moving forward but ending up earlier means the clip looped: add the end-to-start jump back.
                if track.loops, track.speed > 0, track.time < old.time {
                    delta += translation(track.clip, duration) - translation(track.clip, 0)
                } else if track.loops, track.speed < 0, track.time > old.time {
                    delta -= translation(track.clip, duration) - translation(track.clip, 0)
                }
                motion += delta * track.weight
                totalWeight += track.weight
            }
            rootMotion = totalWeight > 0 ? motion / totalWeight : .zero
            rootMotion.y = 0
        }

        /// Moves clip times and fades forward; fully faded-out tracks are dropped.
        public mutating func advance(by seconds: Float) {
            for index in additiveTracks.indices {
                additiveTracks[index].time = wrapped(additiveTracks[index].time + seconds * additiveTracks[index].speed, duration: durations[additiveTracks[index].clip])
            }
            if let phase = syncedPhase {
                let cycle = tracks.reduce(0) { $0 + $1.weight * durations[$1.clip] }
                let speed = tracks.first?.speed ?? 1
                let next = cycle > 0 ? phase + seconds * speed / cycle : phase
                syncedPhase = next - next.rounded(.down)
                applyPhase(syncedPhase ?? 0)
            } else {
                for index in tracks.indices {
                    let duration = durations[tracks[index].clip]
                    let time = tracks[index].time + seconds * tracks[index].speed
                    tracks[index].time = tracks[index].loops ? wrapped(time, duration: duration) : min(max(time, 0), duration)
                }
            }
            for index in tracks.indices {
                let step = tracks[index].fadeRate * seconds
                let target = tracks[index].targetWeight
                let weight = tracks[index].weight
                tracks[index].weight = weight < target ? min(weight + step, target) : max(weight - step, target)
            }
            tracks.removeAll { $0.weight <= 0 && $0.targetWeight <= 0 }
        }

        /// Override weights normalized to sum to 1, then the additive tracks.
        public var layers: [AnimationLayer] {
            let additive = additiveTracks.map { AnimationLayer(clip: $0.clip, time: $0.time, weight: $0.weight, mode: .additive) }
            let total = tracks.reduce(0) { $0 + $1.weight }
            guard total > 0 else {
                // Mid cut with nothing faded in yet: show the newest clip.
                return (tracks.last.map { [AnimationLayer(clip: $0.clip, time: $0.time)] } ?? []) + additive
            }
            return tracks.filter { $0.weight > 0 }.map { AnimationLayer(clip: $0.clip, time: $0.time, weight: $0.weight / total) } + additive
        }

        private func wrapped(_ time: Float, duration: Float) -> Float {
            guard duration > 0 else {
                return time
            }
            let result = time.truncatingRemainder(dividingBy: duration)
            return result < 0 ? result + duration : result
        }

        private mutating func applyPhase(_ phase: Float) {
            for index in tracks.indices {
                tracks[index].time = phase * durations[tracks[index].clip]
            }
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
        public struct Context: Sendable {
            /// The parameters of the state machine, by name.
            public var parameters: [String: Float]
            /// How far through its clip the current state is, from 0 to 1.
            ///
            /// The value is more than 1 after a clip that does not loop has finished.
            public var normalizedTime: Float
            /// The time since the current state started, in seconds.
            public var stateTime: Float
        }

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
        /// The name of the current state.
        public private(set) var currentState: String
        /// The time since the current state started, in seconds.
        public private(set) var stateTime: Float = 0
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
            precondition(states.contains { $0.name == initial }, "The initial state must be one of the states")
            self.states = Dictionary(states.map { ($0.name, $0) }) { first, _ in first }
            self.transitions = transitions
            self.controller = controller
            currentState = initial
            enter(initial, fadeDuration: 0)
        }

        /// The values that transition conditions test now.
        public var context: Context {
            let state = states[currentState]
            let duration = state.map { controller.durations[$0.clip] } ?? 0
            let time = state.flatMap { state in controller.tracks.first { $0.clip == state.clip } }?.time ?? 0
            let normalized: Float
            if let state, !state.loops, duration > 0 {
                // A finished non-looping clip holds its last frame; report it past the end so "on finish" fires.
                normalized = stateTime * abs(state.speed) >= duration ? max(time / duration, 1) + 1e-6 : time / duration
            } else {
                normalized = duration > 0 ? time / duration : 0
            }
            return Context(parameters: parameters, normalizedTime: normalized, stateTime: stateTime)
        }

        /// Takes at most one transition, then advances the controller.
        public mutating func advance(by seconds: Float) {
            let context = context
            if let transition = transitions.first(where: { ($0.from == nil || $0.from == currentState) && $0.to != currentState && states[$0.to] != nil && $0.condition(context) }) {
                enter(transition.to, fadeDuration: transition.fadeDuration)
            }
            stateTime += seconds
            controller.advance(by: seconds)
        }

        private mutating func enter(_ name: String, fadeDuration: Float) {
            guard let state = states[name] else {
                return
            }
            currentState = name
            stateTime = 0
            controller.play(state.clip, fadeDuration: fadeDuration, speed: state.speed, loops: state.loops, restarts: true)
        }
    }
}
