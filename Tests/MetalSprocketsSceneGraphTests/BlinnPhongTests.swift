import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
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

// #36: two flat-colored quads, `near` in front. Returns the center pixel (BGRA).
@MainActor
private func quads(near: BlinnPhongSceneMaterial, far: BlinnPhongSceneMaterial, nearFirst: Bool = true) throws -> SIMD4<UInt8> {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    let nearNode = SceneGraph.Node(trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: near))
    let farNode = SceneGraph.Node(content: .mesh(quad, material: far))
    for node in nearFirst ? [nearNode, farNode] : [farNode, nearNode] {
        root.addChild(node)
    }
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1])])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

private func flat(_ color: SIMD3<Float>, opacity: Float = 1) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(color), diffuse: .color(0), specular: .color(0), shininess: 1, opacity: opacity)
}

@Test
@MainActor
func translucentBlinnPhongBlendsOverWhatIsBehind() throws {
    // Opaque red in front hides blue.
    let opaque = try quads(near: flat([1, 0, 0]), far: flat([0, 0, 1]))
    #expect(opaque.z > 200 && opaque.x < 5)
    // Half-transparent red in front: both show. The opaque quad draws first, even though it comes second.
    let blended = try quads(near: flat([1, 0, 0], opacity: 0.5), far: flat([0, 0, 1]))
    #expect(blended.z > 100 && blended.x > 100)
}

@Test(arguments: [true, false])
@MainActor
func translucentBlinnPhongDrawsBackToFront(nearFirst: Bool) throws {
    // Both half-transparent: the nearer one draws last and dominates, whatever the scene order.
    let value = try quads(near: flat([1, 0, 0], opacity: 0.5), far: flat([0, 0, 1], opacity: 0.5), nearFirst: nearFirst)
    #expect(Int(value.z) > Int(value.x) + 20)
    // And the far one shows through (transparent draws do not write depth).
    #expect(value.x > 40)
}

@Test
@MainActor
func diffuseTextureAlphaIsOpacity() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    let clear = try #require(device.makeTexture(descriptor: descriptor))
    clear.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8(255), 255, 255, 0], bytesPerRow: 4)
    let material = BlinnPhongSceneMaterial(ambient: .color([1, 0, 0]), diffuse: .texture(clear), specular: .color(0), shininess: 1, usesDiffuseTextureAlpha: true)
    #expect(material.isTransparent)
    // Fully clear: only the blue quad behind shows.
    let value = try quads(near: material, far: flat([0, 0, 1]))
    #expect(value.x > 200 && value.z < 5)
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

// #83: center pixel (BGRA) of a 2x2 quad at the origin, lit by a directional light shining down -Z, seen from +Z.
@MainActor
private func litQuadPixel(_ material: BlinnPhongSceneMaterial, quadRotation: simd_quatf = .identity) throws -> SIMD4<UInt8> {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    _ = SceneGraph.Node(parent: root, content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1)))
    _ = SceneGraph.Node(parent: root, trs: .init(rotation: quadRotation), content: .mesh(quad, material: material))
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero)])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

private func solidTexture(_ bytes: [UInt8]) throws -> MTLTexture {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
    let texture = try #require(device.makeTexture(descriptor: descriptor))
    texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: bytes, bytesPerRow: 4)
    return texture
}

@Test(arguments: [false, true])
@MainActor
func emissionAddsUnlitColor(usesTexture: Bool) throws {
    let emission: BlinnPhongSceneMaterial.Source = usesTexture ? .texture(try solidTexture([0, 255, 0, 255])) : .color([0, 1, 0])
    let value = try litQuadPixel(BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: emission))
    #expect(value.y > 250 && value.x < 5 && value.z < 5)
}

@Test
@MainActor
func normalMapBendsLighting() throws {
    let plain = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(1), specular: .color(0), shininess: 1)
    #expect(try litQuadPixel(plain).x > 200)
    // Tangent-space +X: the normal lies in the quad's plane, at right angles to the light.
    var mapped = plain
    mapped.normalMap = try solidTexture([255, 128, 128, 255])
    #expect(try litQuadPixel(mapped).x < 20)
    // Straight up (+Z) matches the mesh normal.
    mapped.normalMap = try solidTexture([128, 128, 255, 255])
    #expect(try litQuadPixel(mapped).x > 200)
}

@Test
@MainActor
func cullModeHidesBackFaces() throws {
    var material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 1, 1]))
    let turned = simd_quatf(angle: .pi, axis: [0, 1, 0])
    #expect(try litQuadPixel(material, quadRotation: turned).x > 200)
    material.cullMode = .back
    #expect(try litQuadPixel(material).x > 200)
    #expect(try litQuadPixel(material, quadRotation: turned).x < 5)
    material.cullMode = .front
    #expect(try litQuadPixel(material).x < 5)
}
