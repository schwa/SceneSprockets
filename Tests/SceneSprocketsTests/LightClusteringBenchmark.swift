import CoreGraphics
import Foundation
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import Testing

// #519: frame time with many short-range lights, clustered and not. Skipped unless SCENESPROCKETS_BENCHMARK=1; run it
// alone. Prints `METRIC name=value` lines (median milliseconds per offscreen frame, which waits for the GPU).

private let isEnabled = ProcessInfo.processInfo.environment["SCENESPROCKETS_BENCHMARK"] == "1"

@Test(.enabled(if: isEnabled && deviceSupportsMetal4))
@MainActor
func lightClusteringBenchmark() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let cases: [(String, any SceneMaterial, any MaterialRenderer)] = [
        ("blinnphong", BlinnPhongSceneMaterial(color: [1, 1, 1]), BlinnPhongMaterialRenderer(ambientLightColor: .zero)),
        ("pbr", PBRSceneMaterial(baseColor: [1, 1, 1], roughness: 0.6), PBRMaterialRenderer(environmentIntensity: 0))
    ]
    let renderer = try OffscreenRenderer(size: CGSize(width: 1_920, height: 1_080))
    for (name, material, materialRenderer) in cases {
        for lightsPerSide in [4, 8, 16] {
            let scene = makeManyLightsScene(material: material, device: device, lightsPerSide: lightsPerSide)
            for clustering in [LightClustering.off, .on] {
                let element = SceneGraphElement(sceneGraph: scene, aspectRatio: 16 / 9, renderers: [materialRenderer]).lightClustering(clustering)
                _ = try renderer.render(element)
                let clock = ContinuousClock()
                let unsorted = try (0 ..< 20).map { _ in
                    let duration = try clock.measure { _ = try renderer.render(element) }
                    return Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1_000
                }
                let times = unsorted.sorted()
                print("METRIC \(name)_\(lightsPerSide * lightsPerSide)lights_\(clustering == .on ? "clustered" : "all")_ms=\(String(format: "%.3f", times[times.count / 2]))")
            }
        }
    }
}
