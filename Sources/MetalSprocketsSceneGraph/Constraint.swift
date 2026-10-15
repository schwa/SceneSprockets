import simd

extension SceneGraph {
    // Changes a node's transform from other nodes each frame, like SceneKit's SCNConstraint subclasses. Constraints
    // set the node's local TRS, keeping its world scale; run them with `SceneGraph.applyConstraints(pointOfView:)`
    // after animation and actions.
    public enum Constraint {
        // Turns the node so `localFront` points at `target`, keeping `worldUp` up when possible.
        case lookAt(target: Node, worldUp: SIMD3<Float> = [0, 1, 0], localFront: SIMD3<Float> = [0, 0, -1])
        // Turns the node to face the point of view (its +Z towards the camera, matching the camera's orientation).
        // With one axis (for example `.y`, like a tree sprite) the node only turns about that world axis; with two
        // it turns towards the camera without rolling.
        case billboard(freeAxes: BillboardAxes = .all)
        // Copies `target`'s world position, orientation and scale (each optional), with offsets in the target's
        // space, like SCNReplicatorConstraint.
        case replicator(target: Node, position: Bool = true, orientation: Bool = true, scale: Bool = true, positionOffset: SIMD3<Float> = .zero, orientationOffset: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scaleOffset: SIMD3<Float> = .one)
        // Moves the node towards `target` until nothing (in `categoryBitMask`) blocks the line between them, like
        // SCNAvoidOccluderConstraint. Hits on the node's and the target's subtrees are ignored.
        case avoidOccluder(target: Node, categoryBitMask: UInt = .max, bias: Float = 0.01)
        // Returns the node's new world TRS from its current one, like SCNTransformConstraint.
        case transform((Node, TRS) -> TRS)
        // Keeps the node between `minimum` and `maximum` from `target`, moving along the line between them.
        case distance(target: Node, minimum: Float = 0, maximum: Float = .infinity)
        // Turns the node's ancestors, from its parent up to `chainRoot`, so the node reaches towards `target`, like
        // SCNIKConstraint (cyclic coordinate descent). The node itself does not turn. `maximumAngle` (radians) limits
        // each joint's turn per step.
        case inverseKinematics(chainRoot: Node, target: Node, iterations: Int = 10, maximumAngle: Float = .pi)
    }

    public struct BillboardAxes: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let x = Self(rawValue: 1 << 0)
        public static let y = Self(rawValue: 1 << 1)
        public static let z = Self(rawValue: 1 << 2)
        public static let all: Self = [.x, .y, .z]
    }

    // Applies every node's constraints, parents before children. `pointOfView` is the camera's world transform,
    // used by billboards.
    public func applyConstraints(pointOfView: simd_float4x4) {
        var constrained: [Node] = []
        visit(includeHidden: true) { node, _ in
            if !node.constraints.isEmpty {
                constrained.append(node)
            }
        }
        for node in constrained {
            for constraint in node.constraints {
                node.apply(constraint, pointOfView: pointOfView, sceneGraph: self)
            }
        }
    }
}

extension SceneGraph.Node {
    func apply(_ constraint: SceneGraph.Constraint, pointOfView: simd_float4x4, sceneGraph: SceneGraph? = nil) {
        if case let .inverseKinematics(chainRoot, target, iterations, maximumAngle) = constraint {
            solveInverseKinematics(chainRoot: chainRoot, target: target.worldTransform.columns.3.xyz, iterations: iterations, maximumAngle: maximumAngle)
            return
        }
        let parentWorld = parent?.worldTransform ?? matrix_identity_float4x4
        let world = SceneGraph.TRS(matrix: parentWorld * transform)
        var desired = world
        switch constraint {
        case let .lookAt(target, worldUp, localFront):
            let targetPosition = target.worldTransform.columns.3.xyz
            guard let rotation = lookRotation(from: world.translation, to: targetPosition, worldUp: worldUp, localFront: localFront) else {
                return
            }
            desired.rotation = rotation
        case let .billboard(freeAxes):
            let toCamera = pointOfView.columns.3.xyz - world.translation
            let axes: [SIMD3<Float>] = [[1, 0, 0], [0, 1, 0], [0, 0, 1]]
            let free = [SceneGraph.BillboardAxes.x, .y, .z].indices.filter { freeAxes.contains([SceneGraph.BillboardAxes.x, .y, .z][$0]) }
            switch free.count {
            case 3:
                desired.rotation = SceneGraph.TRS(matrix: pointOfView).rotation
            case 2:
                // Face the camera position, keeping an up vector so there is no roll.
                let up = free.contains(1) ? axes[1] : axes[free[0]]
                guard let rotation = lookRotation(from: world.translation, to: pointOfView.columns.3.xyz, worldUp: up, localFront: [0, 0, 1]) else {
                    return
                }
                desired.rotation = rotation
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
                desired.rotation = simd_quatf(angle: atan2(simd_dot(simd_cross(reference, direction), axis), simd_dot(reference, direction)), axis: axis)
            default:
                return
            }
        case let .replicator(target, position, orientation, scale, positionOffset, orientationOffset, scaleOffset):
            let targetWorld = SceneGraph.TRS(matrix: target.worldTransform)
            if position {
                desired.translation = (target.worldTransform * SIMD4(positionOffset, 1)).xyz
            }
            if orientation {
                desired.rotation = simd_normalize(targetWorld.rotation * orientationOffset)
            }
            if scale {
                desired.scale = targetWorld.scale * scaleOffset
            }
        case let .avoidOccluder(target, categoryBitMask, bias):
            guard let sceneGraph else {
                return
            }
            let targetPosition = target.worldTransform.columns.3.xyz
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
        }
        trs = SceneGraph.TRS(matrix: parentWorld.inverse * desired.matrix)
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
                let parentRotation = SceneGraph.TRS(matrix: joint.parent?.worldTransform ?? matrix_identity_float4x4).rotation
                let localTurn = parentRotation.inverse * turn * parentRotation
                joint.trs.rotation = simd_normalize(localTurn * joint.trs.rotation)
            }
            if simd_distance(worldTransform.columns.3.xyz, target) < 1e-4 {
                return
            }
        }
    }

    private func lookRotation(from position: SIMD3<Float>, to target: SIMD3<Float>, worldUp: SIMD3<Float>, localFront: SIMD3<Float>) -> simd_quatf? {
        let direction = target - position
        guard simd_length(direction) > 1e-6 else {
            return nil
        }
        let forward = simd_normalize(direction)
        // Basis whose -Z is `forward`; fall back to another up vector when looking straight along `worldUp`.
        let up = abs(simd_dot(forward, simd_normalize(worldUp))) > 0.999 ? SIMD3<Float>(0, 0, 1) : simd_normalize(worldUp)
        let right = simd_normalize(simd_cross(forward, up))
        let trueUp = simd_cross(right, forward)
        let basis = simd_quatf(simd_float3x3(columns: (right, trueUp, -forward)))
        // Turn `localFront` onto -Z first, so the basis then points it at the target.
        return simd_normalize(basis * simd_quatf(from: simd_normalize(localFront), to: [0, 0, -1]))
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
