import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #508: one adaptation step moves towards the target, limited by speed and range.
@Test
func autoExposureStepIsLimited() {
    let settings = AutoExposure.Settings(targetLuminance: 0.18, adaptationSpeed: 1, range: 0.5 ... 4)
    // Two stops too dark, one second: one stop up.
    #expect(AutoExposure.adapted(exposure: 1, meteredLog2Luminance: log2(0.18) - 2, settings: settings, elapsed: 1) == 2)
    // Far too dark for a long time: clamped to the range.
    #expect(AutoExposure.adapted(exposure: 1, meteredLog2Luminance: -20, settings: settings, elapsed: 100) == 4)
    // Too bright.
    #expect(AutoExposure.adapted(exposure: 1, meteredLog2Luminance: log2(0.18) + 3, settings: settings, elapsed: 0.5) == pow(2, -0.5))
    // On target: unchanged.
    #expect(AutoExposure.adapted(exposure: 1.5, meteredLog2Luminance: log2(0.18), settings: settings, elapsed: 1) == 1.5)
}

// #508: a dark scene is brightened over a few frames.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func autoExposureBrightensDarkScene() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let dark = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0.03), specular: .color(0), shininess: 1)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(scale: [3, 3, 1]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: dark)))
    root.addChild(SceneGraph.Node(content: .light(.directional())))
    let camera = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    let sceneGraph = SceneGraph(linearRoot: root)
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let autoExposure = AutoExposure(adaptationSpeed: 1_000)

    func centerBrightness() throws -> Int {
        let element = SceneGraphElement(sceneGraph: sceneGraph, camera: camera, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], autoExposure: autoExposure)
        let texture = try renderer.render(element).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
        return Int(value.x)
    }
    let first = try centerBrightness()
    var last = first
    for _ in 0..<20 {
        last = try centerBrightness()
    }
    #expect(autoExposure.exposure > 2)
    #expect(last > first + 20)
}
