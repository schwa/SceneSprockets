import simd

extension SceneGraph {
    // Format-neutral keyframe animation. Channels target node translation, rotation, scale or morph weights.
    public struct AnimationClip {
        public enum Path: Sendable {
            case translation
            case rotation
            case scale
            case weights
        }

        public enum Interpolation: Sendable {
            case step
            case linear
            // Values are [in-tangent, value, out-tangent] per key, as in glTF.
            case cubicSpline
        }

        public struct Sampler: Sendable {
            public var times: [Float]
            // Flat: componentCount values per key (three times that for cubicSpline).
            public var values: [Float]
            public var interpolation: Interpolation

            public init(times: [Float], values: [Float], interpolation: Interpolation) {
                self.times = times
                self.values = values
                self.interpolation = interpolation
            }

            public var componentCount: Int {
                guard !times.isEmpty else {
                    return 0
                }
                return values.count / times.count / (interpolation == .cubicSpline ? 3 : 1)
            }

            // Clamps outside the key range.
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

        public struct Channel {
            public var target: Node
            public var path: Path
            public var sampler: Sampler

            public init(target: Node, path: Path, sampler: Sampler) {
                self.target = target
                self.path = path
                self.sampler = sampler
            }
        }

        public var name: String?
        public var channels: [Channel]

        public init(name: String? = nil, channels: [Channel]) {
            self.name = name
            self.channels = channels
        }

        public var duration: Float {
            channels.compactMap(\.sampler.times.last).max() ?? 0
        }

        // Sets every target to its value at `time`.
        public func apply(at time: Float, looping: Bool = false) {
            var time = time
            if looping, duration > 0 {
                time = time.truncatingRemainder(dividingBy: duration)
                if time < 0 {
                    time += duration
                }
            }
            for channel in channels {
                let value = channel.sampler.sample(at: time, isRotation: channel.path == .rotation)
                let node = channel.target
                switch channel.path {
                case .translation where value.count == 3:
                    node.trs.translation = SIMD3(value[0], value[1], value[2])
                case .rotation where value.count == 4:
                    node.trs.rotation = simd_quatf(vector: SIMD4(value[0], value[1], value[2], value[3]))
                case .scale where value.count == 3:
                    node.trs.scale = SIMD3(value[0], value[1], value[2])
                case .weights:
                    node.morphWeights = value
                default:
                    break
                }
            }
        }
    }

    // Plays one clip: holds the time and applies the clip as time advances.
    public final class AnimationPlayer {
        public var clip: AnimationClip
        public var time: Float = 0
        public var speed: Float = 1
        public var isLooping: Bool
        public var isPlaying = true

        public init(clip: AnimationClip, isLooping: Bool = true) {
            self.clip = clip
            self.isLooping = isLooping
        }

        public func advance(by deltaTime: Float) {
            guard isPlaying else {
                return
            }
            time += deltaTime * speed
            if !isLooping, time >= clip.duration {
                time = clip.duration
                isPlaying = false
            }
            clip.apply(at: time, looping: isLooping)
        }
    }
}
