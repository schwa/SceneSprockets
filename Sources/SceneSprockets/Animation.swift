import GeometryLite3D
import simd

extension SceneGraph {
    /// A keyframe animation that does not depend on a file format.
    ///
    /// Channels animate node translation, rotation, scale, morph weights, or any other value through a ``Property``.
    public struct AnimationClip {
        /// The value of a node that a channel animates.
        public enum Path: Hashable {
            /// The translation, as 3 values.
            case translation
            /// The rotation, as a quaternion in 4 values (x, y, z, w).
            case rotation
            /// The scale, as 3 values.
            case scale
            /// The morph weights, one value for each morph target.
            case weights
            /// Any other value, such as a light intensity or a material value, like a `CAAnimation` key path.
            case property(Property)

            func set(_ value: [Float], on node: Node) {
                switch self {
                case .translation where value.count == 3:
                    node.trs.translation = SIMD3(value[0], value[1], value[2])
                case .rotation where value.count == 4:
                    node.trs.rotation = simd_quatf(vector: SIMD4(value[0], value[1], value[2], value[3]))
                case .scale where value.count == 3:
                    node.trs.scale = SIMD3(value[0], value[1], value[2])
                case .weights:
                    node.morphWeights = value
                case .property(let property):
                    property.set(node, value)
                default:
                    break
                }
            }
        }

        /// A named value that a channel can animate.
        ///
        /// Two properties are equal when their names are equal, so use one name for each value.
        public struct Property: Hashable {
            /// The name that identifies the value.
            public var name: String
            /// Reads the node's current value. ``AnimationMixer`` uses it as the rest value.
            public var get: (Node) -> [Float]
            /// Writes a value to the node.
            public var set: (Node, [Float]) -> Void

            /// Creates a property.
            ///
            /// - Parameters:
            ///   - name: The name that identifies the value.
            ///   - get: Reads the node's current value.
            ///   - set: Writes a value to the node.
            public init(name: String, get: @escaping (Node) -> [Float], set: @escaping (Node, [Float]) -> Void) {
                self.name = name
                self.get = get
                self.set = set
            }

            public static func == (lhs: Self, rhs: Self) -> Bool {
                lhs.name == rhs.name
            }

            public func hash(into hasher: inout Hasher) {
                hasher.combine(name)
            }

            /// The intensity of a light node.
            public static var lightIntensity: Self { Self(name: "light.intensity") { node in
                if case let .light(light) = node.content { [light.intensity] } else { [] }
            } set: { node, value in
                if case var .light(light) = node.content, let intensity = value.first {
                    light.intensity = intensity
                    node.content = .light(light)
                }
            }
            }

            /// The linear RGB color of a light node.
            public static var lightColor: Self { Self(name: "light.color") { node in
                if case let .light(light) = node.content { [light.color.x, light.color.y, light.color.z] } else { [] }
            } set: { node, value in
                if case var .light(light) = node.content, value.count == 3 {
                    light.color = SIMD3(value[0], value[1], value[2])
                    node.content = .light(light)
                }
            }
            }

            /// isVisible as 0 or 1; values above 0.5 show the node.
            public static var visibility: Self { Self(name: "isVisible") { node in
                [node.isVisible ? 1 : 0]
            } set: { node, value in
                if let visible = value.first {
                    node.isVisible = visible > 0.5
                }
            }
            }

            static func light(_ name: String, _ keyPath: WritableKeyPath<Light, Float>) -> Self {
                Self(name: "light.\(name)") { node in
                    if case let .light(light) = node.content { [light[keyPath: keyPath]] } else { [] }
                } set: { node, value in
                    if case var .light(light) = node.content, let newValue = value.first {
                        light[keyPath: keyPath] = newValue
                        node.content = .light(light)
                    }
                }
            }

            /// The range of a light node.
            public static var lightRange: Self { light("range", \.range) }
            /// The inner cone angle of a spot light node, in radians.
            public static var lightInnerConeAngle: Self { light("innerConeAngle", \.innerConeAngle) }
            /// The outer cone angle of a spot light node, in radians.
            public static var lightOuterConeAngle: Self { light("outerConeAngle", \.outerConeAngle) }

            /// A perspective camera's vertical field of view, in radians.
            public static var cameraVerticalFieldOfView: Self { Self(name: "camera.verticalFieldOfView") { node in
                if case let .camera(camera) = node.content, let projection = camera.projection as? PerspectiveProjection { [projection.verticalAngleOfView.radians] } else { [] }
            } set: { node, value in
                if case var .camera(camera) = node.content, var projection = camera.projection as? PerspectiveProjection, let radians = value.first {
                    projection.verticalAngleOfView = .radians(radians)
                    camera.projection = projection
                    node.content = .camera(camera)
                }
            }
            }

