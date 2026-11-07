import CoreGraphics
import Foundation
import GeometryLite3D
import ImageIO
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import Testing
import UniformTypeIdentifiers

// #341: textures from image files, in one line per material.

private func solidImage(red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return try #require(context.makeImage())
}

private func writePNG(_ image: CGImage) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MaterialTexture-\(UUID().uuidString).png")
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@MainActor
private func centerPixel(_ material: any SceneSprockets.Material, renderer: any SceneGraphMaterialRenderer, channel: SceneGraphMaterialChannel? = nil, device: MTLDevice) throws -> SIMD4<UInt8> {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    _ = SceneGraph.Node(parent: root, content: .mesh(SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device), material: material))
    let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [renderer], materialChannel: channel)
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

@Test
@MainActor
func blinnPhongTextureLoadsFromFile() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let url = try writePNG(solidImage(red: 1, green: 0, blue: 0))
    defer { try? FileManager.default.removeItem(at: url) }
    let material = BlinnPhongSceneMaterial(ambient: try .texture(contentsOf: url, device: device), diffuse: .color(0), specular: .color(0), shininess: 1)
    let value = try centerPixel(material, renderer: BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1]), device: device)
    // BGRA.
    #expect(value.z > 240 && value.x < 10 && value.y < 10)
}

@Test
@MainActor
func pbrBaseColorTextureLoadsFromImage() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let green = try MaterialTexture.load(solidImage(red: 0, green: 1, blue: 0), device: device)
    #expect(green.pixelFormat.isSRGB, "format \(green.pixelFormat.rawValue)")
    let material = try PBRSceneMaterial(device: device, textures: .init(baseColor: green))
    #expect(material.pbrMaterial.uniforms.baseColor.enabled == 1)
    #expect(material.pbrMaterial.uniforms.normal.enabled == 0)
    let value = try centerPixel(material, renderer: PBRMaterialRenderer(device: device), channel: .baseColor, device: device)
    #expect(value.y > 200 && value.x < 40 && value.z < 40)
}

// A mid-grey sRGB image comes back as the same grey: no double encoding or decoding.
@Test
@MainActor
func colorTexturesKeepTheirValues() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let grey = try MaterialTexture.load(solidImage(red: 0.5, green: 0.5, blue: 0.5), device: device)
    let material = try PBRSceneMaterial(device: device, textures: .init(baseColor: grey))
    let value = try centerPixel(material, renderer: PBRMaterialRenderer(device: device), channel: .baseColor, device: device)
    #expect(abs(Int(value.y) - 128) < 12, "\(value)")
}

// Loaded textures are private (and may be sRGB views); scene archives still save and load them.
@Test
@MainActor
func loadedTexturesSurviveAnArchive() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let red = try MaterialTexture.load(solidImage(red: 1, green: 0, blue: 0), device: device)
    let root = SceneGraph.Node(label: "Root")
    _ = SceneGraph.Node(parent: root, shape: .plane(), material: BlinnPhongSceneMaterial(ambient: .texture(red), diffuse: .color(0), specular: .color(0), shininess: 1), device: device)
    let archive = SceneArchive(materialTypes: [BlinnPhongSceneMaterial.self], meshCodec: GLTFMeshCodec())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("MaterialTexture-\(UUID().uuidString).scenesprockets")
    defer { try? FileManager.default.removeItem(at: url) }
    _ = try archive.write(SceneGraph(root: root), to: url)
    let (read, _) = try archive.read(from: url, device: device)
    guard case let .mesh(_, materials, _, _) = try #require(read.root.children.first).content,
          let material = materials.first as? BlinnPhongSceneMaterial, case let .texture(texture, _, _) = material.ambient else {
        Issue.record("No textured material after reading")
        return
    }
    #expect(texture.width == 4 && texture.height == 4)
    #expect(texture.pixelFormat.isSRGB)
}

@Test
func dataTexturesAreLinear() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let texture = try MaterialTexture.load(solidImage(red: 0.5, green: 0.5, blue: 1), device: device, isColor: false)
    #expect(!texture.pixelFormat.isSRGB)
    #expect(texture.mipmapLevelCount > 1)
}

private extension MTLPixelFormat {
    var isSRGB: Bool {
        [.rgba8Unorm_srgb, .bgra8Unorm_srgb].contains(self)
    }
}
