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

private let size = CGSize(width: 128, height: 128)

private func pose(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> simd_float4x4 {
    let forward = simd_normalize(eye - target)
    let right = simd_normalize(simd_cross(up, forward))
    let trueUp = simd_cross(forward, right)
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(trueUp, 0), SIMD4(forward, 0), SIMD4(eye, 1)))
}

// No ambient term: Blinn-Phong shadows dim only the shadowing light's contribution (#71), so the tests measure that.
private var material: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color([0.5, 0.5, 0.5]), specular: .color(0), shininess: 1)
}

// A floor, a box floating above it, and a directional light shining down and towards -x, so the box's shadow
// falls on the floor around x = -1 (a visible spot left of the box). Returns the scene and that spot in pixels.
@MainActor
private func makeScene(boxCastsShadow: Bool = true, skinned: Bool = false, light: Light.Kind = .directional, boxMaterial: (any SceneMaterial)? = nil) throws -> (SceneGraph, SIMD2<Int>) {
    let boxMaterial = boxMaterial ?? material
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let camera = root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [0, 6, 6], target: .zero)), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    switch light {
    case .spot:
        // Above and right of the box, aimed through it at the floor near x = -0.9.
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [1.5, 4, 0], target: [-0.9, 0, 0])), content: .light(.spot(color: [1, 1, 1], intensity: 20, innerConeAngle: 0.4, outerConeAngle: 0.6))))
    case .point:
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [1.5, 4, 0], target: [-0.9, 0, 0])), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20))))
    default:
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: .zero, target: [-0.5, -1, 0])), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
    }
    root.addChild(SceneGraph.Node(label: "Floor", transform: .init(translation: [0, -0.05, 0], scale: [6, 0.1, 6]), content: .mesh(box, material: material)))
    if skinned {
        // Placed only by its joint: the mesh node sits far away, the joint at the usual spot.
        let joint = root.addChild(SceneGraph.Node(label: "Joint", transform: .init(translation: [0, 1.5, 0])))
        let node = root.addChild(SceneGraph.Node(label: "Box", transform: .init(translation: [50, 0, 0]), content: .mesh(box, material: boxMaterial, castsShadow: boxCastsShadow)))
        node.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
        node.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: .zero, weights: [1, 0, 0, 0]), count: box.vertexCount)
    } else {
        root.addChild(SceneGraph.Node(label: "Box", transform: .init(translation: [0, 1.5, 0]), content: .mesh(box, material: boxMaterial, castsShadow: boxCastsShadow)))
    }
    let sceneGraph = SceneGraph(linearRoot: root)

    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: nil, aspectRatio: 1))
    let clip = context.projectionMatrix * context.viewMatrix * SIMD4<Float>(-1, 0, 0, 1)
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    let pixel = SIMD2(Int((ndc.x + 1) / 2 * Float(size.width)), Int((1 - ndc.y) / 2 * Float(size.height)))
    return (sceneGraph, pixel)
}

@MainActor
private func brightness(_ sceneGraph: SceneGraph, at pixel: SIMD2<Int>, shadows: Shadows?, renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer()], sampleCount: Int = 1) throws -> Int {
    let renderer = try OffscreenRenderer(size: size, colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers, shadows: shadows, sampleCount: sampleCount)
    let texture = try renderer.render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(pixel.x, pixel.y, 1, 1), mipmapLevel: 0)
    return Int(value.x) + Int(value.y) + Int(value.z)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func boxCastsShadowOnFloor() throws {
    let (sceneGraph, pixel) = try makeScene()
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8))
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

// #95: with MSAA the scene pass resolves depth, so in-shader shadows and the screen-space mask (which reads depth)
// still work.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [false, true])
@MainActor
func boxCastsShadowWithMultisampling(usesMask: Bool) throws {
    let (sceneGraph, pixel) = try makeScene()
    let renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(), ShaderMaterialRenderer()]
    if usesMask {
        // A floor that does not sample shadows itself, so the screen-space mask pass must darken it.
        let floor = try #require(sceneGraph.nodesWithWorldTransforms().first { $0.node.label == "Floor" }?.node)
        if case let .mesh(mesh, _, castsShadow, receivesShadow) = floor.content {
            floor.content = .mesh(mesh, materials: [ShaderMaterial.rim(color: [0.5, 0.5, 0.5])], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil, renderers: renderers, sampleCount: 4)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8), renderers: renderers, sampleCount: 4)
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func skinnedCasterIsSkinnedOnGPU() throws {
    let (sceneGraph, pixel) = try makeScene(skinned: true)
    let shadows = Shadows(intensity: 0.8)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: shadows)
    #expect(Double(shadowed) < Double(lit) * 0.6)
    // The caster is skinned on the GPU, not CPU-deformed.
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let frame = try #require(try shadows.prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds))
    #expect(frame.casters.contains { if case .skinned = $0.placement { true } else { false } })
}

