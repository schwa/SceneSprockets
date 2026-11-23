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

// #531: planar reflections on PBR surfaces.
private let size = CGSize(width: 96, height: 96)

private func pose(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
    let forward = simd_normalize(eye - target)
    let right = simd_normalize(simd_cross([0, 1, 0], forward))
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(simd_cross(forward, right), 0), SIMD4(forward, 0), SIMD4(eye, 1)))
}

// A mirror-smooth metal floor (a plane facing +Y) under a glowing red box, with no environment light: the floor is
// black except where it reflects something.
@MainActor
private func makeScene() -> (SceneGraph, floor: SceneGraph.Node, reflected: SIMD2<Int>, box: SIMD2<Int>) {
    let root = SceneGraph.Node()
    let camera = root.addChild(SceneGraph.Node(transform: Transform3D(storing: pose(eye: [0, 2, 5], target: [0, 0, 0])), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    let mirror = PBRSceneMaterial(baseColor: [1, 1, 1], metallic: 1, roughness: 0)
    let floor = root.addChild(SceneGraph.Node(label: "Floor", shape: .plane(width: 10, height: 10), material: mirror, transform: .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))))
    let glow = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 0, 0]))
    root.addChild(SceneGraph.Node(label: "Box", shape: .box(width: 1, height: 1, length: 1), material: glow, transform: .init(translation: [0, 1, 0])))
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.intensity = 0
    func pixel(_ point: SIMD3<Float>) -> SIMD2<Int> {
        let context = makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: nil, aspectRatio: 1)!
        let clip = context.projectionMatrix * context.viewMatrix * SIMD4(point, 1)
        let ndc = SIMD2(clip.x, clip.y) / clip.w
        return SIMD2(Int((ndc.x + 1) / 2 * Float(size.width)), Int((1 - ndc.y) / 2 * Float(size.height)))
    }
    // The box's mirror image is at y = -1; the floor shows it where that image projects.
    return (sceneGraph, floor, pixel([0, -1, 0]), pixel([0, 1, 0]))
}

@MainActor
private func color(_ sceneGraph: SceneGraph, at pixel: SIMD2<Int>) throws -> SIMD4<UInt8> {
    let renderer = try OffscreenRenderer(size: size)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer(), BlinnPhongMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(pixel.x, pixel.y, 1, 1), mipmapLevel: 0)
    let isBGRA = texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb
    return isBGRA ? SIMD4(value.z, value.y, value.x, value.w) : value
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func planarReflectorShowsTheSceneMirrored() throws {
    let (sceneGraph, floor, reflected, box) = makeScene()
    let before = try color(sceneGraph, at: reflected)
    #expect(before.x < 40, "no reflector: \(before)")
    floor.planarReflector = SceneGraph.PlanarReflector(resolutionScale: 1)
    let after = try color(sceneGraph, at: reflected)
    #expect(after.x > 120 && after.y < 60, "reflector: \(after)")
    // The box itself still draws.
    #expect(try color(sceneGraph, at: box).x > 120)
}

@Test
func mirrorReflectsAboutThePlane() {
    let mirror = PlanarReflection.mirror(point: [0, 1, 0], normal: [0, 1, 0])
    let point = SIMD4<Float>(1, 3, 3, 1)
    #expect(simd_distance((mirror * point).xyz, [1, -1, 3]) < 1e-5)
    #expect(simd_distance((mirror * mirror * point).xyz, point.xyz) < 1e-5)
}

@Test
@MainActor
func planarReflectorIsArchived() throws {
    let node = SceneGraph.Node()
    node.planarReflector = SceneGraph.PlanarReflector(resolutionScale: 0.25)
    let sceneGraph = SceneGraph(linearRoot: SceneGraph.Node(children: [node]))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = Archive(materialTypes: [])
    try archive.write(sceneGraph, to: url)
    let (decoded, _) = try archive.read(from: url)
    #expect(decoded.root.children.first?.planarReflector == SceneGraph.PlanarReflector(resolutionScale: 0.25))
}