            /// An orthographic camera's half height.
            public static var cameraHalfHeight: Self { Self(name: "camera.halfHeight") { node in
                if case let .camera(camera) = node.content, let projection = camera.projection as? OrthographicProjection { [projection.halfHeight] } else { [] }
            } set: { node, value in
                if case var .camera(camera) = node.content, var projection = camera.projection as? OrthographicProjection, let halfHeight = value.first {
                    projection.halfHeight = halfHeight
                    camera.projection = projection
                    node.content = .camera(camera)
                }
            }
            }

            // The near (isNear) or far clip plane of a perspective or orthographic camera with a clip range.
            static func cameraClip(isNear: Bool) -> Self {
                func clip(_ range: ClosedRange<Float>, _ value: Float) -> ClosedRange<Float> {
                    isNear ? min(value, range.upperBound)...range.upperBound : range.lowerBound...max(value, range.lowerBound)
                }
                return Self(name: isNear ? "camera.zNear" : "camera.zFar") { node in
                    guard case let .camera(camera) = node.content else {
                        return []
                    }
                    let range: ClosedRange<Float>? = switch camera.projection {
                    case let projection as PerspectiveProjection:
                        switch projection.depthMode {
                        case let .standard(zClip), let .reversed(zClip): zClip
                        case let .reversedInfinite(zNear): isNear ? zNear...zNear : nil
                        }
                    case let projection as OrthographicProjection:
                        switch projection.depthMode {
                        case let .standard(zClip), let .reversed(zClip): zClip
                        }
                    default: nil
                    }
                    return range.map { [isNear ? $0.lowerBound : $0.upperBound] } ?? []
                } set: { node, value in
                    guard case var .camera(camera) = node.content, let value = value.first else {
                        return
                    }
                    switch camera.projection {
                    case var projection as PerspectiveProjection:
                        switch projection.depthMode {
                        case let .standard(zClip): projection.depthMode = .standard(zClip: clip(zClip, value))
                        case let .reversed(zClip): projection.depthMode = .reversed(zClip: clip(zClip, value))
                        case .reversedInfinite: if isNear { projection.depthMode = .reversedInfinite(zNear: value) }
                        }
                        camera.projection = projection
                    case var projection as OrthographicProjection:
                        switch projection.depthMode {
                        case let .standard(zClip): projection.depthMode = .standard(zClip: clip(zClip, value))
                        case let .reversed(zClip): projection.depthMode = .reversed(zClip: clip(zClip, value))
                        }
                        camera.projection = projection
                    default:
                        return
                    }
                    node.content = .camera(camera)
                }
            }

            /// The near clip distance of a camera node with a clip range.
            public static var cameraNear: Self { cameraClip(isNear: true) }
            /// The far clip distance of a camera node with a clip range.
            public static var cameraFar: Self { cameraClip(isNear: false) }
        }

        /// A callback at a time in a clip, like SceneKit's `SCNAnimationEvent`.
        ///
        /// ``AnimationPlayer`` calls the handler when playback passes ``time``. The handler's argument is true during
        /// the reversed half of an autoreversing cycle.
        public struct Event {
            /// The time in the clip, in seconds.
            public var time: Float
            /// The callback. Its argument is true when the clip plays backward.
            public var handler: (_ isPlayingBackward: Bool) -> Void

            /// Creates an event.
            ///
            /// - Parameters:
            ///   - time: The time in the clip, in seconds.
            ///   - handler: The callback. Its argument is true when the clip plays backward.
            public init(time: Float, handler: @escaping (_ isPlayingBackward: Bool) -> Void) {
                self.time = time
                self.handler = handler
            }
        }

        /// How a sampler finds values between keys.
        public enum Interpolation: Sendable {
            /// The value of the previous key, until the next key.
            case step
            /// A straight line between keys. Rotations use spherical interpolation.
            case linear
            /// A cubic spline, as in glTF. Each key has an in-tangent, a value and an out-tangent.
            case cubicSpline
        }