// #478: an app changes shadow settings on the main thread while SceneView's render thread prepares the frame. The
// race is on plain values, so it only shows with the thread sanitizer (--sanitize=thread).
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func settingsCanChangeWhileAFrameIsPrepared() async throws {
    let (sceneGraph, _) = try makeScene()
    let shadows = Shadows(intensity: 0.8)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    nonisolated(unsafe) let entries = sceneGraph.meshEntries()
    nonisolated(unsafe) let unsafeContext = context
    nonisolated(unsafe) let unsafeShadows = shadows
    let bounds = sceneGraph.bounds
    let rendering = Task.detached {
        for _ in 0..<200 {
            _ = try? unsafeShadows.prepare(entries: entries, context: unsafeContext, bounds: bounds)
        }
    }
    for index in 0..<200 {
        shadows.intensity = Float(index % 10) / 10
        shadows.softness = index % 3
        shadows.color = SIMD3(repeating: Float(index % 2))
        shadows.depthBias = Float(index % 4)
        _ = shadows.droppedLightCount
    }
    await rendering.value
    #expect(shadows.softness == 199 % 3)
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: [Light.Kind.spot, .point])
@MainActor
func spotAndPointLightsCastShadows(light: Light.Kind) throws {
    let (sceneGraph, pixel) = try makeScene(light: light)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8))
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

@Test
func pointLightUsesSixViews() {
    let shadows = Shadows()
    let bounds = BoundingBox3D(min: [-1, -1, -1], max: [1, 1, 1])
    #expect(shadows.shadowViews(lights: [(matrix_identity_float4x4, Light(type: .point))], bounds: bounds).count == 6)
    #expect(shadows.shadowViews(lights: [(matrix_identity_float4x4, Light(type: .spot))], bounds: bounds).count == 1)
    // Two point lights exceed the 8 slices: the second is dropped whole, and a later spot light still fits.
    let lights = Array(repeating: (matrix_identity_float4x4, Light(type: .point)), count: 2) + [(matrix_identity_float4x4, Light(type: .spot))]
    let result = shadows.shadowViewsAndDroppedLights(lights: lights, bounds: bounds)
    #expect(result.views.count == 7)
    #expect(result.dropped == 1)
}

// #299: the slice limit and which lights win when they do not fit are settings.
@Test
func sliceLimitAndLightPriorityAreConfigurable() {
    let bounds = BoundingBox3D(min: [-1, -1, -1], max: [1, 1, 1])
    let dim = (matrix_identity_float4x4, Light(type: .point, intensity: 1))
    let bright = (matrix_identity_float4x4, Light(type: .point, intensity: 10))
    let shadows = Shadows(maximumSliceCount: 12)
    let roomy = shadows.shadowViewsAndDroppedLights(lights: [dim, bright], bounds: bounds)
    #expect(roomy.views.count == 12)
    #expect(roomy.dropped == 0)

    shadows.maximumSliceCount = 8
    shadows.lightPriority = .brightest
    let brightest = shadows.shadowViewsAndDroppedLights(lights: [dim, bright], bounds: bounds)
    #expect(brightest.dropped == 1)
    #expect(brightest.slices == [0..<0, 0..<6])

    // Camera-relative positions: the camera is at the origin.
    let far = (simd_float4x4(translation: [0, 0, 50]), Light(type: .point))
    let near = (simd_float4x4(translation: [0, 0, 2]), Light(type: .point))
    shadows.lightPriority = .nearestToCamera
    #expect(shadows.shadowViewsAndDroppedLights(lights: [far, near], bounds: bounds).slices == [0..<0, 0..<6])
    shadows.lightPriority = .sceneOrder
    #expect(shadows.shadowViewsAndDroppedLights(lights: [far, near], bounds: bounds).slices == [0..<6, 0..<0])

    // Above the shaders' fixed array size, the limit is clamped.
    shadows.maximumSliceCount = 1_000
    #expect(shadows.maximumSliceCount == Shadows.sliceCountLimit)
}

