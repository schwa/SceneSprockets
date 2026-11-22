import JoltPhysics
import SceneSprockets
import simd

/// A joint between two nodes' bodies, or between a body and the world, like SceneKit's `SCNPhysicsBehavior` joints
/// (#432). Add one with ``SceneGraphPhysicsWorld/addJoint(_:between:and:breakingImpulse:)``.
public final class PhysicsJoint {
    /// How the joint constrains the bodies. Points and axes are in world space when the joint is added.
    public enum Kind {
        /// Holds the bodies in their current relative position and rotation, like a weld.
        case fixed
        /// Keeps one point of each body together and lets them rotate freely, like a ball-and-socket joint.
        case ball(anchor: SIMD3<Float>)
        /// Rotation about one axis through `anchor`, like a door hinge, optionally limited to an angle range in
        /// radians.
        case hinge(anchor: SIMD3<Float>, axis: SIMD3<Float>, limits: ClosedRange<Float>? = nil)
        /// Movement along one axis with no rotation, like a drawer, optionally limited to a distance range.
        case slider(axis: SIMD3<Float>, limits: ClosedRange<Float>? = nil)
        /// Keeps two points, one on each body, within a distance range: a rope or a spring. Nil keeps the current
        /// distance.
        case distance(anchorA: SIMD3<Float>, anchorB: SIMD3<Float>, range: ClosedRange<Float>? = nil)
        /// Twist about one axis and swing within a cone or pyramid, like a shoulder.
        case swingTwist(anchor: SIMD3<Float>, twistAxis: SIMD3<Float>, limits: SwingTwistLimits)
        /// Each of the six axes free, limited or locked.
        case sixDOF(anchor: SIMD3<Float>, axisX: SIMD3<Float> = [1, 0, 0], axisY: SIMD3<Float> = [0, 1, 0], limits: [SixDOFAxis: AxisLimit])
    }

    public let kind: Kind
    /// The first node, or nil when the joint holds `nodeB` to the world.
    public private(set) weak var nodeA: SceneGraph.Node?
    public private(set) weak var nodeB: SceneGraph.Node?
    /// The impulse, in newton seconds per step, above which the joint breaks. Nil never breaks.
    public var breakingImpulse: Float?
    /// True once the joint broke or was removed. A broken joint no longer holds anything.
    public internal(set) var isBroken = false
    /// The Jolt constraint, for motors, limits and anything else this type does not wrap. Nil once broken.
    public internal(set) var constraint: Constraint?

    let bodyA: BodyID?
    let bodyB: BodyID

    init(kind: Kind, nodeA: SceneGraph.Node?, nodeB: SceneGraph.Node, bodyA: BodyID?, bodyB: BodyID, breakingImpulse: Float?, constraint: Constraint) {
        self.kind = kind
        self.nodeA = nodeA
        self.nodeB = nodeB
        self.bodyA = bodyA
        self.bodyB = bodyB
        self.breakingImpulse = breakingImpulse
        self.constraint = constraint
    }

    /// The size of the impulse the joint applied in the last step to hold its position, in newton seconds.
    public var impulse: Float {
        switch constraint {
        case let constraint as FixedConstraint: simd_length(constraint.totalLambdaPosition)
        case let constraint as PointConstraint: simd_length(constraint.totalLambdaPosition)
        case let constraint as HingeConstraint: simd_length(constraint.totalLambdaPosition)
        case let constraint as SliderConstraint: simd_length(constraint.totalLambdaPosition)
        case let constraint as DistanceConstraint: abs(constraint.totalLambdaPosition)
        case let constraint as SwingTwistConstraint: simd_length(constraint.totalLambdaPosition)
        case let constraint as SixDOFConstraint: simd_length(constraint.totalLambdaPosition)
        default: 0
        }
    }

    func uses(_ body: BodyID) -> Bool {
        bodyA == body || bodyB == body
    }
}

public extension SceneGraphPhysicsWorld {
    /// Joins `nodeA`'s body to `nodeB`'s, or `nodeB`'s to the world when `nodeA` is nil. Returns nil if a node has no
    /// body yet (the method calls ``sync()`` first) or both are the same.
    ///
    /// - Parameters:
    ///   - kind: How the joint constrains the bodies; its points and axes are in world space now.
    ///   - nodeA: The first node, or nil for the world.
    ///   - nodeB: The second node.
    ///   - breakingImpulse: The impulse per step, in newton seconds, above which the joint breaks and
    ///     ``jointBreakHandler`` is called. Nil never breaks.
    @discardableResult
    func addJoint(_ kind: PhysicsJoint.Kind, between nodeA: SceneGraph.Node?, and nodeB: SceneGraph.Node, breakingImpulse: Float? = nil) -> PhysicsJoint? {
        sync()
        guard let bodyB = body(of: nodeB) else {
            return nil
        }
        let bodyA = nodeA.flatMap { body(of: $0) }
        guard nodeA == nil || (bodyA != nil && bodyA != bodyB) else {
            return nil
        }
        let constraint: Constraint = switch kind {
        case .fixed:
            world.addFixedConstraint(between: bodyA, and: bodyB)
        case let .ball(anchor):
            world.addPointConstraint(between: bodyA, and: bodyB, point: anchor)
        case let .hinge(anchor, axis, limits):
            world.addHingeConstraint(between: bodyA, and: bodyB, point: anchor, axis: axis, limits: limits)
        case let .slider(axis, limits):
            world.addSliderConstraint(between: bodyA, and: bodyB, axis: axis, limits: limits)
        case let .distance(anchorA, anchorB, range):
            world.addDistanceConstraint(between: bodyA, and: bodyB, point1: anchorA, point2: anchorB, distance: range)
        case let .swingTwist(anchor, twistAxis, limits):
            world.addSwingTwistConstraint(between: bodyA, and: bodyB, point: anchor, twistAxis: twistAxis, limits: limits)
        case let .sixDOF(anchor, axisX, axisY, limits):
            world.addSixDOFConstraint(between: bodyA, and: bodyB, point: anchor, axisX: axisX, axisY: axisY, limits: limits)
        }
        let joint = PhysicsJoint(kind: kind, nodeA: nodeA, nodeB: nodeB, bodyA: bodyA, bodyB: bodyB, breakingImpulse: breakingImpulse, constraint: constraint)
        joints.append(joint)
        // A sleeping body would not feel the joint until something woke it.
        world.activate(bodyB)
        if let bodyA {
            world.activate(bodyA)
        }
        return joint
    }

    /// Removes a joint. It counts as broken afterwards; ``jointBreakHandler`` is not called.
    func removeJoint(_ joint: PhysicsJoint) {
        detach(joint)
    }
}

extension SceneGraphPhysicsWorld {
    // After a step: breaks joints whose load is over their limit.
    func breakOverloadedJoints() {
        for joint in joints {
            guard let limit = joint.breakingImpulse, joint.impulse > limit else {
                continue
            }
            detach(joint)
            jointBreakHandler?(joint)
        }
    }

    // Before a body goes away: Jolt must not keep constraints to a removed body.
    func detachJoints(using body: BodyID) {
        for joint in joints where joint.uses(body) {
            detach(joint)
        }
    }

    func detach(_ joint: PhysicsJoint) {
        guard let constraint = joint.constraint else {
            return
        }
        world.removeConstraint(constraint)
        joint.constraint = nil
        joint.isBroken = true
        joints.removeAll { $0 === joint }
        for body in [joint.bodyA, joint.bodyB].compactMap(\.self) where world.isAdded(body) {
            world.activate(body)
        }
    }
}
