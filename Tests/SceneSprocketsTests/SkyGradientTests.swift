import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import Testing

private let gradient = SceneGraph.Environment.SkyGradient(zenith: [0, 0, 1], horizon: [0, 1, 0], ground: [1, 0, 0])

// #247: the center pixel (BGRA) of an empty scene with a gradient sky, the camera pitched by `pitch` radians.
@MainActor
private func skyPixel(pitch: Float) throws -> SIMD4<UInt8> {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(rotation: simd_quatf(angle: pitch, axis: [1, 0, 0])), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(10)))))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.environment.background = .gradient(gradient)
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func gradientSkyDrawsWithoutPBR() throws {
    let level = try skyPixel(pitch: 0)
    // The center pixel is half a pixel off level, and sRGB encoding lifts the small ground mix.
    #expect(level.y > 240 && level.x < 15 && level.z < 40, "\(level)")
    let up = try skyPixel(pitch: .pi / 2)
    #expect(up.x > 240 && up.y < 15 && up.z < 15, "\(up)")
    let down = try skyPixel(pitch: -.pi / 2)
    #expect(down.z > 240 && down.x < 15 && down.y < 15, "\(down)")
}

@Test
func gradientBackgroundRoundTripsThroughArchive() throws {
    let background = SceneGraph.Environment.Background.gradient(gradient)
    let data = try JSONEncoder().encode(background)
    let decoded = try JSONDecoder().decode(SceneGraph.Environment.Background.self, from: data)
    guard case let .gradient(value) = decoded else {
        Issue.record("Decoded \(decoded)")
        return
    }
    #expect(value == gradient)
}