// #299: lights beyond 8 slices cast shadows when the limit is raised.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func raisedSliceLimitShadowsEveryLight() throws {
    let (sceneGraph, pixel) = try makeScene(light: .point)
    // A first point light that fills six slices but lights nothing near the measured spot.
    sceneGraph.root.insertChild(SceneGraph.Node(transform: .init(translation: [0, 40, 0]), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 0.001))), at: 0)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let limited = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8))
    let raised = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8, maximumSliceCount: 12))
    #expect(abs(limited - lit) <= 3)
    #expect(Double(raised) < Double(lit) * 0.6)
}

@Test
@MainActor
func droppedLightsAreCounted() throws {
    let (sceneGraph, _) = try makeScene(light: .point)
    sceneGraph.root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [-1.5, 4, 0], target: .zero)), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20))))
    let shadows = Shadows()
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    _ = try shadows.prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds)
    #expect(shadows.droppedLightCount == 1)
}

// #66: a floor that does not receive shadows stays lit under the box's shadow. With only Blinn-Phong meshes the
// screen-space mask is not needed at all (#71).
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func nonReceiversAreNotDarkened() throws {
    let (sceneGraph, pixel) = try makeScene()
    let floor = try #require(sceneGraph.nodesWithWorldTransforms().first { $0.node.label == "Floor" }?.node)
    if case let .mesh(mesh, materials, castsShadow, _) = floor.content {
        floor.content = .mesh(mesh, materials: materials, castsShadow: castsShadow, receivesShadow: false)
    }
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadows = Shadows(intensity: 0.8)
    let withShadows = try brightness(sceneGraph, at: pixel, shadows: shadows)
    #expect(abs(withShadows - lit) <= 3)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let frame = try #require(try shadows.prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds, viewSize: (128, 128)))
    #expect(frame.masksEverything)
    #expect(frame.nonReceivers == nil)
}

// The screen-space mask still covers other materials, skipping Blinn-Phong meshes (which shadow themselves).
@Test
@MainActor
func screenSpaceMaskSkipsBlinnPhong() throws {
    let (sceneGraph, _) = try makeScene()
    let floor = try #require(sceneGraph.nodesWithWorldTransforms().first { $0.node.label == "Floor" }?.node)
    if case let .mesh(mesh, _, castsShadow, receivesShadow) = floor.content {
        floor.content = .mesh(mesh, materials: [ShaderMaterial.normals()], castsShadow: castsShadow, receivesShadow: receivesShadow)
    }
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let frame = try #require(try Shadows().prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds, viewSize: (128, 128)))
    #expect(!frame.masksEverything)
    // Only the Blinn-Phong box is marked.
    #expect(frame.nonReceivers?.casters.count == 1)
}

// #71: a light's shadow dims only that light. The floor spot is in the sun's box shadow but lit by a second light
// from the other side, which must still reach it; and a light whose category excludes the floor casts nothing on it.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shadowsDimOnlyTheirOwnLight() throws {
    let (sceneGraph, pixel) = try makeScene()
    let shadows = Shadows(intensity: 1)
    let sunOnly = try brightness(sceneGraph, at: pixel, shadows: shadows)
    #expect(sunOnly < 10)
    // From the right, low: lights the floor spot and its box shadow falls left of it.
    let fill = sceneGraph.root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [6, 3, 0], target: [-1, 0, 0])), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
    let withFill = try brightness(sceneGraph, at: pixel, shadows: shadows)
    let fillWithoutShadows = try brightness(sceneGraph, at: pixel, shadows: nil)
    _ = fill
    #expect(withFill > 30)
    // The fill's contribution is not dimmed by the sun's shadow (with the old screen-space mask it went to black).
    #expect(Double(withFill) > Double(fillWithoutShadows) * 0.3)

    // A light that lights only category 2 casts no shadow on the category-1 floor.
    let (masked, maskedPixel) = try makeScene()
    let sun = try #require(masked.lightNodes().first?.node)
    let other = masked.root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: .zero, target: [-0.5, -1, 0])), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
    other.lightCategoryBitMask = 0b10
    sun.removeFromParent()
    // The floor glows (ambient) and no light reaches it; the category-2 light's box shadow would land on the spot,
    // which the old screen-space mask darkened.
    let floor = try #require(masked.nodesWithWorldTransforms().first { $0.node.label == "Floor" }?.node)
    if case let .mesh(mesh, _, castsShadow, receivesShadow) = floor.content {
        floor.content = .mesh(mesh, materials: [BlinnPhongSceneMaterial(ambient: .color(1), diffuse: .color(0.5), specular: .color(0), shininess: 1)], castsShadow: castsShadow, receivesShadow: receivesShadow)
    }
    let glowing = try brightness(masked, at: maskedPixel, shadows: nil)
    #expect(glowing > 30)
    #expect(abs(try brightness(masked, at: maskedPixel, shadows: Shadows(intensity: 1)) - glowing) <= 3)
}