        /// Keyframes for one animated value.
        public struct Sampler: Sendable {
            /// The time of each key, in seconds, in increasing order.
            public var times: [Float]
            /// The values of all keys, in one flat array.
            ///
            /// Each key has ``componentCount`` values. For ``Interpolation/cubicSpline``, each key has three times as
            /// many: the in-tangent, the value and the out-tangent.
            public var values: [Float]
            /// How the sampler finds values between keys.
            public var interpolation: Interpolation

            /// Creates a sampler.
            ///
            /// - Parameters:
            ///   - times: The time of each key, in seconds, in increasing order.
            ///   - values: The values of all keys, in one flat array.
            ///   - interpolation: How the sampler finds values between keys.
            public init(times: [Float], values: [Float], interpolation: Interpolation) {
                self.times = times
                self.values = values
                self.interpolation = interpolation
            }

            /// The number of values for each key, for example 3 for a translation.
            public var componentCount: Int {
                guard !times.isEmpty else {
                    return 0
                }
                return values.count / times.count / (interpolation == .cubicSpline ? 3 : 1)
            }

            /// Returns the value at a time.
            ///
            /// Before the first key and after the last key, the value is the value of that key.
            ///
            /// - Parameters:
            ///   - time: The time, in seconds.
            ///   - isRotation: Whether the values are quaternions. If true, linear interpolation uses spherical
            ///     interpolation, and cubic splines normalize the result.
            public func sample(at time: Float, isRotation: Bool = false) -> [Float] {
                let count = componentCount
                guard let first = times.first, let last = times.last, count > 0 else {
                    return []
                }
                let stride = interpolation == .cubicSpline ? count * 3 : count
                let valueOffset = interpolation == .cubicSpline ? count : 0
                func value(_ key: Int) -> [Float] {
                    Array(values[(key * stride + valueOffset)..<(key * stride + valueOffset + count)])
                }
                if time <= first {
                    return value(0)
                }
                if time >= last {
                    return value(times.count - 1)
                }
                let upper = times.firstIndex { $0 > time } ?? times.count - 1
                let lower = upper - 1
                let span = times[upper] - times[lower]
                let t = span > 0 ? (time - times[lower]) / span : 0
                switch interpolation {
                case .step:
                    return value(lower)
                case .linear:
                    let start = value(lower)
                    let end = value(upper)
                    if isRotation, count == 4 {
                        let result = simd_slerp(simd_quatf(vector: SIMD4(start[0], start[1], start[2], start[3])), simd_quatf(vector: SIMD4(end[0], end[1], end[2], end[3])), t)
                        return [result.vector.x, result.vector.y, result.vector.z, result.vector.w]
                    }
                    return zip(start, end).map { $0 + ($1 - $0) * t }
                case .cubicSpline:
                    let t2 = t * t
                    let t3 = t2 * t
                    let startValue = value(lower)
                    let endValue = value(upper)
                    let outTangent = Array(values[(lower * stride + 2 * count)..<(lower * stride + 3 * count)])
                    let inTangent = Array(values[(upper * stride)..<(upper * stride + count)])
                    var result = (0..<count).map { index in
                        (2 * t3 - 3 * t2 + 1) * startValue[index]
                            + (t3 - 2 * t2 + t) * span * outTangent[index]
                            + (-2 * t3 + 3 * t2) * endValue[index]
                            + (t3 - t2) * span * inTangent[index]
                    }
                    if isRotation, count == 4 {
                        let length = sqrt(result.reduce(0) { $0 + $1 * $1 })
                        if length > 0 {
                            result = result.map { $0 / length }
                        }
                    }
                    return result
                }
            }
        }

        /// The keyframes for one value of one node.
        public struct Channel {
            /// The node that the channel animates.
            public var target: Node
            /// The value of the node that the channel animates.
            public var path: Path
            /// The keyframes.
            public var sampler: Sampler

            /// Creates a channel.
            public init(target: Node, path: Path, sampler: Sampler) {
                self.target = target
                self.path = path
                self.sampler = sampler
            }
        }

        /// The name of the clip, for example from the glTF file.
        public var name: String?
        /// The channels that the clip animates.
        public var channels: [Channel]
        /// The callbacks that ``AnimationPlayer`` calls during playback.
        public var events: [Event] = []

        /// Creates a clip.
        ///
        /// - Parameters:
        ///   - name: The name of the clip.
        ///   - channels: The channels that the clip animates.
        ///   - events: The callbacks that ``AnimationPlayer`` calls during playback.
        public init(name: String? = nil, channels: [Channel], events: [Event] = []) {
            self.name = name
            self.channels = channels
            self.events = events
        }

