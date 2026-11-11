import GeometryLite3D
@testable import SceneSprockets
import simd
import Testing

private func isClose(_ lhs: simd_float4x4, _ rhs: simd_float4x4) -> Bool {
    (0..<4).allSatisfy { simd_distance(lhs[$0], rhs[$0]) < 0.0001 }
}

// #78: rotation applies about the pivot; the pivot point stays at the node's position.
@Test
func pivotMovesTheRotationCenter() {
    let root = SceneGraph.Node()
    let node = root.addChild(SceneGraph.Node(trs: .init(translation: [5, 0, 0], rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))))
    node.pivot = simd_float4x4(translation: [1, 0, 0])
    let child = node.addChild(SceneGraph.Node(trs: .init(translation: [1, 0, 0])))
    // The child sits on the pivot point, so it lands on the node's position.
    #expect(simd_distance(child.worldTransform.columns.3, [5, 0, 0, 1]) < 1e-5)
    let origin = node.addChild(SceneGraph.Node())
    // Content origin is 1 unit from the pivot, rotated 90 degrees: (5, -1).
    #expect(simd_distance(origin.worldTransform.columns.3, [5, -1, 0, 1]) < 1e-5)
    let sceneGraph = SceneGraph(root: root)
    #expect(sceneGraph.nodesWithWorldTransforms().contains { $0.node === origin && simd_distance($0.worldTransform.columns.3, [5, -1, 0, 1]) < 1e-5 })
    // The stored transform does not include the pivot.
    #expect(node.trs.translation == [5, 0, 0])
}

@Test
func trsIsStoredLosslessly() {
    let rotation = simd_quatf(angle: .pi / 3, axis: simd_normalize([1, 1, 0]))
    let trs = Transform3D(translation: [1, 2, 3], rotation: rotation, scale: [2, 2, 2])
    let node = SceneGraph.Node(trs: trs)

    #expect(node.trs == trs)
    #expect(isClose(node.transform, simd_float4x4(translation: [1, 2, 3]) * simd_float4x4(rotation) * simd_float4x4(diagonal: [2, 2, 2, 1])))

    node.trs.scale = [3, 3, 3]
    #expect(node.trs.rotation.quaternion == rotation)
    #expect(node.trs.translation == [1, 2, 3])
}

@Test
func matrixTransformDecomposesToTRS() {
    let rotation = simd_quatf(angle: .pi / 4, axis: [0, 1, 0])
    let matrix = simd_float4x4(translation: [4, 5, 6]) * simd_float4x4(rotation) * simd_float4x4(diagonal: [1, 2, 3, 1])
    let node = SceneGraph.Node(transform: matrix)

    #expect(isClose(node.trs.matrix, matrix))
    #expect(simd_distance(node.trs.translation, [4, 5, 6]) < 0.0001)
    #expect(simd_distance(node.trs.scale, [1, 2, 3]) < 0.0001)
}

@Test
func settingTRSUpdatesWorldTransforms() {
    let root = SceneGraph.Node()
    let child = root.addChild(SceneGraph.Node())
    child.trs.translation = [0, 0, 5]

    let world = SceneGraph(root: root).nodesWithWorldTransforms().last!.worldTransform
    #expect(world.columns.3 == SIMD4<Float>(0, 0, 5, 1))
}

private extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
