import GeometryLite3D
import simd

extension SceneGraph {
    /// Changes a node's transform from other nodes each frame, like SceneKit's SCNConstraint subclasses. Constraints
    /// set the node's local TRS, keeping its world scale; run them with `SceneGraph.applyConstraints(pointOfView:)`
    /// after animation and actions.
    public struct Constraint {
        /// What the constraint does.
        public var kind: Kind
        /// 0 leaves the node as it was, 1 applies the constraint fully; in between blends, like SCNConstraint.
        public var influenceFactor: Float = 1
        /// Whether the constraint applies. A disabled constraint leaves the node as it is.
        public var isEnabled = true

        /// Creates a constraint.
        ///
        /// - Parameters:
        ///   - kind: What the constraint does.
        ///   - influenceFactor: How much the constraint applies, from 0 to 1.
        ///   - isEnabled: Whether the constraint applies.
        public init(_ kind: Kind, influenceFactor: Float = 1, isEnabled: Bool = true) {
            self.kind = kind
            self.influenceFactor = influenceFactor
            self.isEnabled = isEnabled
        }

        /// A constraint that turns the node to look at a target. See ``Kind/lookAt(target:worldUp:localFront:)``.
        public static func lookAt(target: Node, worldUp: SIMD3<Float> = [0, 1, 0], localFront: SIMD3<Float> = [0, 0, -1]) -> Self {
            Self(.lookAt(target: target, worldUp: worldUp, localFront: localFront))
        }

        /// A constraint that turns the node to face the camera. See ``Kind/billboard(freeAxes:)``.
        public static func billboard(freeAxes: BillboardAxes = .all) -> Self {
            Self(.billboard(freeAxes: freeAxes))
        }

        /// A constraint that copies a target's position, orientation and scale. See
        /// ``Kind/replicator(target:position:orientation:scale:positionOffset:orientationOffset:scaleOffset:)``.
        public static func replicator(target: Node, position: Bool = true, orientation: Bool = true, scale: Bool = true, positionOffset: SIMD3<Float> = .zero, orientationOffset: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scaleOffset: SIMD3<Float> = .one) -> Self {
            Self(.replicator(target: target, position: position, orientation: orientation, scale: scale, positionOffset: positionOffset, orientationOffset: orientationOffset, scaleOffset: scaleOffset))
        }

        /// A constraint that moves the node so that nothing blocks its view of a target. See
        /// ``Kind/avoidOccluder(target:categoryBitMask:bias:)``.
        public static func avoidOccluder(target: Node, categoryBitMask: UInt = .max, bias: Float = 0.01) -> Self {
            Self(.avoidOccluder(target: target, categoryBitMask: categoryBitMask, bias: bias))
        }

        /// A constraint that computes the node's world transform with a closure. See ``Kind/transform(_:)``.
        public static func transform(_ body: @escaping (Node, Transform3D) -> Transform3D) -> Self {
            Self(.transform(body))
        }

        /// A constraint that keeps the node within a distance range from a target. See
        /// ``Kind/distance(target:minimum:maximum:)``.
        public static func distance(target: Node, minimum: Float = 0, maximum: Float = .infinity) -> Self {
            Self(.distance(target: target, minimum: minimum, maximum: maximum))
        }

        /// A constraint that turns the node's ancestors so that the node reaches a target. See
        /// ``Kind/inverseKinematics(chainRoot:target:iterations:maximumAngle:)``.
        public static func inverseKinematics(chainRoot: Node, target: Node, iterations: Int = 10, maximumAngle: Float = .pi) -> Self {
            Self(.inverseKinematics(chainRoot: chainRoot, target: target, iterations: iterations, maximumAngle: maximumAngle))
        }

        /// A constraint that smooths the node's movement. See
        /// ``Kind/acceleration(maximumLinearAcceleration:maximumLinearVelocity:damping:)``.
        public static func acceleration(maximumLinearAcceleration: Float = 3, maximumLinearVelocity: Float = 10, damping: Float = 0.1) -> Self {
            Self(.acceleration(maximumLinearAcceleration: maximumLinearAcceleration, maximumLinearVelocity: maximumLinearVelocity, damping: damping))
        }
    }
}

