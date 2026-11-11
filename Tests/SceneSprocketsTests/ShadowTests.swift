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
private func makeScene(boxCastsShadow: Bool = true, skinned: Bool = false, light: Light.LightType = .directional) throws -> (SceneGraph, SIMD2<Int>) {
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
        let node = root.addChild(SceneGraph.Node(label: "Box", transform: .init(translation: [50, 0, 0]), content: .mesh(box, material: material, castsShadow: boxCastsShadow)))
        node.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
        node.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: .zero, weights: [1, 0, 0, 0]), count: box.vertexCount)
    } else {
        root.addChild(SceneGraph.Node(label: "Box", transform: .init(translation: [0, 1.5, 0]), content: .mesh(box, material: material, castsShadow: boxCastsShadow)))
    }
    let sceneGraph = SceneGraph(root: root)

    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: nil, aspectRatio: 1))
    let clip = context.projectionMatrix * context.viewMatrix * SIMD4<Float>(-1, 0, 0, 1)
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    let pixel = SIMD2(Int((ndc.x + 1) / 2 * Float(size.width)), Int((1 - ndc.y) / 2 * Float(size.height)))
    return (sceneGraph, pixel)
}

@MainActor
private func brightness(_ sceneGraph: SceneGraph, at pixel: SIMD2<Int>, shadows: SceneGraphShadows?, renderers: [any SceneGraphMaterialRenderer] = [BlinnPhongMaterialRenderer()]) throws -> Int {
    let renderer = try OffscreenRenderer(size: size, colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers, shadows: shadows)
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
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: SceneGraphShadows(intensity: 0.8))
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func skinnedCasterIsSkinnedOnGPU() throws {
    let (sceneGraph, pixel) = try makeScene(skinned: true)
    let shadows = SceneGraphShadows(intensity: 0.8)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: shadows)
    #expect(Double(shadowed) < Double(lit) * 0.6)
    // The caster is skinned on the GPU, not CPU-deformed.
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let frame = try #require(try shadows.prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds))
    #expect(frame.casters.contains { if case .skinned = $0.placement { true } else { false } })
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: [Light.LightType.spot, .point])
@MainActor
func spotAndPointLightsCastShadows(light: Light.LightType) throws {
    let (sceneGraph, pixel) = try makeScene(light: light)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: SceneGraphShadows(intensity: 0.8))
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

@Test
func pointLightUsesSixViews() {
    let shadows = SceneGraphShadows()
    let bounds = BoundingBox3D(min: [-1, -1, -1], max: [1, 1, 1])
    #expect(shadows.shadowViews(lights: [(matrix_identity_float4x4, Light(type: .point))], bounds: bounds).count == 6)
    #expect(shadows.shadowViews(lights: [(matrix_identity_float4x4, Light(type: .spot))], bounds: bounds).count == 1)
    // Two point lights exceed the 8 slices: the second is dropped whole, and a later spot light still fits.
    let lights = Array(repeating: (matrix_identity_float4x4, Light(type: .point)), count: 2) + [(matrix_identity_float4x4, Light(type: .spot))]
    let result = shadows.shadowViewsAndDroppedLights(lights: lights, bounds: bounds)
    #expect(result.views.count == 7)
    #expect(result.dropped == 1)
}

@Test
@MainActor
func droppedLightsAreCounted() throws {
    let (sceneGraph, _) = try makeScene(light: .point)
    sceneGraph.root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [-1.5, 4, 0], target: .zero)), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20))))
    let shadows = SceneGraphShadows()
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
    let shadows = SceneGraphShadows(intensity: 0.8)
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
        floor.content = .mesh(mesh, materials: [try ShaderMaterial.normals()], castsShadow: castsShadow, receivesShadow: receivesShadow)
    }
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let frame = try #require(try SceneGraphShadows().prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds, viewSize: (128, 128)))
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
    let shadows = SceneGraphShadows(intensity: 1)
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
    #expect(abs(try brightness(masked, at: maskedPixel, shadows: SceneGraphShadows(intensity: 1)) - glowing) <= 3)
}

