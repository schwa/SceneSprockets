import Foundation
import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #584: frustum culling cost, linear versus the mesh entry index. Skipped unless SCENESPROCKETS_BENCHMARK=1; run it
// alone. Prints `METRIC name=value` lines.

private let isEnabled = ProcessInfo.processInfo.environment["SCENESPROCKETS_BENCHMARK"] == "1"

@Test(.enabled(if: isEnabled))
func cullingBenchmark() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
    // 10,000 boxes in a 100 x 100 grid, 3 apart; the camera sees a corner of it.
    let root = SceneGraph.Node()
    for x in 0 ..< 100 {
        for y in 0 ..< 100 {
            root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [Float(x) * 3, Float(y) * 3, 0])), content: .mesh(box, material: material)))
        }
    }
    let graph = SceneGraph(root: root)
    let entries = graph.meshEntries()
    let camera = LookAt(position: [20, 20, 40], target: [20, 20, 0], up: [0, 1, 0]).viewMatrix.inverse
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .standard(zClip: 0.1 ... 1_000)).projectionMatrix(aspectRatio: 1)
    let clock = ContinuousClock()
    func best(_ repeats: Int = 20, _ body: () -> Void) -> Double {
        var best = Duration.seconds(1_000)
        for _ in 0 ..< repeats {
            best = min(best, clock.measure(body))
        }
        return (Double(best.components.seconds) * 1e6 + Double(best.components.attoseconds) / 1e12)
    }
    var visible = 0
    let linear = best { visible = meshEntriesInFrustum(entries, projectionMatrix: projection, cameraMatrix: camera).filter(\.self).count }
    let build = best(5) { _ = MeshEntryIndex(entries: entries) }
    let frustum = Frustum(viewProjection: projection * camera.inverse)
    var indexed = 0
    let query = best { indexed = graph.meshEntries(in: frustum).count }
    print("METRIC cull_linear_us=\(String(format: "%.1f", linear))")
    print("METRIC index_build_us=\(String(format: "%.1f", build))")
    print("METRIC cull_index_query_us=\(String(format: "%.1f", query))")
    print("BENCHMARK visible linear \(visible) index \(indexed) of \(entries.count)")
}