extension SceneGraph.Constraint {
    /// What a constraint does.
    public enum Kind {
        /// Turns the node so that `localFront` points at `target`, and keeps `worldUp` up when possible.
        case lookAt(target: SceneGraph.Node, worldUp: SIMD3<Float> = [0, 1, 0], localFront: SIMD3<Float> = [0, 0, -1])
        /// Turns the node to face the point of view, with its +Z toward the camera, like the camera's orientation.
        ///
        /// With one axis, for example `.y` for a tree sprite, the node turns only about that world axis. With two axes,
        /// it turns toward the camera without rolling.
        case billboard(freeAxes: SceneGraph.BillboardAxes = .all)
        /// Copies the target's world position, orientation and scale, each optional, with offsets in the target's
        /// space, like `SCNReplicatorConstraint`.
        case replicator(target: SceneGraph.Node, position: Bool = true, orientation: Bool = true, scale: Bool = true, positionOffset: SIMD3<Float> = .zero, orientationOffset: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scaleOffset: SIMD3<Float> = .one)
        /// Moves the node toward the target until nothing in `categoryBitMask` blocks the line between them, like
        /// `SCNAvoidOccluderConstraint`. Hits on the subtrees of the node and the target do not count.
        case avoidOccluder(target: SceneGraph.Node, categoryBitMask: UInt = .max, bias: Float = 0.01)
        /// Computes the node's new world transform from its current one, like `SCNTransformConstraint`.
        case transform((SceneGraph.Node, Transform3D) -> Transform3D)
        /// Keeps the node between `minimum` and `maximum` from the target. It moves the node along the line between
        /// them.
        case distance(target: SceneGraph.Node, minimum: Float = 0, maximum: Float = .infinity)
        /// Turns the node's ancestors, from its parent up to `chainRoot`, so that the node reaches toward the target,
        /// like `SCNIKConstraint`.
        ///
        /// The solver uses cyclic coordinate descent. The node itself does not turn. `maximumAngle`, in radians, limits
        /// the turn of each joint in one step.
        case inverseKinematics(chainRoot: SceneGraph.Node, target: SceneGraph.Node, iterations: Int = 10, maximumAngle: Float = .pi)
        /// Smooths the node's world position, like `SCNAccelerationConstraint`.
        ///
        /// The node follows where earlier constraints and animation put it. Its speed changes by at most
        /// `maximumLinearAcceleration`, in meters per second squared, and stays at most `maximumLinearVelocity`, in meters
        /// per second. `damping`, from 0 to 1, slows it each second.
        case acceleration(maximumLinearAcceleration: Float = 3, maximumLinearVelocity: Float = 10, damping: Float = 0.1)
    }
}

extension SceneGraph {
    /// The world axes that a billboard constraint can turn about.
    public struct BillboardAxes: OptionSet, Sendable {
        /// The bits of the axes.
        public let rawValue: Int

        /// Creates a set of axes from bits.
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// The x axis.
        public static let x = Self(rawValue: 1 << 0)
        /// The y axis.
        public static let y = Self(rawValue: 1 << 1)
        /// The z axis.
        public static let z = Self(rawValue: 1 << 2)
        /// All three axes.
        public static let all: Self = [.x, .y, .z]
    }

    /// Applies every node's constraints, parents before children. `pointOfView` is the camera's world transform,
    /// used by billboards. `deltaTime` (seconds since the last call) drives acceleration constraints.
    public func applyConstraints(pointOfView: simd_float4x4, deltaTime: Float = 0) {
        var constrained: [Node] = []
        visitActive { node, _ in
            if !node.constraints.isEmpty {
                constrained.append(node)
            }
        }
        for node in constrained {
            for (index, constraint) in node.constraints.enumerated() where constraint.isEnabled {
                node.apply(constraint, index: index, pointOfView: pointOfView, deltaTime: deltaTime, sceneGraph: self)
            }
        }
    }
}

struct AccelerationState {
    var position: SIMD3<Float>
    var velocity: SIMD3<Float>
}

