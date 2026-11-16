import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

// #45: a box on a floor, both flat-lit (ambient only), seen from above and in front. `emissive` (#136) lights them
// by emission instead of ambient light; `material` replaces both materials.
@MainActor
private func render(_ postProcessing: SceneGraph.PostProcessing?, color: SIMD3<Float> = [0.8, 0.8, 0.8], ambientOcclusion: SceneGraph.AmbientOcclusion? = nil, emissive: Bool = false, material: (any SceneMaterial)? = nil, boxMaterial: (any SceneMaterial)? = nil, renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1])]) throws -> (SceneGraph, MTLTexture) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let material = material ?? (emissive
        ? BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color))
        : BlinnPhongSceneMaterial(ambient: .color(color), diffuse: .color(0), specular: .color(0), shininess: 1))
    let root = SceneGraph.Node()
    let eye: SIMD3<Float> = [0, 3, 4]
    let forward = simd_normalize(-eye)
    let right = simd_normalize(simd_cross(forward, [0, 1, 0]))
    let up = simd_cross(right, forward)
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(columns: (SIMD4(right, 0), SIMD4(up, 0), SIMD4(-forward, 0), SIMD4(eye, 1)))), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    root.addChild(SceneGraph.Node(label: "Floor", transform: .init(translation: [0, -0.05, 0], scale: [6, 0.1, 6]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: material)))
    root.addChild(SceneGraph.Node(label: "Box", transform: .init(translation: [0, 0.5, 0]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: boxMaterial ?? material)))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.postProcessing = postProcessing
    sceneGraph.environment.ambientOcclusion = ambientOcclusion
    let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    return (sceneGraph, try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers)).texture)
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
    let (_, occluded) = try render(nil, ambientOcclusion: strongOcclusion)
    let occludedContact = try pixel(occluded, sceneGraph, at: contact)
    let plainContact = try pixel(plain, sceneGraph, at: contact)
    #expect(Int(occludedContact.x) < Int(plainContact.x) - 15)
    let occludedOpen = try pixel(occluded, sceneGraph, at: open)
    let plainOpen = try pixel(plain, sceneGraph, at: open)
    #expect(abs(Int(occludedOpen.x) - Int(plainOpen.x)) <= 8)
}

// #136: occlusion reduces only ambient light, so emission at a contact is unchanged.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func ambientOcclusionLeavesEmissionAlone() throws {
    let (sceneGraph, plain) = try render(nil, emissive: true)
    let (_, occluded) = try render(nil, ambientOcclusion: strongOcclusion, emissive: true)
    let occludedContact = try pixel(occluded, sceneGraph, at: contact)
    let plainContact = try pixel(plain, sceneGraph, at: contact)
    #expect(abs(Int(occludedContact.x) - Int(plainContact.x)) <= 2)
}

// #136: materials that do not apply occlusion while shading, PBR included (#408), are still darkened after the scene
// pass.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [false, true])
@MainActor
func ambientOcclusionDarkensOtherMaterials(usesPBR: Bool) throws {
    let material: any SceneMaterial = usesPBR ? PBRSceneMaterial(baseColor: [0.8, 0.8, 0.8], roughness: 1) : ShaderMaterial.rim(color: [0.8, 0.8, 0.8])
    let renderers: [any MaterialRenderer] = usesPBR ? [PBRMaterialRenderer()] : [ShaderMaterialRenderer()]
    let (sceneGraph, plain) = try render(nil, material: material, renderers: renderers)
    let (_, occluded) = try render(nil, ambientOcclusion: strongOcclusion, material: material, renderers: renderers)
    #expect(Int(try pixel(occluded, sceneGraph, at: contact).x) < Int(try pixel(plain, sceneGraph, at: contact).x) - 10)
}

// #136: with in-shader and other materials together, each pixel is darkened once, by its front surface's path.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func ambientOcclusionInMixedScenes() throws {
    let box = ShaderMaterial.rim(color: [0.8, 0.8, 0.8])
    let renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1]), ShaderMaterialRenderer()]
    let (sceneGraph, plain) = try render(nil, emissive: true, boxMaterial: box, renderers: renderers)
    let (_, occluded) = try render(nil, ambientOcclusion: strongOcclusion, emissive: true, boxMaterial: box, renderers: renderers)
    // The emissive floor at the contact is unchanged; the box's base edge, just above it, is darkened.
    #expect(abs(Int(try pixel(occluded, sceneGraph, at: contact).x) - Int(try pixel(plain, sceneGraph, at: contact).x)) <= 2)
    let boxBase: SIMD3<Float> = [0, 0.08, 0.5]
    #expect(Int(try pixel(occluded, sceneGraph, at: boxBase).x) < Int(try pixel(plain, sceneGraph, at: boxBase).x) - 5)
}

private let strongOcclusion = SceneGraph.AmbientOcclusion(radius: 0.5, intensity: 1, sampleCount: 32)
// Floor right at the box's front base, and floor far from it.
private let contact: SIMD3<Float> = [0, 0, 0.55]
private let open: SIMD3<Float> = [1.5, 0, 1.5]
