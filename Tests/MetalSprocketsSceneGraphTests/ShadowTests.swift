import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphRenderer

private let size = CGSize(width: 128, height: 128)

private func pose(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> simd_float4x4 {
    let forward = simd_normalize(eye - target)
    let right = simd_normalize(simd_cross(up, forward))
    let trueUp = simd_cross(forward, right)
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(trueUp, 0), SIMD4(forward, 0), SIMD4(eye, 1)))
}

private var material: BlinnPhongMaterial {
    BlinnPhongMaterial(ambient: .color([0.5, 0.5, 0.5]), diffuse: .color([0.5, 0.5, 0.5]), specular: .color(0), shininess: 1)
}

// A floor, a box floating above it, and a directional light shining down and towards -x, so the box's shadow
// falls on the floor around x = -1 (a visible spot left of the box). Returns the scene and that spot in pixels.
@MainActor
private func makeScene(boxCastsShadow: Bool = true, skinned: Bool = false, light: LightType = .directional) throws -> (SceneGraph, SIMD2<Int>) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let camera = SceneGraph.Node(parent: root, transform: pose(eye: [0, 6, 6], target: .zero), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50)))))
    switch light {
    case .spot:
        // Above and right of the box, aimed through it at the floor near x = -0.9.
        _ = SceneGraph.Node(parent: root, transform: pose(eye: [1.5, 4, 0], target: [-0.9, 0, 0]), content: .light(.spot(color: [1, 1, 1], intensity: 20, innerConeAngle: 0.4, outerConeAngle: 0.6)))
    case .point:
        _ = SceneGraph.Node(parent: root, transform: pose(eye: [1.5, 4, 0], target: [-0.9, 0, 0]), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20)))
    default:
        _ = SceneGraph.Node(parent: root, transform: pose(eye: .zero, target: [-0.5, -1, 0]), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1)))
    }
    _ = SceneGraph.Node(parent: root, label: "Floor", trs: .init(translation: [0, -0.05, 0], scale: [6, 0.1, 6]), content: .mesh(box, material: material))
    if skinned {
        // Placed only by its joint: the mesh node sits far away, the joint at the usual spot.
        let joint = SceneGraph.Node(parent: root, label: "Joint", trs: .init(translation: [0, 1.5, 0]))
        let node = SceneGraph.Node(parent: root, label: "Box", trs: .init(translation: [50, 0, 0]), content: .mesh(box, material: material, castsShadow: boxCastsShadow))
        node.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
        node.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: .zero, weights: [1, 0, 0, 0]), count: box.vertexCount)
    } else {
        _ = SceneGraph.Node(parent: root, label: "Box", trs: .init(translation: [0, 1.5, 0]), content: .mesh(box, material: material, castsShadow: boxCastsShadow))
    }
    let sceneGraph = SceneGraph(root: root)

    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: nil, aspectRatio: 1))
    let clip = context.projectionMatrix * context.viewMatrix * SIMD4<Float>(-1, 0, 0, 1)
    let ndc = SIMD2(clip.x, clip.y) / clip.w
    let pixel = SIMD2(Int((ndc.x + 1) / 2 * Float(size.width)), Int((1 - ndc.y) / 2 * Float(size.height)))
    return (sceneGraph, pixel)
}

@MainActor
private func brightness(_ sceneGraph: SceneGraph, at pixel: SIMD2<Int>, shadows: SceneGraphShadows?) throws -> Int {
    let renderer = try OffscreenRenderer(size: size, colorUsage: ShadowContext.requiredColorUsage, depthUsage: ShadowContext.requiredDepthUsage)
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)
    let texture = try renderer.render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(pixel.x, pixel.y, 1, 1), mipmapLevel: 0)
    return Int(value.x) + Int(value.y) + Int(value.z)
}

@Test
@MainActor
func boxCastsShadowOnFloor() throws {
    let (sceneGraph, pixel) = try makeScene()
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: SceneGraphShadows(intensity: 0.8))
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

@Test
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

@Test(arguments: [LightType.spot, .point])
@MainActor
func spotAndPointLightsCastShadows(light: LightType) throws {
    let (sceneGraph, pixel) = try makeScene(light: light)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let shadowed = try brightness(sceneGraph, at: pixel, shadows: SceneGraphShadows(intensity: 0.8))
    #expect(lit > 30)
    #expect(Double(shadowed) < Double(lit) * 0.6)
}

@Test
func pointLightUsesSixViews() throws {
    let shadows = SceneGraphShadows()
    let bounds = BoundingBox(min: [-1, -1, -1], max: [1, 1, 1])
    #expect(shadows.shadowViews(lights: [(matrix_identity_float4x4, Light(type: .point))], bounds: bounds).count == 6)
    #expect(shadows.shadowViews(lights: [(matrix_identity_float4x4, Light(type: .spot))], bounds: bounds).count == 1)
    // Two point lights exceed the 8 slices; the extra views are dropped.
    #expect(shadows.shadowViews(lights: Array(repeating: (matrix_identity_float4x4, Light(type: .point)), count: 2), bounds: bounds).count == 8)
}

@Test
@MainActor
func nonCastersCastNoShadow() throws {
    let (sceneGraph, pixel) = try makeScene(boxCastsShadow: false)
    let lit = try brightness(sceneGraph, at: pixel, shadows: nil)
    let withShadows = try brightness(sceneGraph, at: pixel, shadows: SceneGraphShadows(intensity: 0.8))
    #expect(abs(withShadows - lit) <= 3)
}
