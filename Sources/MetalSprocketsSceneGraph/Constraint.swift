import simd

extension SceneGraph {
    // Changes a node's transform from other nodes each frame, like SceneKit's SCNConstraint subclasses. Constraints
    // set the node's local TRS, keeping its world scale; run them with `SceneGraph.applyConstraints(pointOfView:)`
    // after animation and actions.
    public enum Constraint {
        // Turns the node so `localFront` points at `target`, keeping `worldUp` up when possible.
        case lookAt(target: Node, worldUp: SIMD3<Float> = [0, 1, 0], localFront: SIMD3<Float> = [0, 0, -1])
        // Turns the node to face the point of view (its +Z towards the camera, matching the camera's orientation).
        // With `.y` only the node turns about its Y axis, like a tree sprite.
        case billboard(freeAxes: BillboardAxes = .all)
        // Keeps the node between `minimum` and `maximum` from `target`, moving along the line between them.
        case distance(target: Node, minimum: Float = 0, maximum: Float = .infinity)
        // Turns the node's ancestors, from its parent up to `chainRoot`, so the node reaches towards `target`, like
        // SCNIKConstraint (cyclic coordinate descent). The node itself does not turn. `maximumAngle` (radians) limits
        // each joint's turn per step.
        case inverseKinematics(chainRoot: Node, target: Node, iterations: Int = 10, maximumAngle: Float = .pi)
    }

    public enum BillboardAxes: Sendable {
        case all
        case y
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
                node.apply(constraint, pointOfView: pointOfView)
            }
        }
    }
}

extension SceneGraph.Node {
    func apply(_ constraint: SceneGraph.Constraint, pointOfView: simd_float4x4) {
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
            let cameraRotation = SceneGraph.TRS(matrix: pointOfView).rotation
            switch freeAxes {
            case .all:
                desired.rotation = cameraRotation
            case .y:
                // Yaw only: face the camera's position projected onto the node's horizontal plane.
                var toCamera = pointOfView.columns.3.xyz - world.translation
                toCamera.y = 0
                guard simd_length(toCamera) > 1e-6 else {
                    return
                }
                desired.rotation = simd_quatf(angle: atan2(toCamera.x, toCamera.z), axis: [0, 1, 0])
            }
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
