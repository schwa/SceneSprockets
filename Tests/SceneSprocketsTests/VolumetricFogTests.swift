import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #540: volumetric fog dims what is behind it and scatters light, where the light's shadow allows.

private let size = 96

@MainActor
private struct FogScene {
    let sceneGraph: SceneGraph
    let device: MTLDevice

    // Camera at (0, 2, 8) looking down -Z; a spot light at (0, 6, 0) shining straight down with a 30 degree cone.
    init(occluder: Bool = false, emissiveWall: Bool = false, light: Bool = true) throws {
        device = try #require(MTLCreateSystemDefaultDevice())
        let root = SceneGraph.Node()
        root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, 8]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: 0.1 ... 100))))))
        if light {
            var spot = Light.spot(color: [1, 1, 1], intensity: 40, innerConeAngle: .pi / 8, outerConeAngle: .pi / 6)
            spot.castsShadow = true
            root.addChild(SceneGraph.Node(transform: .init(translation: [0, 6, 0], rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])), content: .light(spot)))
        }
        if occluder {
            let box = MetalMesh(mesh: .box(), device: device)
            root.addChild(SceneGraph.Node(transform: .init(translation: [0, 3.5, 0], scale: [1.5, 0.2, 1.5]), content: .mesh(box, material: BlinnPhongSceneMaterial(color: [0.1, 0.1, 0.1]))))
        }
        if emissiveWall {
            let wall = MetalMesh(mesh: .quad(extents: [40, 40]), device: device)
            root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, -2]), content: .mesh(wall, material: BlinnPhongSceneMaterial(color: .zero, emission: [1, 1, 1]))))
        }
        sceneGraph = SceneGraph(root: root)
    }

    func render(scattering: SceneGraph.Fog.Scattering?, shadows: Bool = false) throws -> MTLTexture {
        // Distance fog off (alpha 0), so only scattering changes the image.
        sceneGraph.fog = SceneGraph.Fog(color: [0, 0, 0, 0], scattering: scattering)
        let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
        let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero)], shadows: shadows ? Shadows(intensity: 1) : nil)
        return try renderer.render(element).texture
    }

    // The summed RGB of the pixel that `point` projects to.
    func brightness(_ texture: MTLTexture, at point: SIMD3<Float>) throws -> Int {
        let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
        let clip = context.projectionMatrix * context.viewMatrix * SIMD4(point, 1)
        let x = Int((clip.x / clip.w + 1) / 2 * Float(size))
        let y = Int((1 - clip.y / clip.w) / 2 * Float(size))
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return Int(value.x) + Int(value.y) + Int(value.z)
    }
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func scatteringShowsTheLightBeamOnly() throws {
    let scene = try FogScene()
    let scattering = SceneGraph.Fog.Scattering(density: 0.1, intensity: 1, anisotropy: 0, stepCount: 64, maximumDistance: 20)
    let clear = try scene.render(scattering: nil)
    let foggy = try scene.render(scattering: scattering)
    // A ray through the cone's middle, and one that passes well outside it (over the background).
    let inBeam = (clear: try scene.brightness(clear, at: [0, 2, 0]), foggy: try scene.brightness(foggy, at: [0, 2, 0]))
    let outside = (clear: try scene.brightness(clear, at: [-5, 5.5, 0]), foggy: try scene.brightness(foggy, at: [-5, 5.5, 0]))
    #expect(inBeam.foggy > inBeam.clear + 60, "beam \(inBeam)")
    #expect(outside.foggy < outside.clear + 20, "outside \(outside)")
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func scatteringFogDimsWhatIsBehindIt() throws {
    let scene = try FogScene(emissiveWall: true, light: false)
    let clear = try scene.brightness(try scene.render(scattering: nil), at: [0, 2, -2])
    let foggy = try scene.brightness(try scene.render(scattering: .init(density: 0.2, stepCount: 16)), at: [0, 2, -2])
    #expect(clear > 600, "clear \(clear)")
    // 10 units to the wall: exp(-0.2 * 10), about 14% of the light is left. The target is sRGB, so compare in linear.
    func linear(_ sum: Int) -> Float {
        let encoded = Float(sum) / 3 / 255
        return encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
    }
    let ratio = linear(foggy) / linear(clear)
    #expect(abs(ratio - exp(-2)) < 0.03, "clear \(clear) foggy \(foggy) ratio \(ratio)")
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shadowsCutTheBeam() throws {
    let scene = try FogScene(occluder: true)
    let scattering = SceneGraph.Fog.Scattering(density: 0.1, intensity: 1, anisotropy: 0, stepCount: 64, maximumDistance: 20)
    // Below the occluder: the ray crosses its shadow in the middle of the beam.
    let point: SIMD3<Float> = [0, 1.5, 0]
    let unshadowed = try scene.brightness(try scene.render(scattering: scattering, shadows: false), at: point)
    let shadowed = try scene.brightness(try scene.render(scattering: scattering, shadows: true), at: point)
    #expect(shadowed < unshadowed - 30, "unshadowed \(unshadowed) shadowed \(shadowed)")
}
