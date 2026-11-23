import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsShaderMaterial
import simd
import Testing

// #634: shadows in stereo match each eye drawn alone, for in-shader shadows (Blinn-Phong) and the screen-space mask
// (shader materials without samplesShadows).
private let size = 48

@MainActor
private func target(_ format: MTLPixelFormat, slices: Int, device: MTLDevice) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
    if slices > 1 {
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = slices
    }
    descriptor.usage = format == .depth32Float ? Shadows.requiredDepthUsage : Shadows.requiredColorUsage
    descriptor.storageMode = format == .depth32Float ? .private : .shared
    return try #require(device.makeTexture(descriptor: descriptor))
}

private func pixels(_ texture: MTLTexture, slice: Int) -> [SIMD4<UInt8>] {
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, bytesPerImage: size * size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: slice)
    return pixels
}

private func pose(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
    let forward = simd_normalize(eye - target)
    let right = simd_normalize(simd_cross([0, 1, 0], forward))
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(simd_cross(forward, right), 0), SIMD4(forward, 0), SIMD4(eye, 1)))
}

// A box over a floor, lit from above; returns each eye drawn alone and both eyes drawn at once.
@MainActor
private func renders(floor: any SceneMaterial, renderers: [any MaterialRenderer], shadows: Shadows?) throws -> (mono: [[SIMD4<UInt8>]], stereo: [[SIMD4<UInt8>]]) {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: .zero, target: [-0.3, -1, 0])), content: .light(.directional(intensity: 1))))
    root.addChild(SceneGraph.Node(shape: .box(width: 6, height: 0.1, length: 6), material: floor, transform: .init(translation: [0, -0.05, 0])))
    root.addChild(SceneGraph.Node(shape: .box(), material: BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.6), specular: .color(0), shininess: 1), transform: .init(translation: [0, 1, 0])))
    let sceneGraph = SceneGraph(linearRoot: root)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let camera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60)))
    let projection = simd_float4x4.reverseZ * camera.projection.projectionMatrix(aspectRatio: 1)
    let eyes = [-0.1, 0.1].map { offset in pose(eye: [Float(offset), 5, 4], target: [Float(offset), 0, 0]) }
    var mono: [[SIMD4<UInt8>]] = []
    for eye in eyes {
        let color = try target(.bgra8Unorm_srgb, slices: 1, device: device)
        let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: target(.depth32Float, slices: 1, device: device), clearDepth: 0)
        _ = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, cameraMatrix: eye, aspectRatio: 1, renderers: renderers, defaultCamera: camera, shadows: shadows))
        mono.append(pixels(color, slice: 0))
    }
    let viewport = MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1)
    let views = StereoViews(viewMatrices: eyes.map(\.inverse), projectionMatrices: eyes.map { _ in projection }, viewports: eyes.map { _ in viewport })
    let color = try target(.bgra8Unorm_srgb, slices: 2, device: device)
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: target(.depth32Float, slices: 2, device: device), clearDepth: 0)
    renderer.renderPassDescriptor.renderTargetArrayLength = 2
    _ = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers, defaultCamera: camera, shadows: shadows, stereoViews: views))
    return (mono, [pixels(color, slice: 0), pixels(color, slice: 1)])
}

// Pixels that differ by more than `tolerance` in any channel.
private func differingCount(_ lhs: [SIMD4<UInt8>], _ rhs: [SIMD4<UInt8>], tolerance: Int = 24) -> Int {
    zip(lhs, rhs).filter { a, b in (0 ..< 3).contains { abs(Int(a[$0]) - Int(b[$0])) > tolerance } }.count
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: ["Blinn-Phong", "Shader material"])
@MainActor
func stereoShadowsMatchMono(floorKind: String) throws {
    let floor: any SceneMaterial = floorKind == "Blinn-Phong"
        ? BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.6), specular: .color(0), shininess: 1)
        : ShaderMaterial.rim(color: [0.6, 0.6, 0.6])
    let renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(), ShaderMaterialRenderer()]
    let shadowed = try renders(floor: floor, renderers: renderers, shadows: Shadows(intensity: 0.8))
    let unshadowed = try renders(floor: floor, renderers: renderers, shadows: nil)
    for eye in 0 ..< 2 {
        // The shadow shows in each mono eye.
        let shadowPixels = differingCount(shadowed.mono[eye], unshadowed.mono[eye])
        #expect(shadowPixels > 10)
        // Stereo draws the same shadow, give or take edge pixels.
        let mismatched = differingCount(shadowed.stereo[eye], shadowed.mono[eye])
        #expect(mismatched < shadowPixels / 4, "eye \(eye): \(mismatched) of \(shadowPixels) shadow pixels differ")
    }
}
