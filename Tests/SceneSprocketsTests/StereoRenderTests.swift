import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
@testable import SceneSprocketsShaderMaterial
import simd
import Testing

// #379: two views drawn at once (vertex amplification into a two-slice target) give each slice what drawing that view
// alone gives.

private let size = 32

@MainActor
private func texture(_ format: MTLPixelFormat, slices: Int, device: MTLDevice) throws -> MTLTexture {
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
    if slices > 1 {
        descriptor.textureType = .type2DArray
        descriptor.arrayLength = slices
    }
    descriptor.usage = [.renderTarget, .shaderRead]
    descriptor.storageMode = format == .depth32Float ? .private : .shared
    return try #require(device.makeTexture(descriptor: descriptor))
}

private func pixels(_ texture: MTLTexture, slice: Int) -> [SIMD4<UInt8>] {
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, bytesPerImage: size * size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, slice: slice)
    return pixels
}

/// Renders `sceneGraph` once per eye, then both eyes at once, and returns the per-eye mono pixels and stereo slices.
@MainActor
func stereoAndMonoRenders(_ sceneGraph: SceneGraph, renderers: [any MaterialRenderer], eyes: [simd_float4x4], debugMode: DebugMode? = nil) throws -> (mono: [[SIMD4<UInt8>]], stereo: [[SIMD4<UInt8>]]) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let camera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60)))
    let projection = simd_float4x4.reverseZ * camera.projection.projectionMatrix(aspectRatio: 1)
    var mono: [[SIMD4<UInt8>]] = []
    for eye in eyes {
        let color = try texture(.bgra8Unorm_srgb, slices: 1, device: device)
        let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: texture(.depth32Float, slices: 1, device: device), clearDepth: 0)
        _ = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, cameraMatrix: eye, aspectRatio: 1, renderers: renderers, defaultCamera: camera, debugMode: debugMode))
        mono.append(pixels(color, slice: 0))
    }
    let viewport = MTLViewport(originX: 0, originY: 0, width: Double(size), height: Double(size), znear: 0, zfar: 1)
    let views = StereoViews(viewMatrices: eyes.map(\.inverse), projectionMatrices: eyes.map { _ in projection }, viewports: eyes.map { _ in viewport })
    let color = try texture(.bgra8Unorm_srgb, slices: eyes.count, device: device)
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorTexture: color, depthTexture: texture(.depth32Float, slices: eyes.count, device: device), clearDepth: 0)
    renderer.renderPassDescriptor.renderTargetArrayLength = eyes.count
    _ = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers, defaultCamera: camera, debugMode: debugMode, stereoViews: views))
    return (mono, (0 ..< eyes.count).map { pixels(color, slice: $0) })
}

func largestDifference(_ lhs: [SIMD4<UInt8>], _ rhs: [SIMD4<UInt8>]) -> Int {
    zip(lhs, rhs).map { a, b in (0 ..< 4).map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0 }.max() ?? 0
}

func eyePair(at position: SIMD3<Float>, separation: Float) -> [simd_float4x4] {
    [-separation / 2, separation / 2].map { offset in
        var matrix = matrix_identity_float4x4
        matrix.columns.3 = SIMD4(position + [offset, 0, 0], 1)
        return matrix
    }
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func blinnPhongStereoMatchesMono() throws {
    let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.6), specular: .color(1), shininess: 32)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [1, 1, 2]), content: .light(Light(type: .point, intensity: 2))))
    root.addChild(SceneGraph.Node(content: .mesh(SceneGraph.Shape.box(width: 1, height: 1, length: 1).metalMesh(), material: material)))
    // Instanced copies use the instanced vertex shader.
    for index in 0 ..< 3 {
        root.addChild(SceneGraph.Node(transform: .init(translation: [Float(index) - 1, -1, -0.5]), content: .mesh(SceneGraph.Shape.sphere(radius: 0.3).metalMesh(), material: material)))
    }
    let (mono, stereo) = try stereoAndMonoRenders(SceneGraph(root: root), renderers: [BlinnPhongMaterialRenderer()], eyes: eyePair(at: [0, 0, 3], separation: 0.6))
    #expect(largestDifference(mono[0], mono[1]) > 20, "the eyes should see different images")
    for eye in 0 ..< 2 {
        #expect(largestDifference(mono[eye], stereo[eye]) <= 3, "eye \(eye): \(largestDifference(mono[eye], stereo[eye]))")
    }
}