extension SceneGraph.Node {
    func apply(_ constraint: SceneGraph.Constraint, index: Int, pointOfView: simd_float4x4, deltaTime: Float, sceneGraph: SceneGraph? = nil) {
        let influence = min(max(constraint.influenceFactor, 0), 1)
        guard influence > 0 else {
            return
        }
        if case let .inverseKinematics(chainRoot, target, iterations, maximumAngle) = constraint.kind {
            // Influence scales how far each joint may turn per step.
            solveInverseKinematics(chainRoot: chainRoot, target: target.worldTransform.columns.3.xyz, iterations: iterations, maximumAngle: maximumAngle * influence)
            return
        }
        let parentWorld = parent?.worldTransform ?? matrix_identity_float4x4
        let world = Transform3D(nearestTo: parentWorld * transform.matrix)
        var desired = world
        switch constraint.kind {
        case let .lookAt(target, worldUp, localFront):
            let targetPosition = target.worldTransform.columns.3.xyz
            guard let rotation = lookRotation(from: world.translation, to: targetPosition, worldUp: worldUp, localFront: localFront) else {
                return
            }
            desired.rotation = Rotation3D(rotation)
        case let .billboard(freeAxes):
            let toCamera = pointOfView.columns.3.xyz - world.translation
            let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
            let free = [SceneGraph.BillboardAxes.x, .y, .z].indices.filter { freeAxes.contains([SceneGraph.BillboardAxes.x, .y, .z][$0]) }
            switch free.count {
            case 3:
                desired.rotation = Transform3D(nearestTo: pointOfView).rotation
            case 2:
                // Face the camera position, keeping an up vector so there is no roll.
                let up = free.contains(1) ? axes[1] : axes[free[0]]
                guard let rotation = lookRotation(from: world.translation, to: pointOfView.columns.3.xyz, worldUp: up, localFront: [0, 0, 1]) else {
                    return
                }
                desired.rotation = Rotation3D(rotation)
            case 1:
                // Turn about the free axis so the node's reference direction (+Z, or +Y for Z) faces the camera's
                // position projected onto the plane across that axis.
                let axis = axes[free[0]]
                let reference: SIMD3<Float> = free[0] == 2 ? [0, 1, 0] : [0, 0, 1]
                let projected = toCamera - axis * simd_dot(toCamera, axis)
                guard simd_length(projected) > 1e-6 else {
                    return
                }
                let direction = simd_normalize(projected)
                desired.rotation = Rotation3D(simd_quatf(angle: atan2(simd_dot(simd_cross(reference, direction), axis), simd_dot(reference, direction)), axis: axis))
            default:
                return
            }
        case let .replicator(target, position, orientation, scale, positionOffset, orientationOffset, scaleOffset):
            let targetWorld = Transform3D(nearestTo: target.worldTransform)
            if position {
                desired.translation = (target.worldTransform * SIMD4(positionOffset, 1)).xyz
            }
            if orientation {
                desired.rotation = Rotation3D(simd_normalize(targetWorld.rotation.quaternion * orientationOffset))
            }
            if scale {
                desired.scale = targetWorld.scale * scaleOffset
            }
        case let .avoidOccluder(target, categoryBitMask, bias):
            guard let sceneGraph else {
                return
            }
            let targetPosition = target.worldTransform.columns.3.xyz
            // swiftlint:disable:next prefer_self_in_static_references - Self is not Node in this closure
            let ignored = { (node: SceneGraph.Node) in node === self || self.isAncestor(of: node) || node === target || target.isAncestor(of: node) }
            guard let hit = sceneGraph.hitTest(segmentFrom: targetPosition, to: world.translation, options: .init(categoryBitMask: categoryBitMask)).first(where: { !ignored($0.node) }) else {
                return
            }
            let direction = simd_normalize(world.translation - targetPosition)
            desired.translation = targetPosition + direction * max(hit.distance - bias, 0)
        case let .transform(body):
            desired = body(self, world)
        case let .distance(target, minimum, maximum):
            let targetPosition = target.worldTransform.columns.3.xyz
            let offset = world.translation - targetPosition
            let length = simd_length(offset)
            guard length > 1e-6 else {
                return
            }
            let clamped = min(max(length, minimum), maximum)
            guard clamped != length else {
                return
            }
            desired.translation = targetPosition + offset / length * clamped
        case .inverseKinematics:
            return
        case let .acceleration(maximumLinearAcceleration, maximumLinearVelocity, damping):
            desired.translation = accelerate(towards: world.translation, index: index, deltaTime: deltaTime, maximumLinearAcceleration: maximumLinearAcceleration, maximumLinearVelocity: maximumLinearVelocity, damping: damping)
        }
        if influence < 1 {
            desired.translation = simd_mix(world.translation, desired.translation, SIMD3(repeating: influence))
            desired.rotation = Rotation3D(simd_slerp(world.rotation.quaternion, desired.rotation.quaternion, influence))
            desired.scale = simd_mix(world.scale, desired.scale, SIMD3(repeating: influence))
        }
        transform = Transform3D(nearestTo: parentWorld.inverse * desired.matrix)
    }

