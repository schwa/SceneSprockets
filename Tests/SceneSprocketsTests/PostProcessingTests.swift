import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #45: a box on a floor, both flat-lit (ambient only), seen from above and in front.
@MainActor
private func render(_ postProcessing: SceneGraph.PostProcessing?, color: SIMD3<Float> = [0.8, 0.8, 0.8]) throws -> (SceneGraph, MTLTexture) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let material = BlinnPhongSceneMaterial(ambient: .color(color), diffuse: .color(0), specular: .color(0), shininess: 1)
    let root = SceneGraph.Node()
    let eye: SIMD3<Float> = [0, 3, 4]
    let forward = simd_normalize(-eye)
    let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
    let up = simd_cross(right, forward)
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(columns: (SIMD4(right, 0), SIMD4(up, 0), SIMD4(-forward, 0), SIMD4(eye, 1)))), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    root.addChild(SceneGraph.Node(label: "Floor", transform: .init(translation: [0, -0.05, 0], scale: [6, 0.1, 6]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: material)))
    root.addChild(SceneGraph.Node(label: "Box", transform: .init(translation: [0, 0.5, 0]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: material)))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.postProcessing = postProcessing
    let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    return (sceneGraph, try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1])])).texture)
}

@MainActor
private func pixel(_ texture: MTLTexture, _ sceneGraph: SceneGraph, at point: SIMD3<Float>) throws -> SIMD4<UInt8> {
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let clip = context.projectionMatrix * context.viewMatrix * SIMD4(point, 1)
    let x = Int((clip.x / clip.w + 1) / 2 * 64)
    let y = Int((1 - clip.y / clip.w) / 2 * 64)
    // Off-screen points would read outside the texture (#297).
    try #require((0..<texture.width).contains(x) && (0..<texture.height).contains(y), "\(point) projects to (\(x), \(y)), outside the texture")
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
    return value
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func colorAdjustmentChangesSaturationExposureAndCorners() throws {
    let floorPoint: SIMD3<Float> = [1.5, 0, 1.5]
    let (sceneGraph, plain) = try render(nil, color: [0.5, 0.2, 0.1])
    let base = try pixel(plain, sceneGraph, at: floorPoint)
    let (_, grey) = try render(.init(saturation: 0), color: [0.5, 0.2, 0.1])
    let greyPixel = try pixel(grey, sceneGraph, at: floorPoint)
    #expect(abs(Int(greyPixel.x) - Int(greyPixel.z)) <= 2)
    #expect(Int(base.z) - Int(base.x) > 30)
    let (_, brighter) = try render(.init(exposure: 1), color: [0.5, 0.2, 0.1])
    #expect(try pixel(brighter, sceneGraph, at: floorPoint).z > base.z)
    let (_, vignette) = try render(.init(vignetteIntensity: 1, vignetteRadius: 0), color: [0.5, 0.2, 0.1])
    var corner = SIMD4<UInt8>.zero
    var plainCorner = SIMD4<UInt8>.zero
    vignette.getBytes(&corner, bytesPerRow: 4, from: MTLRegionMake2D(2, 62, 1, 1), mipmapLevel: 0)
    plain.getBytes(&plainCorner, bytesPerRow: 4, from: MTLRegionMake2D(2, 62, 1, 1), mipmapLevel: 0)
    #expect(Int(corner.z) < Int(plainCorner.z) - 20)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func ambientOcclusionDarkensContactsOnly() throws {
    let (sceneGraph, plain) = try render(nil)
    let (_, occluded) = try render(.init(ambientOcclusion: .init(radius: 0.5, intensity: 1, sampleCount: 32)))
    // Floor right at the box's front base, and floor far from it.
    let contact: SIMD3<Float> = [0, 0, 0.55]
    let open: SIMD3<Float> = [1.5, 0, 1.5]
    let occludedContact = try pixel(occluded, sceneGraph, at: contact)
    let plainContact = try pixel(plain, sceneGraph, at: contact)
    #expect(Int(occludedContact.x) < Int(plainContact.x) - 15)
    let occludedOpen = try pixel(occluded, sceneGraph, at: open)
    let plainOpen = try pixel(plain, sceneGraph, at: open)
    #expect(abs(Int(occludedOpen.x) - Int(plainOpen.x)) <= 8)
}