        /// The length of the clip in seconds: the time of the last key of any channel.
        public var duration: Float {
            channels.compactMap(\.sampler.times.last).max() ?? 0
        }

        /// Sets every channel's node to its value at a time.
        ///
        /// - Parameters:
        ///   - time: The time in the clip, in seconds.
        ///   - looping: Whether to wrap `time` into the duration of the clip.
        public func apply(at time: Float, looping: Bool = false) {
            var time = time
            if looping, duration > 0 {
                time = time.truncatingRemainder(dividingBy: duration)
                if time < 0 {
                    time += duration
                }
            }
            for channel in channels {
                channel.path.set(channel.sampler.sample(at: time, isRotation: channel.path == .rotation), on: channel.target)
            }
        }
    }

    /// A player for one clip, like SceneKit's `SCNAnimationPlayer`.
    ///
    /// The player keeps the playback time and applies the clip each time you call ``advance(by:)``.
    public final class AnimationPlayer {
        /// The clip that the player plays.
        public var clip: AnimationClip
        /// The playback time since the start, in seconds, across repeats.
        public var time: Float = 0
        /// The playback speed. 1 is normal speed.
        public var speed: Float = 1
        /// Whether the clip repeats forever.
        ///
        /// If false, the player plays ``repeatCount`` cycles and stops on the last frame.
        public var isLooping: Bool
        /// The number of cycles to play when ``isLooping`` is false.
        public var repeatCount = 1
        /// Whether each cycle plays forward, then backward.
        public var autoreverses = false
        /// The easing of each pass through the clip.
        public var timingMode: Action.TimingMode = .linear
        /// Whether the player advances. It becomes false when a clip that does not loop finishes.
        public var isPlaying = true

        /// Creates a player.
        ///
        /// - Parameters:
        ///   - clip: The clip to play.
        ///   - isLooping: Whether the clip repeats forever.
        public init(clip: AnimationClip, isLooping: Bool = true) {
            self.clip = clip
            self.isLooping = isLooping
        }

        private var cycleDuration: Float {
            clip.duration * (autoreverses ? 2 : 1)
        }

        // Clip time and direction at playback time `time`, before easing.
        private func clipTime(at time: Float) -> (time: Float, isBackward: Bool) {
            let duration = clip.duration
            guard duration > 0 else {
                return (0, false)
            }
            let total = isLooping ? Float.infinity : cycleDuration * Float(max(repeatCount, 1))
            if time >= total {
                return autoreverses ? (0, true) : (duration, false)
            }
            let cycle = max(time, 0).truncatingRemainder(dividingBy: cycleDuration)
            return cycle > duration ? (2 * duration - cycle, true) : (cycle, false)
        }

        /// Advances the playback time, calls the events that it passes, and applies the clip.
        ///
        /// - Parameter deltaTime: The time to advance, in seconds. ``speed`` multiplies it.
        public func advance(by deltaTime: Float) {
            guard isPlaying else {
                return
            }
            let previous = time
            time += deltaTime * speed
            if !isLooping, time >= cycleDuration * Float(max(repeatCount, 1)) {
                time = cycleDuration * Float(max(repeatCount, 1))
                isPlaying = false
            }
            fireEvents(from: previous, to: time)
            let (local, _) = clipTime(at: time)
            let duration = clip.duration
            clip.apply(at: duration > 0 ? timingMode.apply(local / duration) * duration : 0)
        }

        // Fires events whose clip time is passed between two playback times, a pass (forward or backward) at a time.
        private func fireEvents(from start: Float, to end: Float) {
            let duration = clip.duration
            guard !clip.events.isEmpty, duration > 0, end > start else {
                return
            }
            var passStart = start
            // Bounded, so a huge step does not loop for long.
            for _ in 0..<64 where passStart < end {
                let passIndex = (passStart / duration).rounded(.down)
                let passEnd = min((passIndex + 1) * duration, end)
                let isBackward = autoreverses && Int(passIndex) % 2 == 1
                let startOffset = passStart - passIndex * duration
                let endOffset = passEnd - passIndex * duration
                for event in clip.events {
                    let passed = if isBackward {
                        event.time < duration - startOffset && event.time >= duration - endOffset
                    } else {
                        // A forward pass that starts at its beginning includes events at 0.
                        (startOffset == 0 ? event.time >= 0 : event.time > startOffset) && event.time <= endOffset
                    }
                    if passed {
                        event.handler(isBackward)
                    }
                }
                passStart = passEnd
            }
        }
    }
}
