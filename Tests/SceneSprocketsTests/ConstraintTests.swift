import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

private func front(of node: SceneGraph.Node) -> SIMD3<Float> {
    let matrix = node.worldTransform
    return simd_normalize(-SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
}

@Test
func lookAtPointsFrontAtTarget() {
    let root = SceneGraph.Node()
    let target = root.addChild(SceneGraph.Node(transform: .init(translation: [5, 0, 0])))
    let parent = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 0], rotation: simd_quatf(angle: 1, axis: [0, 1, 0]), scale: [2, 2, 2])))
    let node = parent.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 0])))
    node.constraints = [.lookAt(target: target)]
    SceneGraph(root: root).applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(simd_distance(front(of: node), [1, 0, 0]) < 1e-4)
    // World scale from the parent is kept.
    #expect(abs(simd_length(node.worldTransform.columns.0) - 2) < 1e-4)
    // Up stays up.
    #expect(node.worldTransform.columns.1.y > 0.99 * 2)
}

@Test
func lookAtWithCustomFront() {
    let root = SceneGraph.Node()
    let target = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5])))
    let node = root.addChild(SceneGraph.Node())
    node.constraints = [.lookAt(target: target, localFront: [1, 0, 0])]
    SceneGraph(root: root).applyConstraints(pointOfView: matrix_identity_float4x4)
    let xAxis = node.worldTransform.columns.0
    #expect(simd_distance(SIMD3(xAxis.x, xAxis.y, xAxis.z), [0, 0, 1]) < 1e-4)
}

@Test
func billboardMatchesCameraOrientation() {
    let root = SceneGraph.Node()
    let node = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, -5])))
    node.constraints = [.billboard()]
    let camera = simd_float4x4(simd_quatf(angle: 0.5, axis: [0, 1, 0]))
    SceneGraph(root: root).applyConstraints(pointOfView: camera)
    #expect(simd_distance(front(of: node), simd_normalize(-SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z))) < 1e-4)
    #expect(node.worldTransform.columns.3 == [0, 0, -5, 1])
}

@Test
func yBillboardOnlyYaws() {
    let root = SceneGraph.Node()
    let node = root.addChild(SceneGraph.Node())
    node.constraints = [.billboard(freeAxes: .y)]
    var camera = matrix_identity_float4x4
    camera.columns.3 = [5, 10, 0, 1]
    SceneGraph(root: root).applyConstraints(pointOfView: camera)
    // +Z faces the camera horizontally; Y stays up.
    let zAxis = node.worldTransform.columns.2
    #expect(simd_distance(SIMD3(zAxis.x, zAxis.y, zAxis.z), [1, 0, 0]) < 1e-4)
    #expect(abs(node.worldTransform.columns.1.y - 1) < 1e-4)
}

@Test
func distanceClampsAlongLine() {
    let root = SceneGraph.Node()
    let target = root.addChild(SceneGraph.Node(transform: .init(translation: [1, 0, 0])))
    let node = root.addChild(SceneGraph.Node(transform: .init(translation: [11, 0, 0])))
    node.constraints = [.distance(target: target, minimum: 1, maximum: 3)]
    let graph = SceneGraph(root: root)
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(simd_distance(node.transform.translation, [4, 0, 0]) < 1e-4)
    node.transform.translation = [1.5, 0, 0]
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(simd_distance(node.transform.translation, [2, 0, 0]) < 1e-4)
}

// #91
@Test
func replicatorCopiesTargetWithOffsets() {
    let root = SceneGraph.Node()
    let target = root.addChild(SceneGraph.Node(transform: .init(translation: [1, 2, 3], rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]), scale: [2, 2, 2])))
    let follower = root.addChild(SceneGraph.Node())
    follower.constraints = [.replicator(target: target, scale: false, positionOffset: [1, 0, 0])]
    SceneGraph(root: root).applyConstraints(pointOfView: matrix_identity_float4x4)
    // +X in the target's space is -Z in the world, scaled by 2.
    #expect(simd_distance(follower.transform.translation, [1, 2, 1]) < 1e-4)
    #expect(abs(follower.transform.rotation.quaternion.angle - .pi / 2) < 1e-4)
    #expect(simd_distance(follower.transform.scale, .one) < 1e-4)
}

