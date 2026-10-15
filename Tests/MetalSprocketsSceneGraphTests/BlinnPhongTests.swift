import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

// #100: the in-repo Blinn-Phong renderer.
@MainActor
private func centerPixel(_ mesh: MetalMesh, _ material: BlinnPhongSceneMaterial, ambientLight: SIMD3<Float> = [1, 1, 1]) throws -> SIMD4<UInt8> {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    _ = SceneGraph.Node(parent: root, content: .mesh(mesh, material: material))
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: ambientLight)])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

@Test
@MainActor
func diffuseAndAmbientTexturesAreSampled() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    let red = try #require(device.makeTexture(descriptor: descriptor))
    red.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8(255), 0, 0, 255], bytesPerRow: 4)
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    // Ambient only: the texture, tinted to half.
    let value = try centerPixel(quad, BlinnPhongSceneMaterial(ambient: .texture(red, tint: [0.5, 0.5, 0.5]), diffuse: .color(0), specular: .color(0), shininess: 1))
    // BGRA, sRGB: linear 0.5 encodes to about 188.
    #expect(value.z > 170 && value.z < 205)
    #expect(value.x < 5 && value.y < 5)
}

@Test
@MainActor
func zeroNormalsFallBackToFaceNormals() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let positions: [SIMD3<Float>] = [[-1, -1, 0], [1, -1, 0], [-1, 1, 0], [1, 1, 0]]
    let mesh = MetalMesh(device: device, attributes: [
        .positions(positions),
        .normals(Array(repeating: .zero, count: 4)),
        .textureCoordinates(Array(repeating: .zero, count: 4)),
    ], submeshes: [.init(indices: [0, 1, 2, 2, 1, 3])])
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    // A light behind the camera, shining at the quad: lit only if the fallback normal faces the camera.
    _ = SceneGraph.Node(parent: root, content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1)))
    _ = SceneGraph.Node(parent: root, content: .mesh(mesh, material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(1), specular: .color(0), shininess: 1)))
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero)])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    #expect(value.x > 200 && value.y > 200 && value.z > 200)
}