// #102: PBR samples each light's shadow in its shader, so the sun's shadow does not dim the fill light.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func pbrShadowsDimOnlyTheirOwnLight() throws {
    let (sceneGraph, pixel) = try makeScene()
    let gray = try PBRSceneMaterial(baseColor: [0.5, 0.5, 0.5, 1], roughness: 1)
    for (node, _) in sceneGraph.nodesWithWorldTransforms() {
        if case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content {
            node.content = .mesh(mesh, materials: [gray], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }
    let renderers: [any SceneGraphMaterialRenderer] = [PBRMaterialRenderer(environmentIntensity: 0)]
    let shadows = SceneGraphShadows(intensity: 1)
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
    let gray = try ShaderMaterial.lit(color: [0.5, 0.5, 0.5, 1])
    for (node, _) in sceneGraph.nodesWithWorldTransforms() {
        if case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content {
            node.content = .mesh(mesh, materials: [gray], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }
    let renderers: [any SceneGraphMaterialRenderer] = [ShaderMaterialRenderer()]
    let shadows = SceneGraphShadows(intensity: 1)
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
private func pixels(_ sceneGraph: SceneGraph, shadows: SceneGraphShadows?) throws -> [SIMD4<UInt8>] {
    let renderer = try OffscreenRenderer(size: size, colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
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
    let tinted = try pixels(sceneGraph, shadows: SceneGraphShadows(intensity: 1, color: [1, 0, 0]))[index]
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
        let shadowed = try pixels(sceneGraph, shadows: SceneGraphShadows(intensity: 1, softness: softness, resolution: 256))
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
    let withShadows = try brightness(sceneGraph, at: pixel, shadows: SceneGraphShadows(intensity: 0.8))
    #expect(abs(withShadows - lit) <= 3)
}

// #60: casters are pushed away from a directional light by `depthOffsetTexels` shadow map texels in world space.
@Test
func directionalCasterDepthOffsetIsWorldSpace() throws {
    let shadows = SceneGraphShadows(resolution: 1_024, depthOffsetTexels: 2)
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
@Test(.enabled(if: deviceSupportsMetal4), arguments: [Light.LightType.spot, .point, .directional], [1, 2, 4])
@MainActor
func wideSoftShadowsDoNotSelfShadowFloor(light: Light.LightType, softness: Int) throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [3, 7, 3], target: .zero)), content: .light(Light(type: light, intensity: light == .directional ? 1 : 80, range: 30, outerConeAngle: .pi / 4))))
    root.addChild(SceneGraph.Node(shape: .floor(width: 8, length: 8), material: material, transform: .init(translation: [0, -1, 0])))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [0, 3, 8], target: [0, 0.5, 0])), content: .camera(SceneView.defaultCamera)))
    let sceneGraph = SceneGraph(root: root)

    let side = 256
    func render(_ shadows: SceneGraphShadows?) throws -> [SIMD4<UInt8>] {
        let renderer = try OffscreenRenderer(size: CGSize(width: side, height: side), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)).texture
        var pixels = [SIMD4<UInt8>](repeating: .zero, count: side * side)
        texture.getBytes(&pixels, bytesPerRow: side * 4, from: MTLRegionMake2D(0, 0, side, side), mipmapLevel: 0)
        return pixels
    }
    let lit = try render(nil)
    let shadowed = try render(SceneGraphShadows(intensity: 0.7, softness: softness))
    let floorPixels = lit.indices.filter { lit[$0].x > 0 || lit[$0].y > 0 || lit[$0].z > 0 }
    let darkened = floorPixels.filter { Int(lit[$0].x) - Int(shadowed[$0].x) > 4 }
    #expect(floorPixels.count > 1_000)
    #expect(darkened.count < floorPixels.count / 200, "\(darkened.count) of \(floorPixels.count) floor pixels self-shadowed")
}