// #102: PBR samples each light's shadow in its shader, so the sun's shadow does not dim the fill light.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func pbrShadowsDimOnlyTheirOwnLight() throws {
    let (sceneGraph, pixel) = try makeScene()
    let gray = PBRSceneMaterial(baseColor: [0.5, 0.5, 0.5], roughness: 1)
    for (node, _) in sceneGraph.nodesWithWorldTransforms() {
        if case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content {
            node.content = .mesh(mesh, materials: [gray], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }
    let renderers: [any MaterialRenderer] = [PBRMaterialRenderer(environmentIntensity: 0)]
    let shadows = Shadows(intensity: 1)
    #expect(try brightness(sceneGraph, at: pixel, shadows: shadows, renderers: renderers) < 10)
    sceneGraph.root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [6, 3, 0], target: [-1, 0, 0])), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
    let withFill = try brightness(sceneGraph, at: pixel, shadows: shadows, renderers: renderers)
    let fillWithoutShadows = try brightness(sceneGraph, at: pixel, shadows: nil, renderers: renderers)
    #expect(withFill > 30)
    #expect(Double(withFill) > Double(fillWithoutShadows) * 0.3)
    #expect((PBRSceneMaterial.self as Any) is any SamplesShadowsInShader.Type)
}

// #300: a ShaderMaterial with `samplesShadows` shades each light with its own shadow, so the sun's shadow does not dim
// the fill light (the screen-space mask darkened it by every light's shadow).
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shaderMaterialShadowsDimOnlyTheirOwnLight() throws {
    let (sceneGraph, pixel) = try makeScene()
    let gray = ShaderMaterial.lit(color: [0.5, 0.5, 0.5])
    for (node, _) in sceneGraph.nodesWithWorldTransforms() {
        if case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content {
            node.content = .mesh(mesh, materials: [gray], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }
    let renderers: [any MaterialRenderer] = [ShaderMaterialRenderer()]
    let shadows = Shadows(intensity: 1)
    let sunWithoutShadows = try brightness(sceneGraph, at: pixel, shadows: nil, renderers: renderers)
    #expect(sunWithoutShadows > 30)
    #expect(try brightness(sceneGraph, at: pixel, shadows: shadows, renderers: renderers) < 10)
    sceneGraph.root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [6, 3, 0], target: [-1, 0, 0])), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
    let withFill = try brightness(sceneGraph, at: pixel, shadows: shadows, renderers: renderers)
    let fillWithoutShadows = try brightness(sceneGraph, at: pixel, shadows: nil, renderers: renderers) - sunWithoutShadows
    #expect(withFill > 30)
    #expect(Double(withFill) > Double(fillWithoutShadows) * 0.3)
}

@MainActor
private func pixels(_ sceneGraph: SceneGraph, shadows: Shadows?) throws -> [SIMD4<UInt8>] {
    let renderer = try OffscreenRenderer(size: size, colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)).texture
    var result = [SIMD4<UInt8>](repeating: .zero, count: texture.width * texture.height)
    texture.getBytes(&result, bytesPerRow: texture.width * 4, from: MTLRegionMake2D(0, 0, texture.width, texture.height), mipmapLevel: 0)
    return result
}

// #88: shadows tint towards `color`, and `softness` widens the penumbra.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shadowColorTintsShadowedPixels() throws {
    let (sceneGraph, pixel) = try makeScene()
    let index = pixel.y * Int(size.width) + pixel.x
    let lit = try pixels(sceneGraph, shadows: nil)[index]
    let tinted = try pixels(sceneGraph, shadows: Shadows(intensity: 1, color: [1, 0, 0]))[index]
    // BGRA: red kept, blue gone.
    #expect(abs(Int(tinted.z) - Int(lit.z)) <= 3)
    #expect(tinted.x < 5)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func softnessWidensPenumbra() throws {
    let (sceneGraph, _) = try makeScene()
    let lit = try pixels(sceneGraph, shadows: nil)
    func penumbraCount(softness: Int) throws -> Int {
        let shadowed = try pixels(sceneGraph, shadows: Shadows(intensity: 1, softness: softness, resolution: 256))
        // Partly darkened: between 10% and 90% of the lit brightness.
        return zip(lit, shadowed).filter { lit, shadowed in
            let ratio = (Float(shadowed.x) + Float(shadowed.y) + Float(shadowed.z) + 1) / (Float(lit.x) + Float(lit.y) + Float(lit.z) + 1)
            return ratio > 0.1 && ratio < 0.9
        }.count
    }
    #expect(try penumbraCount(softness: 4) > penumbraCount(softness: 0) + 10)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func nonCastersCastNoShadow() throws {
    let (sceneGraph, pixel) = try makeScene(boxCastsShadow: false)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let withShadows = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8))
    #expect(abs(withShadows - lit) <= 3)
}

