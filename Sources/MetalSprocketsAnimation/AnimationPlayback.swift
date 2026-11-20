import simd

/// Which clips play, at what time and weight: cross-fades, per-clip speed and looping, phase-synced blends and
/// additive clips. Shared by the glTF and scene graph animation controllers (#589).
public struct AnimationPlayback: Sendable, Equatable {
    /// A clip that plays, with its time and weight.
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
        // The weight a fade is heading to, and how fast (weight per second).
        var targetWeight: Float
        var fadeRate: Float = 0
    }

    /// One clip at one time, with a weight.
    public struct Layer: Sendable, Equatable {
        public var clip: Int
        public var time: Float
        public var weight: Float
        public var mode: AnimationBlendMode
    }

    /// The duration of each clip, in seconds, by clip index.
    public let durations: [Float]
    /// The override tracks that play now, including tracks that fade out.
    public private(set) var tracks: [Track] = []
    /// The shared fraction of the cycle of a phase-synced blend, or `nil` when no synced blend plays.
    public private(set) var syncedPhase: Float?
    /// The additive tracks that play on top of the override tracks.
    public private(set) var additiveTracks: [Track] = []

    public init(durations: [Float]) {
        self.durations = durations
    }

    /// Fades `clip` in and every other track out over `fadeDuration` (0 cuts). A clip already playing continues from
    /// its time unless `restarts`.
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

    /// Weights for `count` clips evenly spaced along `parameter` (clamped to 0...1): the two clips either side of it
    /// share the weight linearly. They sum to 1.
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

    /// Moves clip times and fades forward; fully faded-out tracks are dropped.
    public mutating func advance(by seconds: Float) {
        for index in additiveTracks.indices {
            additiveTracks[index].time = Self.wrapped(additiveTracks[index].time + seconds * additiveTracks[index].speed, duration: durations[additiveTracks[index].clip])
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
                tracks[index].time = tracks[index].loops ? Self.wrapped(time, duration: duration) : min(max(time, 0), duration)
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

    /// How far the root moved horizontally (x, z) between `before` and the current tracks. `translation` gives the
    /// root's translation in one clip at one time. Each loop's wrap from end to start counts as moving on.
    public func rootMotion(since before: [Track], translation: (_ clip: Int, _ time: Float) -> SIMD3<Float>) -> SIMD3<Float> {
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
        var result = totalWeight > 0 ? motion / totalWeight : .zero
        result.y = 0
        return result
    }

    /// Override weights normalized to sum to 1, then the additive tracks.
    public var layers: [Layer] {
        let additive = additiveTracks.map { Layer(clip: $0.clip, time: $0.time, weight: $0.weight, mode: .additive) }
        let total = tracks.reduce(0) { $0 + $1.weight }
        guard total > 0 else {
            // Mid cut with nothing faded in yet: show the newest clip.
            return (tracks.last.map { [Layer(clip: $0.clip, time: $0.time, weight: 1, mode: .override)] } ?? []) + additive
        }
        return tracks.filter { $0.weight > 0 }.map { Layer(clip: $0.clip, time: $0.time, weight: $0.weight / total, mode: .override) } + additive
    }

    private static func wrapped(_ time: Float, duration: Float) -> Float {
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
