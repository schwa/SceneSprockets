import Foundation
import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #337: hit test cost on a large static scene. Skipped unless SCENESPROCKETS_BENCHMARK=1; run it alone.
// Prints `METRIC name=value` lines.

private let isEnabled = ProcessInfo.processInfo.environment["SCENESPROCKETS_BENCHMARK"] == "1"

@Test(.enabled(if: isEnabled))
func hitTestBenchmark() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // 400 spheres of 64 x 128 segments (~16k triangles each, 6.5M in all), 3 apart in a 20 x 20 grid.
    let sphere = MetalMesh(mesh: .sphere(latitudeSegments: 64, longitudeSegments: 128), device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
    let root = SceneGraph.Node()
    for x in 0 ..< 20 {
        for y in 0 ..< 20 {
            root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(translation: [Float(x) * 3, Float(y) * 3, 0])), content: .mesh(sphere, material: material)))
        }
    }
    let graph = SceneGraph(root: root)
    // Rays from in front of the grid toward random points on it; most hit a sphere.
    var generator = SystemRandomNumberGenerator()
    let rays = (0 ..< 500).map { _ in
        let target = SIMD3<Float>(.random(in: 0 ... 57, using: &generator), .random(in: 0 ... 57, using: &generator), 0)
        return Ray3D(origin: [28.5, 28.5, 40], direction: target - [28.5, 28.5, 40])
    }
    func run(_ options: SceneGraph.HitTestOptions) -> Int {
        rays.reduce(0) { $0 + graph.hitTest($1, options: options).count }
    }
    // First pass reads and caches geometry; it is timed separately.
    let clock = ContinuousClock()
    var hits = 0
    let first = clock.measure { hits = run(SceneGraph.HitTestOptions()) }
    var best = Duration.seconds(1_000)
    for _ in 0 ..< 3 {
        best = min(best, clock.measure { hits = run(SceneGraph.HitTestOptions()) })
    }
    func microseconds(_ duration: Duration) -> Double {
        (Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) / 1e12) / Double(rays.count)
    }
    print("METRIC hit_test_first_us_per_ray=\(String(format: "%.1f", microseconds(first)))")
    print("METRIC hit_test_us_per_ray=\(String(format: "%.1f", microseconds(best)))")
    print("BENCHMARK hits \(hits)")
}
