import MetalSprocketsAnimation
import MetalSprocketsPBR

/// One clip at one time, with a weight, for ``GLTFAsset/pose(layers:)``.
public struct GLTFAnimationLayer: Sendable, Equatable {
    /// ``AnimationBlendMode/additive`` adds the clip's offsets from rest, scaled by the weight, on top of the override
    /// layers (e.g. a breathing or aiming clip over a walk).
    public typealias Mode = AnimationBlendMode

    public var animation: Int
    public var time: Float
    public var weight: Float
    public var mode: Mode

    public init(animation: Int, time: Float, weight: Float = 1, mode: Mode = .override) {
        self.animation = animation
        self.time = time
        self.weight = weight
        self.mode = mode
    }
}

extension AnimationPlayback.Track {
    /// The index of the clip in ``GLTFAsset/animations``.
    public var animation: Int {
        get { clip }
        set { clip = newValue }
    }
}

/// Plays an asset's animation clips: cross-fades between clips, per-clip speed and looping, and a one-parameter
/// blend between clips (e.g. idle, walk, run by speed) with their cycles kept in phase.
///
/// A value type: call ``advance(by:)`` each frame, then ``pose(in:)``.
public struct GLTFAnimationController: Sendable {
    public typealias Track = AnimationPlayback.Track

    var playback: AnimationPlayback

    /// Each clip's duration in seconds, by animation index.
    public var durations: [Float] { playback.durations }
    public var tracks: [Track] { playback.tracks }
    /// With a phase-synced blend, the shared position in the cycle, 0 ..< 1.
    public var syncedPhase: Float? { playback.syncedPhase }
    /// Clips added on top of the playing ones (``GLTFAnimationLayer/Mode/additive``); they loop at their own speed.
    public var additiveTracks: [Track] { playback.additiveTracks }
    /// The node whose horizontal movement becomes ``rootMotion`` instead of moving it in the pose (usually the
    /// character's root or hips); nil leaves the animation's movement in the pose.
    public var rootMotionNode: Int?
    /// How far the root node moved (x, z) during the last ``advance(by:in:)``, in its parent's space.
    public private(set) var rootMotion: SIMD3<Float> = .zero

    public init(durations: [Float]) {
        playback = AnimationPlayback(durations: durations)
    }

    public init(asset: GLTFAsset) {
        self.init(durations: asset.animations.map(\.duration))
    }

    /// Switches to `animation`, fading it in and every other track out over `fadeDuration` seconds (0 cuts).
    /// A clip already playing continues from its time unless `restarts`.
    public mutating func play(_ animation: Int, fadeDuration: Float = 0.25, speed: Float = 1, loops: Bool = true, restarts: Bool = false) {
        playback.play(animation, fadeDuration: fadeDuration, speed: speed, loops: loops, restarts: restarts)
    }

    /// Plays `animations` together, weighted by `parameter` along them (0 is the first, 1 the last; see
    /// ``blendWeights(parameter:count:)``). With `syncsPhase`, every clip is at the same fraction of its cycle and the
    /// cycle lasts the weighted mix of their durations, so walk and run cycles keep their feet in step.
    public mutating func blend(_ animations: [Int], parameter: Float, speed: Float = 1, syncsPhase: Bool = true) {
        playback.blend(animations, parameter: parameter, speed: speed, syncsPhase: syncsPhase)
    }

    /// Weights for `count` clips evenly spaced along `parameter` (clamped to 0 ... 1): the two clips either side of
    /// it share the weight linearly. They always sum to 1.
    public static func blendWeights(parameter: Float, count: Int) -> [Float] {
        AnimationPlayback.blendWeights(parameter: parameter, count: count)
    }

    /// Adds `animation` on top of the playing clips at `weight` (0 removes it), e.g. breathing over a walk.
    public mutating func setAdditive(_ animation: Int, weight: Float, speed: Float = 1) {
        playback.setAdditive(animation, weight: weight, speed: speed)
    }

    /// Advances like ``advance(by:)``, and with ``rootMotionNode`` set, measures how far the clips moved the root node
    /// horizontally into ``rootMotion`` (counting each loop's wrap from its end back to its start).
    public mutating func advance(by seconds: Float, in asset: GLTFAsset) {
        let before = playback.tracks
        advance(by: seconds)
        guard let node = rootMotionNode else {
            rootMotion = .zero
            return
        }
        rootMotion = playback.rootMotion(since: before) { animation, time in
            asset.rootTranslation(layers: [GLTFAnimationLayer(animation: animation, time: time)], node: node)
        }
    }

    /// Moves clip times and fades forward by `seconds`; fully faded-out tracks are dropped.
    public mutating func advance(by seconds: Float) {
        playback.advance(by: seconds)
    }

    /// The tracks as layers, override weights normalized to sum to 1, then the additive tracks.
    public var layers: [GLTFAnimationLayer] {
        playback.layers.map { GLTFAnimationLayer(animation: $0.clip, time: $0.time, weight: $0.weight, mode: $0.mode) }
    }

    /// The pose; with ``rootMotionNode`` set, without the root's horizontal movement.
    public func pose(in asset: GLTFAsset) -> PBRPose {
        asset.pose(layers: layers, rootMotionNode: rootMotionNode)
    }
}