private func alphaTexture(_ alpha: UInt8) throws -> MTLTexture {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [128, 128, 128, alpha], bytesPerRow: 4)
    return texture
}

// #541: casters with see-through materials cast shadows only where their alpha reaches the cutoff.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [
    ("Blinn-Phong opacity 0.1", false),
    ("Blinn-Phong texture alpha 0", false),
    ("Blinn-Phong texture alpha 1", true),
    ("Blinn-Phong skinned texture alpha 0", false),
    ("PBR mask texture alpha 0", false),
    ("PBR mask texture alpha 1", true),
    ("PBR blend opacity 0.1", false),
    ("Node opacity 0.1", false)
])
@MainActor
func seeThroughCastersFollowAlpha(name: String, castsShadow: Bool) throws {
    let boxMaterial: any SceneMaterial
    var skinned = false
    var nodeOpacity: Float = 1
    switch name {
    case "Blinn-Phong opacity 0.1":
        boxMaterial = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0.5), specular: .color(0), shininess: 1, opacity: 0.1)
    case "Blinn-Phong texture alpha 0", "Blinn-Phong skinned texture alpha 0":
        boxMaterial = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .texture(try alphaTexture(0)), specular: .color(0), shininess: 1, usesDiffuseTextureAlpha: true)
        skinned = name.contains("skinned")
    case "Blinn-Phong texture alpha 1":
        boxMaterial = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .texture(try alphaTexture(255)), specular: .color(0), shininess: 1, usesDiffuseTextureAlpha: true)
    case "PBR mask texture alpha 0", "PBR mask texture alpha 1":
        let pbr = try PBRSceneMaterial(textures: .init(baseColor: try alphaTexture(name.hasSuffix("1") ? 255 : 0)))
        var uniforms = pbr.pbrMaterial.uniforms
        uniforms.alphaMode = .mask
        uniforms.alphaCutoff = 0.5
        boxMaterial = PBRSceneMaterial(pbr.pbrMaterial.with(uniforms: uniforms))
    case "PBR blend opacity 0.1":
        boxMaterial = PBRSceneMaterial(opacity: 0.1)
    default:
        boxMaterial = material
        nodeOpacity = 0.1
    }
    let (sceneGraph, pixel) = try makeScene(skinned: skinned, boxMaterial: boxMaterial)
    if nodeOpacity < 1 {
        try #require(sceneGraph.nodesWithWorldTransforms().first { $0.node.label == "Box" }?.node).opacity = nodeOpacity
    }
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil, renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()])
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8), renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()])
    #expect(lit > 30)
    if castsShadow {
        #expect(Double(shadowed) < Double(lit) * 0.6)
    } else {
        #expect(abs(shadowed - lit) <= 3)
    }
}

// #60: casters are pushed away from a directional light by `depthOffsetTexels` shadow map texels in world space.
@Test
func directionalCasterDepthOffsetIsWorldSpace() throws {
    let shadows = Shadows(resolution: 1_024, depthOffsetTexels: 2)
    let bounds = BoundingBox3D(min: [-3, -3, -3], max: [3, 3, 3])
    let light = (pose(eye: [0, 10, 0], target: .zero), Light(type: .directional))
    let view = try #require(shadows.shadowViews(lights: [light], bounds: bounds).first)
    let biased = shadows.casterViewProjection(view)
    let texel = 2 / simd_length(SIMD3(view[0][0], view[1][0], view[2][0])) / 1_024
    let point = SIMD4<Float>(0.5, 0.2, -0.3, 1)
    let biasedDepth = (biased * point).z / (biased * point).w
    // Unbiased depth of the same point moved 2 texels further from the light (light points down -y).
    let moved = view * (point + SIMD4(0, -2 * texel, 0, 0))
    #expect(abs(biasedDepth - moved.z / moved.w) < 1e-6)
    #expect(biasedDepth < (view * point).z) // Reversed depth: further is smaller.
}

