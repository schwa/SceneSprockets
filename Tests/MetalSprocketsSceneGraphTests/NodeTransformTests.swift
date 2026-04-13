import Testing
import simd
@testable import MetalSprocketsSceneGraph

private func isClose(_ lhs: simd_float4x4, _ rhs: simd_float4x4) -> Bool {
    (0..<4).allSatisfy { simd_distance(lhs[$0], rhs[$0]) < 0.0001 }
}

@Test
func trsIsStoredLosslessly() {
    let rotation = simd_quatf(angle: .pi / 3, axis: simd_normalize([1, 1, 0]))
    let trs = SceneGraph.TRS(translation: [1, 2, 3], rotation: rotation, scale: [2, 2, 2])
    let node = SceneGraph.Node(trs: trs)

    #expect(node.trs == trs)
    #expect(isClose(node.transform, simd_float4x4(translation: [1, 2, 3]) * simd_float4x4(rotation) * simd_float4x4(diagonal: [2, 2, 2, 1])))

    node.trs.scale = [3, 3, 3]
    #expect(node.trs.rotation == rotation)
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
    let child = SceneGraph.Node(parent: root)
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