    // Moves the node's smoothed position towards `goal`, keeping velocity per constraint between frames.
    private func accelerate(towards goal: SIMD3<Float>, index: Int, deltaTime: Float, maximumLinearAcceleration: Float, maximumLinearVelocity: Float, damping: Float) -> SIMD3<Float> {
        guard var state = accelerationStates[index], deltaTime > 0 else {
            accelerationStates[index] = AccelerationState(position: goal, velocity: .zero)
            return goal
        }
        let wanted = (goal - state.position) / deltaTime
        var change = wanted - state.velocity
        let maximumChange = maximumLinearAcceleration * deltaTime
        if simd_length(change) > maximumChange {
            change = simd_normalize(change) * maximumChange
        }
        state.velocity += change
        state.velocity *= max(1 - damping * deltaTime, 0)
        if simd_length(state.velocity) > maximumLinearVelocity {
            state.velocity = simd_normalize(state.velocity) * maximumLinearVelocity
        }
        state.position += state.velocity * deltaTime
        accelerationStates[index] = state
        return state.position
    }

    // Cyclic coordinate descent: each joint, nearest first, turns so the line from it to this node points at the
    // target. Does nothing when `chainRoot` is not an ancestor.
    private func solveInverseKinematics(chainRoot: SceneGraph.Node, target: SIMD3<Float>, iterations: Int, maximumAngle: Float) {
        var joints: [SceneGraph.Node] = []
        var current = parent
        while let joint = current {
            joints.append(joint)
            if joint === chainRoot {
                break
            }
            current = joint.parent
        }
        guard joints.last === chainRoot else {
            return
        }
        for _ in 0..<max(iterations, 1) {
            for joint in joints {
                let jointWorld = joint.worldTransform
                let jointPosition = jointWorld.columns.3.xyz
                let toEffector = worldTransform.columns.3.xyz - jointPosition
                let toTarget = target - jointPosition
                guard simd_length(toEffector) > 1e-6, simd_length(toTarget) > 1e-6 else {
                    continue
                }
                var turn = simd_quatf(from: simd_normalize(toEffector), to: simd_normalize(toTarget))
                if turn.angle > maximumAngle {
                    turn = simd_quatf(angle: maximumAngle, axis: turn.axis)
                }
                // Apply the world-space turn in the joint's parent space.
                let parentRotation = Transform3D(nearestTo: joint.parent?.worldTransform ?? matrix_identity_float4x4).rotation.quaternion
                let localTurn = parentRotation.inverse * turn * parentRotation
                joint.transform.rotation = Rotation3D(simd_normalize(localTurn * joint.transform.rotation.quaternion))
            }
            if simd_distance(worldTransform.columns.3.xyz, target) < 1e-4 {
                return
            }
        }
    }

    private func lookRotation(from position: SIMD3<Float>, to target: SIMD3<Float>, worldUp: SIMD3<Float>, localFront: SIMD3<Float>) -> simd_quatf? {
        guard simd_length(target - position) > 1e-6 else {
            return nil
        }
        return .lookRotation(from: position, to: target, up: worldUp, localFront: localFront)
    }
}
