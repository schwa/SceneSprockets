import GeometryLite3D
@testable import SceneSprockets
import simd
import Testing

// #407: splines through points, sampled by distance, and an action that moves a node along one.

@Test
func splinePassesThroughItsPointsAtEvenSpeed() {
    let square: [SIMD3<Float>] = [[0, 0, 0], [4, 0, 0], [4, 0, 4], [0, 0, 4]]
    let open = SceneGraph.Spline(points: square)
    #expect(simd_distance(open.position(at: 0), square[0]) < 1e-4)
    #expect(simd_distance(open.position(at: 1), square[3]) < 1e-4)
    // Passes through the middle points.
    #expect((0...100).contains { simd_distance(open.position(at: Float($0) / 100), square[1]) < 0.15 })
    // Roughly the polyline's length, a little more for the curve.
    #expect(open.length > 11.5 && open.length < 13)
    // Even speed: equal steps of t cover about equal distances.
    let steps = (0..<10).map { simd_distance(open.position(at: Float($0) / 10), open.position(at: Float($0 + 1) / 10)) }
    #expect((steps.max() ?? 0) / (steps.min() ?? 1) < 1.2, "\(steps)")
    // A closed spline comes back to its start.
    let loop = SceneGraph.Spline(points: square, isClosed: true)
    #expect(simd_distance(loop.position(at: 1), square[0]) < 1e-4)
    #expect(loop.length > open.length)
    // Tangents follow the direction of travel.
    #expect(simd_dot(open.tangent(at: 0.02), [1, 0, 0]) > 0.9)
}

@Test
func followActionMovesAlongSplineAndFacesTravel() {
    let root = SceneGraph.Node()
    let graph = SceneGraph(root: root)
    let node = root.addChild(SceneGraph.Node())
    let path = SceneGraph.Spline(points: [[0, 0, 0], [10, 0, 0]])
    node.run(.follow(path, duration: 2, orientsToPath: true))
    graph.advanceActions(by: 1)
    #expect(simd_distance(node.transform.translation, [5, 0, 0]) < 0.05, "\(node.transform.translation)")
    // Nodes look down -Z, so facing +X means -Z maps to +X.
    let forward = node.transform.rotation.quaternion.act([0, 0, -1])
    #expect(simd_distance(forward, [1, 0, 0]) < 1e-3, "\(forward)")
    graph.advanceActions(by: 1.5)
    #expect(simd_distance(node.transform.translation, [10, 0, 0]) < 1e-3)
    #expect(!node.hasActions)
}