@Test
func avoidOccluderMovesInFrontOfBlocker() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    let target = root.addChild(SceneGraph.Node())
    let camera = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 10])))
    // A 1-unit box centered at z = 5 blocks the line from the target to the camera.
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: ShaderMaterial.normals())))
    camera.constraints = [.avoidOccluder(target: target, bias: 0)]
    SceneGraph(root: root).applyConstraints(pointOfView: matrix_identity_float4x4)
    let bounds = try #require(root.children[2].meshBounds)
    #expect(abs(camera.transform.translation.z - (5 + bounds.min.z)) < 1e-3)
}

@Test
func transformConstraintAndBillboardAxes() {
    let root = SceneGraph.Node()
    let node = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 0])))
    node.constraints = [
        .transform { _, world in
            var result = world
            result.translation.y = 7
            return result
        }
    ]
    let graph = SceneGraph(root: root)
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(node.transform.translation.y == 7)

    // Free about X only: the node tips its +Z up towards a camera above it.
    let sprite = root.addChild(SceneGraph.Node())
    sprite.constraints = [.billboard(freeAxes: .x)]
    graph.applyConstraints(pointOfView: simd_float4x4(translation: [0, 5, 0]))
    #expect(simd_distance(sprite.transform.rotation.quaternion.act([0, 0, 1]), [0, 1, 0]) < 1e-4)
}

// #57: a two-bone arm (lengths 1 and 1) along +X reaches a target it can reach.
@Test
func inverseKinematicsReachesTarget() {
    let root = SceneGraph.Node()
    let shoulder = root.addChild(SceneGraph.Node())
    let elbow = shoulder.addChild(SceneGraph.Node(transform: .init(translation: [1, 0, 0])))
    let hand = elbow.addChild(SceneGraph.Node(transform: .init(translation: [1, 0, 0])))
    let target = root.addChild(SceneGraph.Node(transform: .init(translation: [1, 1.2, 0])))
    hand.constraints = [.inverseKinematics(chainRoot: shoulder, target: target, iterations: 50)]
    let graph = SceneGraph(root: root)
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    let reached = hand.worldTransform.columns.3.xyz
    #expect(simd_distance(reached, [1, 1.2, 0]) < 0.01)
    // Bone lengths are kept.
    let elbowPosition = elbow.worldTransform.columns.3.xyz
    #expect(abs(simd_length(elbowPosition) - 1) < 1e-4)
    // Out of reach: the arm points at the target, fully stretched.
    target.transform.translation = [0, 5, 0]
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    let stretched = hand.worldTransform.columns.3.xyz
    #expect(simd_distance(stretched, [0, 2, 0]) < 0.01)
}

// #91: influenceFactor blends between the unconstrained and constrained transform; disabled constraints do nothing.
@Test
func constraintInfluenceAndEnabled() {
    let root = SceneGraph.Node()
    let target = root.addChild(SceneGraph.Node(transform: .init(translation: [4, 0, 0])))
    let node = root.addChild(SceneGraph.Node())
    var constraint = SceneGraph.Constraint.replicator(target: target, orientation: false, scale: false)
    constraint.influenceFactor = 0.25
    node.constraints = [constraint]
    let graph = SceneGraph(root: root)
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(simd_distance(node.transform.translation, [1, 0, 0]) < 1e-5)

    node.transform.translation = .zero
    node.constraints[0].isEnabled = false
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(node.transform.translation == .zero)
}

// #91: acceleration limits how fast the node's position can change.
@Test
func accelerationConstraintLimitsSpeed() {
    let root = SceneGraph.Node()
    let node = root.addChild(SceneGraph.Node())
    node.constraints = [.acceleration(maximumLinearAcceleration: 2, maximumLinearVelocity: 1, damping: 0)]
    let graph = SceneGraph(root: root)
    graph.applyConstraints(pointOfView: matrix_identity_float4x4, deltaTime: 0.1)
    // The node jumps to x = 10; from rest it may only speed up by 2 m/s each second.
    node.transform.translation = [10, 0, 0]
    graph.applyConstraints(pointOfView: matrix_identity_float4x4, deltaTime: 0.1)
    #expect(abs(node.transform.translation.x - 0.02) < 1e-4)
    for _ in 0..<100 {
        node.transform.translation = [10, 0, 0]
        graph.applyConstraints(pointOfView: matrix_identity_float4x4, deltaTime: 0.1)
    }
    // Never faster than 1 m/s: at most 10 seconds' travel.
    #expect(node.transform.translation.x <= 10.0001)
    let before = node.transform.translation.x
    node.transform.translation = [10, 0, 0]
    graph.applyConstraints(pointOfView: matrix_identity_float4x4, deltaTime: 0.1)
    #expect(node.transform.translation.x - before <= 0.1 + 1e-4)
}
