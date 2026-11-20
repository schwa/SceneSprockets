/// The values that a state machine transition condition can test.
public struct AnimationStateContext: Sendable {
    /// The parameters of the state machine, by name.
    public var parameters: [String: Float]
    /// How far through its clip the current state is, from 0 to 1. More than 1 after a clip that does not loop has
    /// finished.
    public var normalizedTime: Float
    /// The time since the current state started, in seconds.
    public var stateTime: Float
}

/// The state bookkeeping shared by the glTF and scene graph animation state machines (#589): the current state, its
/// time, and which clip each state plays on an ``AnimationPlayback``.
public struct AnimationStates: Sendable {
    /// What a state plays.
    public struct State: Sendable {
        public var clip: Int
        public var speed: Float
        public var loops: Bool

        public init(clip: Int, speed: Float, loops: Bool) {
            self.clip = clip
            self.speed = speed
            self.loops = loops
        }
    }

    public let states: [String: State]
    public private(set) var currentState: String
    public private(set) var stateTime: Float = 0

    /// Starts in `initial`, which must be one of `states`, and plays it on `playback`.
    public init(states: [String: State], initial: String, playback: inout AnimationPlayback) {
        precondition(states[initial] != nil, "The initial state must be one of the states")
        self.states = states
        currentState = initial
        enter(initial, fadeDuration: 0, playback: &playback)
    }

    public func context(parameters: [String: Float], playback: AnimationPlayback) -> AnimationStateContext {
        let state = states[currentState]
        let duration = state.map { playback.durations[$0.clip] } ?? 0
        let time = state.flatMap { state in playback.tracks.first { $0.clip == state.clip } }?.time ?? 0
        let normalized: Float
        if let state, !state.loops, duration > 0 {
            // A finished non-looping clip holds its last frame; report it past the end so "on finish" fires.
            normalized = stateTime * abs(state.speed) >= duration ? max(time / duration, 1) + 1e-6 : time / duration
        } else {
            normalized = duration > 0 ? time / duration : 0
        }
        return AnimationStateContext(parameters: parameters, normalizedTime: normalized, stateTime: stateTime)
    }

    /// Whether a transition from `from` (nil: any state) to `to` may be taken now, before testing its condition.
    public func canTake(from: String?, to: String) -> Bool {
        (from == nil || from == currentState) && to != currentState && states[to] != nil
    }

    /// Enters `transitionTo` when not nil, then advances the state time. The caller advances the playback.
    public mutating func advance(by seconds: Float, transitionTo: (name: String, fadeDuration: Float)?, playback: inout AnimationPlayback) {
        if let transitionTo {
            enter(transitionTo.name, fadeDuration: transitionTo.fadeDuration, playback: &playback)
        }
        stateTime += seconds
    }

    private mutating func enter(_ name: String, fadeDuration: Float, playback: inout AnimationPlayback) {
        guard let state = states[name] else {
            return
        }
        currentState = name
        stateTime = 0
        playback.play(state.clip, fadeDuration: fadeDuration, speed: state.speed, loops: state.loops, restarts: true)
    }
}