// #366: a lit floor that casts shadows must not shadow itself (acne) when the PCF kernel is wider than one texel.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [Light.Kind.spot, .point, .directional], [1, 2, 4])
@MainActor
func wideSoftShadowsDoNotSelfShadowFloor(light: Light.Kind, softness: Int) throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [3, 7, 3], target: .zero)), content: .light(Light(type: light, intensity: light == .directional ? 1 : 80, range: 30, outerConeAngle: .pi / 4))))
    root.addChild(SceneGraph.Node(shape: .floor(width: 8, length: 8), material: material, transform: .init(translation: [0, -1, 0])))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [0, 3, 8], target: [0, 0.5, 0])), content: .camera(Camera.default)))
    let sceneGraph = SceneGraph(linearRoot: root)

    let side = 256
    func render(_ shadows: Shadows?) throws -> [SIMD4<UInt8>] {
        let renderer = try OffscreenRenderer(size: CGSize(width: side, height: side), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
        let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)).texture
        var pixels = [SIMD4<UInt8>](repeating: .zero, count: side * side)
        texture.getBytes(&pixels, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        return pixels
    }
    let lit = try render(nil)
    let shadowed = try render(Shadows(intensity: 0.7, softness: softness))
    let floorPixels = lit.indices.filter { lit[$0].x > 0 || lit[$0].y > 0 || lit[$0].z > 0 }
    let darkened = floorPixels.filter { Int(lit[$0].x) - Int(shadowed[$0].x) > 4 }
    #expect(floorPixels.count > 1_000)
    #expect(darkened.count < floorPixels.count / 200, "\(darkened.count) of \(floorPixels.count) floor pixels self-shadowed")
}

// A material its renderer never draws in the scene pass, only into the shadow map, as a ShadowCasterRenderer.
private struct InvisibleCasterMaterial: SceneMaterial {}

private struct InvisibleCasterRenderer: ShadowCasterRenderer {
    var materialType: any SceneMaterial.Type { InvisibleCasterMaterial.self }

    // swiftlint:disable:next unneeded_throws_rethrows - the protocol requirement throws
    func makeElement(entries _: [SceneGraph.MeshEntry], context _: RenderContext) throws -> AnyElement {
        EmptyElement().eraseToAnyElement()
    }

    func makeShadowCasterElement(entries: [SceneGraph.MeshEntry], context: ShadowCasterContext) throws -> AnyElement {
        let shaders = try ShadowCasterShaders.shared()
        let casters = try entries.map { entry in
            let positions = entry.mesh.positions().map(SceneSprockets.Packed3.init)
            let buffer = try #require(entry.mesh.vertexBuffer.device.makeBuffer(bytes: positions, length: positions.count * MemoryLayout<SceneSprockets.Packed3>.stride))
            var model = entry.worldTransform
            model.columns.3 -= SIMD4(context.renderOrigin, 0)
            return Shadows.Caster(positions: buffer, submesh: entry.mesh.submeshes[entry.submeshIndex], placement: .model(model))
        }
        return try casterPipeline("Invisible Casters", vertexShader: shaders.staticVertex, fragmentShader: shaders.fragment, vertexDescriptor: shaders.staticDescriptor, casters: casters, viewProjection: context.viewProjection, colorPixelFormat: .invalid)
            .eraseToAnyElement()
    }
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shadowCasterRendererDrawsItsOwnCasters() throws {
    let (sceneGraph, pixel) = try makeScene()
    let box = try #require(sceneGraph.root.children.first { $0.label == "Box" })
    guard case let .mesh(mesh, _, _, _) = box.content else {
        Issue.record("The box has no mesh")
        return
    }
    box.content = .mesh(mesh, materials: [InvisibleCasterMaterial()], castsShadow: true)
    let renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(), InvisibleCasterRenderer()]
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil, renderers: renderers)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: Shadows(intensity: 0.8), renderers: renderers)
    #expect(Double(shadowed) < Double(lit) * 0.6)

    // The box is not also drawn as an ordinary mesh caster.
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let frame = try #require(try Shadows().prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds, renderers: renderers))
    #expect(frame.customCasters.map(\.entries.count) == [1])
    #expect(frame.casters.count == 1)
}
