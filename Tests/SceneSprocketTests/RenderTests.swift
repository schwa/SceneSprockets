import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import SwiftMesh
import Testing
import simd
@testable import SceneSprocket
@testable import SceneSprocketBlinnPhong
@testable import SceneSprocketPBR

// Renders small scenes offscreen and checks pixels, so both renderers are exercised end to end.

private let size = CGSize(width: 64, height: 64)

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
}

// BGRA pixel at (x, y).
private func pixel(_ texture: MTLTexture, x: Int, y: Int) -> SIMD4<UInt8> {
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
    return value
}

private func isBackground(_ value: SIMD4<UInt8>) -> Bool {
    value.x < 3 && value.y < 3 && value.z < 3
}

private func makeScene(meshMaterial: (MetalMesh) throws -> SceneGraph.Node.Content, xOffset: Float = 0) throws -> (SceneGraph, MetalMesh) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, transform: translation(0, 0, 4), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    _ = SceneGraph.Node(parent: root, transform: translation(2, 2, 3), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 5)))
    _ = SceneGraph.Node(parent: root, transform: translation(xOffset, 0, 0), content: try meshMaterial(box))
    return (SceneGraph(root: root), box)
}

private var blinnPhong: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color([0.3, 0.1, 0.1]), diffuse: .color([0.9, 0.2, 0.2]), specular: .color([1, 1, 1]), shininess: 16)
}

@Test
@MainActor
func blinnPhongBoxIsDrawnAtCenter() throws {
    let (sceneGraph, _) = try makeScene { .mesh($0, material: blinnPhong) }
    let renderer = try OffscreenRenderer(size: size)
    let texture = try renderer.render(BlinnPhongSceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1)).texture

    let center = pixel(texture, x: 32, y: 32)
    #expect(!isBackground(center))
    #expect(center.z > center.y) // Red material (BGRA).
    #expect(isBackground(pixel(texture, x: 1, y: 1)))
}

@Test
@MainActor
func culledBoxDrawsNothing() throws {
    let (sceneGraph, _) = try makeScene(meshMaterial: { .mesh($0, material: blinnPhong) }, xOffset: 50)
    let renderer = try OffscreenRenderer(size: size)
    let texture = try renderer.render(BlinnPhongSceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1)).texture
    #expect(isBackground(pixel(texture, x: 32, y: 32)))
}

@Test
@MainActor
func blinnPhongSkinnedBoxFollowsJoint() throws {
    let (sceneGraph, box) = try makeScene(meshMaterial: { .mesh($0, material: blinnPhong) }, xOffset: 100)
    let skinned = try #require(sceneGraph.meshEntries().first?.node)
    let joint = SceneGraph.Node(parent: sceneGraph.root)
    skinned.skin = SceneGraph.Skin(joints: [joint], inverseBindMatrices: [matrix_identity_float4x4])
    skinned.skinVertices = Array(repeating: SceneGraph.SkinVertex(joints: [0, 0, 0, 0], weights: [1, 0, 0, 0]), count: box.vertexCount)

    let texture = try OffscreenRenderer(size: size).render(BlinnPhongSceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1)).texture
    #expect(!isBackground(pixel(texture, x: 32, y: 32)))
}

@Test
@MainActor
func blinnPhongDirectionalLightFollowsNodeRotation() throws {
    func centerBrightness(lightRotation: simd_quatf) throws -> Int {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let root = SceneGraph.Node()
        _ = SceneGraph.Node(parent: root, transform: translation(0, 0, 4), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
        let light = SceneGraph.Node(parent: root, content: .light(Light(type: .directional, intensity: 1)))
        light.trs.rotation = lightRotation
        _ = SceneGraph.Node(parent: root, content: .mesh(MetalMesh(mesh: .box(), device: device), material: blinnPhong))
        let texture = try OffscreenRenderer(size: size).render(BlinnPhongSceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1)).texture
        let center = pixel(texture, x: 32, y: 32)
        return Int(center.x) + Int(center.y) + Int(center.z)
    }
    // Identity points down -Z, onto the box's front face; turned around it lights the back.
    let facing = try centerBrightness(lightRotation: simd_quatf(angle: 0, axis: [0, 1, 0]))
    let away = try centerBrightness(lightRotation: simd_quatf(angle: .pi, axis: [0, 1, 0]))
    #expect(facing > away + 30)
}

@Test
@MainActor
func pbrBoxIsDrawnAtCenter() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let material = try PBRSceneMaterial(device: device, baseColor: [0.1, 0.8, 0.1, 1], metallic: 0, roughness: 0.5)
    let (sceneGraph, _) = try makeScene { .mesh($0, material: material) }
    let renderer = try OffscreenRenderer(size: size)
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer(device: device)])
    let texture = try renderer.render(element).texture

    let center = pixel(texture, x: 32, y: 32)
    #expect(!isBackground(center))
    #expect(center.y > center.z) // Green material (BGRA).
    #expect(isBackground(pixel(texture, x: 1, y: 1)))
}

@Test
@MainActor
func mixedRenderersShareOnePass() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let pbr = try PBRSceneMaterial(device: device, baseColor: [0.1, 0.8, 0.1, 1], metallic: 0, roughness: 0.5)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, transform: translation(0, 0, 6), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    _ = SceneGraph.Node(parent: root, transform: translation(0, 2, 4), content: .light(Light(type: .point, color: [1, 1, 1], intensity: 5)))
    _ = SceneGraph.Node(parent: root, transform: translation(-1.2, 0, 0), content: .mesh(box, material: blinnPhong))
    _ = SceneGraph.Node(parent: root, transform: translation(1.2, 0, 0), content: .mesh(box, material: pbr))
    let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer(device: device)])

    let texture = try OffscreenRenderer(size: size).render(element).texture
    let left = pixel(texture, x: 20, y: 32)
    let right = pixel(texture, x: 44, y: 32)
    #expect(left.z > left.y) // Blinn-Phong red on the left.
    #expect(right.y > right.z) // PBR green on the right.
}
