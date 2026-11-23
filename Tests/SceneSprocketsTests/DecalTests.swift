import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import Testing

// #397: projected decals.
private let size = CGSize(width: 64, height: 64)

@MainActor
private func render(_ sceneGraph: SceneGraph, renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(), DecalRenderer()]) throws -> MTLTexture {
    let renderer = try OffscreenRenderer(size: size, colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    return try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers)).texture
}

private func pixel(_ texture: MTLTexture, _ x: Int, _ y: Int) -> SIMD4<UInt8> {
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
    let isBGRA = texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb
    return isBGRA ? SIMD4(value.z, value.y, value.x, value.w) : value
}

// The floor's gray: red is not much above green.
private func isGray(_ color: SIMD4<UInt8>) -> Bool {
    Int(color.x) - Int(color.y) < 30
}

// A gray floor seen from above, with a red decal box over its middle facing up (the box's -Z points down).
@MainActor
private func makeScene(cameraHeight: Float = 5, decalRotation: simd_quatf = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])) -> (SceneGraph, decal: SceneGraph.Node) {
    let root = SceneGraph.Node()
    let lookDown = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, cameraHeight, 0], rotation: lookDown), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60))))))
    let gray = BlinnPhongSceneMaterial(ambient: .color(0.5), diffuse: .color(0), specular: .color(0), shininess: 1)
    root.addChild(SceneGraph.Node(label: "Floor", shape: .plane(width: 20, height: 20), material: gray)).transform = .init(rotation: lookDown)
    let decal = root.addChild(SceneGraph.Node(label: "Decal", shape: .box(), material: DecalMaterial(color: [1, 0, 0, 1]), transform: .init(rotation: decalRotation, scale: [2, 2, 1])))
    return (SceneGraph(linearRoot: root), decal)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func decalColorsTheSurfaceInsideItsBox() throws {
    let (sceneGraph, _) = makeScene()
    let texture = try render(sceneGraph)
    let center = pixel(texture, 32, 32)
    let corner = pixel(texture, 2, 2)
    #expect(center.x > 200 && center.y < 60, "center \(center)")
    #expect(isGray(corner), "corner \(corner)")
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func decalDrawsWithTheCameraInsideItsBox() throws {
    let (sceneGraph, decal) = makeScene(cameraHeight: 0.4)
    decal.transform = .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]), scale: [2, 2, 2])
    let center = pixel(try render(sceneGraph), 32, 32)
    #expect(center.x > 200 && center.y < 60, "center \(center)")
}

// Projected sideways (along -X), the floor is turned 90° from the decal's direction: no decal.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func decalFadesOnSurfacesTurnedAway() throws {
    let (sceneGraph, decal) = makeScene(decalRotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
    decal.transform.scale = [2, 2, 2]
    let center = pixel(try render(sceneGraph), 32, 32)
    #expect(isGray(center), "center \(center)")
}

// Without DecalRenderer's depth pass (no readable targets), decals are skipped instead of drawn as boxes, and they
// never cast shadows.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func decalsNeedReadableTargetsAndCastNoShadow() throws {
    let (sceneGraph, _) = makeScene()
    let renderer = try OffscreenRenderer(size: size)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(), DecalRenderer()])).texture
    let center = pixel(texture, 32, 32)
    #expect(isGray(center), "center \(center)")

    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1, defaultLight: .directional()))
    let frame = try Shadows().prepare(entries: sceneGraph.meshEntries(), context: context, bounds: sceneGraph.bounds)
    #expect(frame?.casters.count == 1)
}