@MainActor private var plainMaterial: BlinnPhongSceneMaterial { BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.6), specular: .color(0.5), shininess: 16) }

// A box in `material`, lit by a point light, in front of `background`.
@MainActor
private func expectStereoMatchesMono(_ material: any SceneMaterial, renderers: [any MaterialRenderer], background: SceneGraph.Environment.Background = .color([0, 0, 0, 1]), debugMode: DebugMode? = nil) throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [1, 1, 2]), content: .light(Light(type: .point, intensity: 2))))
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0])), content: .mesh(SceneGraph.Shape.box(width: 1, height: 1, length: 1).metalMesh(), material: material)))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.environment.background = background
    let (mono, stereo) = try stereoAndMonoRenders(sceneGraph, renderers: renderers, eyes: eyePair(at: [0, 0.3, 3], separation: 0.6), debugMode: debugMode)
    #expect(largestDifference(mono[0], mono[1]) > 20, "the eyes should see different images")
    for eye in 0 ..< 2 {
        #expect(largestDifference(mono[eye], stereo[eye]) <= 3, "eye \(eye): \(largestDifference(mono[eye], stereo[eye]))")
    }
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shaderMaterialStereoMatchesMono() throws {
    try expectStereoMatchesMono(ShaderMaterial.rim(color: [1, 0.5, 0]), renderers: [ShaderMaterialRenderer()])
    try expectStereoMatchesMono(ShaderMaterial.lit(color: [0.2, 0.6, 1]), renderers: [ShaderMaterialRenderer()])
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func debugViewStereoMatchesMono() throws {
    try expectStereoMatchesMono(plainMaterial, renderers: [BlinnPhongMaterialRenderer()], debugMode: .shaded)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func skyGradientStereoMatchesMono() throws {
    let gradient = SceneGraph.Environment.SkyGradient(zenith: [0, 0, 1], horizon: [0, 1, 0], ground: [1, 0, 0])
    try expectStereoMatchesMono(plainMaterial, renderers: [BlinnPhongMaterialRenderer()], background: .gradient(gradient))
}

// Billboards face the center camera in stereo, not each eye, so slices are not compared with mono renders. Each eye
// must see the cloud, shifted by parallax.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func particlesDrawInBothEyes() throws {
    let system = ParticleSystem("Glow") {
        EmitterDescription("Glow") {
            ShapeModule(shape: .sphere(radius: 0.1))
            RateModule(birthRate: 2_000)
            LifetimeModule(range: 5...5)
            VelocityModule(velocity: .zero)
            GravityModule(acceleration: .zero)
            SizeOverLifeModule(curve: .constant(0.3))
            ColorOverLifeModule(color: .constant([1, 1, 1, 1]))
            SpriteModule(blendMode: .additive)
        }
    }
    let root = SceneGraph.Node()
    let emitter = root.addChild(SceneGraph.Node())
    emitter.particleSystems = [SceneParticleSystem(system, seed: 3)]
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.environment.background = .color([0, 0, 0, 1])
    sceneGraph.advanceParticles(by: 0.1)
    let (_, stereo) = try stereoAndMonoRenders(sceneGraph, renderers: [BlinnPhongMaterialRenderer()], eyes: eyePair(at: [0, 0, 3], separation: 1))
    // The mean x of bright pixels: the left eye sees the cloud right of center, the right eye left of it.
    func meanBrightX(_ pixels: [SIMD4<UInt8>]) -> Float? {
        let xs = pixels.indices.filter { pixels[$0].x > 100 }.map { Float($0 % size) }
        return xs.isEmpty ? nil : xs.reduce(0, +) / Float(xs.count)
    }
    let left = try #require(meanBrightX(stereo[0]), "left eye sees no particles")
    let right = try #require(meanBrightX(stereo[1]), "right eye sees no particles")
    #expect(left > Float(size) / 2 + 1, "\(left)")
    #expect(right < Float(size) / 2 - 1, "\(right)")
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func pbrStereoMatchesMono() throws {
    try expectStereoMatchesMono(PBRSceneMaterial(baseColor: [0.8, 0.3, 0.1], metallic: 0, roughness: 0.4), renderers: [PBRMaterialRenderer()])
}
