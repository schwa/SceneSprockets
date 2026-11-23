import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

// #640: the HDR scene path and bloom.
private let size = 64

@MainActor
private func render(_ sceneGraph: SceneGraph, sampleCount: Int = 1) throws -> [SIMD4<UInt8>] {
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()], sampleCount: sampleCount)).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    return pixels
}

private func brightness(_ pixel: SIMD4<UInt8>) -> Int {
    Int(pixel.x) + Int(pixel.y) + Int(pixel.z)
}

// A small, very bright sphere on black, and a lit gray box beside it.
@MainActor
private func makeScene(bloom: SceneGraph.PostProcessing.Bloom?) -> SceneGraph {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 6]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .light(.point(intensity: 30))))
    let glow = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([20, 20, 20]))
    root.addChild(SceneGraph.Node(shape: .sphere(radius: 0.15), material: glow))
    root.addChild(SceneGraph.Node(shape: .box(width: 0.6, height: 0.6, length: 0.6), material: PBRSceneMaterial(baseColor: [0.5, 0.5, 0.5], roughness: 0.8), transform: .init(translation: [1.2, 0, 0])))
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.intensity = 0
    sceneGraph.postProcessing = bloom.map { SceneGraph.PostProcessing(bloom: $0) }
    return sceneGraph
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: [1, 4])
@MainActor
func bloomGlowsAroundBrightPixels(sampleCount: Int) throws {
    // Just outside the sphere's edge (radius 0.15 at distance 6 is about 4 pixels at this size).
    let near = (size / 2) * size + size / 2 + 7
    let plain = try render(makeScene(bloom: nil), sampleCount: sampleCount)
    let bloomed = try render(makeScene(bloom: .init(threshold: 1, intensity: 1, radius: 5)), sampleCount: sampleCount)
    #expect(brightness(plain[near]) < 10, "\(plain[near])")
    #expect(brightness(bloomed[near]) > brightness(plain[near]) + 30, "\(bloomed[near])")
}

// With no glow, the HDR path draws what the default path draws: exposure and tone mapping move to the composite.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func hdrPathMatchesTheDefaultPath() throws {
    let plain = try render(makeScene(bloom: nil))
    let hdr = try render(makeScene(bloom: .init(threshold: 1_000, intensity: 0)))
    let largest = zip(plain, hdr).map { a, b in (0 ..< 3).map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0 }.max() ?? 0
    #expect(largest <= 3, "largest difference \(largest)")
}

@Test
func bloomIsArchived() throws {
    let settings = SceneGraph.PostProcessing(contrast: 1.1, bloom: .init(threshold: 2, intensity: 0.3, radius: 4))
    #expect(try JSONDecoder().decode(SceneGraph.PostProcessing.self, from: JSONEncoder().encode(settings)) == settings)
    let old = #"{"exposure":0,"contrast":1,"saturation":1,"vignetteIntensity":0,"vignetteRadius":0.6}"#
    #expect(try JSONDecoder().decode(SceneGraph.PostProcessing.self, from: Data(old.utf8)).bloom == nil)
}
