import Testing
import simd
@testable import MetalSprocketsSceneGraph

private func front(of node: SceneGraph.Node) -> SIMD3<Float> {
    let matrix = node.worldTransform
    return simd_normalize(-SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z))
}

@Test
func lookAtPointsFrontAtTarget() {
    let root = SceneGraph.Node()
    let target = SceneGraph.Node(parent: root, trs: .init(translation: [5, 0, 0]))
    let parent = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0], rotation: simd_quatf(angle: 1, axis: [0, 1, 0]), scale: [2, 2, 2]))
    let node = SceneGraph.Node(parent: parent, trs: .init(translation: [0, 0, 0]))
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
    let target = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 5]))
    let node = SceneGraph.Node(parent: root)
    node.constraints = [.lookAt(target: target, localFront: [1, 0, 0])]
    SceneGraph(root: root).applyConstraints(pointOfView: matrix_identity_float4x4)
    let xAxis = node.worldTransform.columns.0
    #expect(simd_distance(SIMD3(xAxis.x, xAxis.y, xAxis.z), [0, 0, 1]) < 1e-4)
}

@Test
func billboardMatchesCameraOrientation() {
    let root = SceneGraph.Node()
    let node = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, -5]))
    node.constraints = [.billboard()]
    let camera = simd_float4x4(simd_quatf(angle: 0.5, axis: [0, 1, 0]))
    SceneGraph(root: root).applyConstraints(pointOfView: camera)
    #expect(simd_distance(front(of: node), simd_normalize(-SIMD3(camera.columns.2.x, camera.columns.2.y, camera.columns.2.z))) < 1e-4)
    #expect(node.worldTransform.columns.3 == [0, 0, -5, 1])
}

@Test
func yBillboardOnlyYaws() {
    let root = SceneGraph.Node()
    let node = SceneGraph.Node(parent: root)
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
    let target = SceneGraph.Node(parent: root, trs: .init(translation: [1, 0, 0]))
    let node = SceneGraph.Node(parent: root, trs: .init(translation: [11, 0, 0]))
    node.constraints = [.distance(target: target, minimum: 1, maximum: 3)]
    let graph = SceneGraph(root: root)
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(simd_distance(node.trs.translation, [4, 0, 0]) < 1e-4)
    node.trs.translation = [1.5, 0, 0]
    graph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(simd_distance(node.trs.translation, [2, 0, 0]) < 1e-4)
}
