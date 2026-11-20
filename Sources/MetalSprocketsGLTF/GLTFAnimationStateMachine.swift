import MetalSprocketsAnimation
import MetalSprocketsPBR

/// Chooses which clip plays from named states and transitions, driving a ``GLTFAnimationController``: e.g. idle,
/// walk and run, switched by a `speed` parameter, cross-fading on each change.
///
/// A value type: set ``parameters``, call ``advance(by:in:)`` each frame, then ``pose(in:)``.
public struct GLTFAnimationStateMachine: Sendable {
    public struct State: Sendable {
        public var name: String
        public var animation: Int
        public var speed: Float
        public var loops: Bool

        public init(_ name: String, animation: Int, speed: Float = 1, loops: Bool = true) {
            self.name = name
            self.animation = animation
            self.speed = speed
            self.loops = loops
        }
    }

    /// What a transition's condition can look at.
    public typealias Context = AnimationStateContext

    public struct Transition: Sendable {
        /// The state it leaves; nil leaves any state.
        public var from: String?
        public var to: String
        public var fadeDuration: Float
        public var condition: @Sendable (Context) -> Bool

        @preconcurrency
        public init(from: String?, to: String, fadeDuration: Float = 0.25, when condition: @escaping @Sendable (Context) -> Bool) {
            self.from = from
            self.to = to
            self.fadeDuration = fadeDuration
            self.condition = condition
        }
    }

    public let states: [String: State]
    public let transitions: [Transition]
    public var parameters: [String: Float] = [:]
    private var core: AnimationStates
    public var currentState: String { core.currentState }
    public var stateTime: Float { core.stateTime }
    /// The controller playing the states' clips; set its ``GLTFAnimationController/rootMotionNode`` or additive
    /// clips here.
    public var controller: GLTFAnimationController

    /// Starts in `initial`. Transitions are checked in order; the first whose condition holds is taken.
    public init(controller: GLTFAnimationController, states: [State], transitions: [Transition], initial: String) {
        self.states = Dictionary(states.map { ($0.name, $0) }) { first, _ in first }
        self.transitions = transitions
        var controller = controller
        core = AnimationStates(states: self.states.mapValues { .init(clip: $0.animation, speed: $0.speed, loops: $0.loops) }, initial: initial, playback: &controller.playback)
        self.controller = controller
    }

    public var context: Context {
        core.context(parameters: parameters, playback: controller.playback)
    }

    /// Takes the first transition whose condition holds (at most one per call), then advances the controller.
    public mutating func advance(by seconds: Float, in asset: GLTFAsset) {
        let context = context
        let transition = transitions.first { core.canTake(from: $0.from, to: $0.to) && $0.condition(context) }
        core.advance(by: seconds, transitionTo: transition.map { ($0.to, $0.fadeDuration) }, playback: &controller.playback)
        controller.advance(by: seconds, in: asset)
    }

    public func pose(in asset: GLTFAsset) -> PBRPose {
        controller.pose(in: asset)
    }
}
