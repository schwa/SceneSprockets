import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

// #495: screen-space contact shadows from the brightest directional light.
private let size = CGSize(width: 96, height: 96)

private func pose(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
    let forward = simd_normalize(eye - target)
    let right = simd_normalize(simd_cross([0, 1, 0], forward))
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(simd_cross(forward, right), 0), SIMD4(forward, 0), SIMD4(eye, 1)))
}

// A small box resting on a floor, seen from above, lit by a low sun from +x: the floor just left of the box is in its
// shadow, which only contact shadows draw here (no shadow map).
@MainActor
private func makeScene(material: any SceneMaterial) -> (SceneGraph, shadowed: SIMD2<Int>, open: SIMD2<Int>) {
    let root = SceneGraph.Node()
    let camera = root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [0, 3, 0.01], target: .zero)), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: .zero, target: [-1, -0.5, 0])), content: .light(.directional(intensity: 2))))
    root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 4, height: 0.1, length: 4), material: material, transform: .init(translation: [0, -0.05, 0])))
    root.addChild(SceneGraph.Node(label: "Box", shape: .box(width: 0.2, height: 0.2, length: 0.2), material: material, transform: .init(translation: [0, 0.1, 0])))
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.contactShadows = nil
    func pixel(_ point: SIMD3<Float>) -> SIMD2<Int> {
        let context = makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: nil, aspectRatio: 1)!
        let clip = context.projectionMatrix * context.viewMatrix * SIMD4(point, 1)
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return SIMD2(Int((ndc.x + 1) / 2 * Float(size.width)), Int((1 - ndc.y) / 2 * Float(size.height)))
    }
    return (sceneGraph, pixel([-0.15, 0, 0]), pixel([0.6, 0, 0.6]))
}

@MainActor
private func brightness(_ sceneGraph: SceneGraph, at pixel: SIMD2<Int>, renderers: [any MaterialRenderer]) throws -> Int {
    let renderer = try OffscreenRenderer(size: size, colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers)).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(pixel.x, pixel.y, 1, 1), mipmapLevel: 0)
    return Int(value.x) + Int(value.y) + Int(value.z)
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: ["Blinn-Phong", "PBR"])
@MainActor
func contactShadowsDarkenTheFloorBesideAnObject(rendererName: String) throws {
    let isPBR = rendererName == "PBR"
    let material: any SceneMaterial = isPBR ? PBRSceneMaterial(baseColor: [0.6, 0.6, 0.6], roughness: 1) : BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0.6), specular: .color(0), shininess: 1)
    let renderers: [any MaterialRenderer] = isPBR ? [PBRMaterialRenderer(environmentIntensity: 0)] : [BlinnPhongMaterialRenderer()]
    var (sceneGraph, shadowed, open) = makeScene(material: material)
    let litBeside = try brightness(sceneGraph, at: shadowed, renderers: renderers)
    let litOpen = try brightness(sceneGraph, at: open, renderers: renderers)
    #expect(litBeside > 60)

    sceneGraph.environment.contactShadows = SceneGraph.ContactShadows(length: 0.5, thickness: 0.5)
    let contactBeside = try brightness(sceneGraph, at: shadowed, renderers: renderers)
    let contactOpen = try brightness(sceneGraph, at: open, renderers: renderers)
    #expect(Double(contactBeside) < Double(litBeside) * 0.5, "beside: \(litBeside) -> \(contactBeside)")
    #expect(abs(contactOpen - litOpen) <= 6, "open: \(litOpen) -> \(contactOpen)")

    // With ambient occlusion on too, both still apply.
    sceneGraph.environment.ambientOcclusion = SceneGraph.AmbientOcclusion()
    #expect(Double(try brightness(sceneGraph, at: shadowed, renderers: renderers)) < Double(litBeside) * 0.5)
}

@Test
func contactShadowsAreArchived() throws {
    var environment = SceneGraph.Environment()
    environment.contactShadows = SceneGraph.ContactShadows(length: 1, thickness: 0.2, strength: 0.5, stepCount: 8)
    let decoded = try JSONDecoder().decode(SceneGraph.Environment.self, from: JSONEncoder().encode(environment))
    #expect(decoded.contactShadows == environment.contactShadows)
}
