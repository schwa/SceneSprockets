import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import SwiftMesh
import Testing

// #132: debug views replace every mesh's material.
private func render(_ mode: DebugMode?, mesh: MetalMesh) throws -> SIMD4<UInt8> {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 4, 1]))), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [1, 1, 3, 1]))), content: .light(Light(type: .point, intensity: 5))))
    root.addChild(SceneGraph.Node(content: .mesh(mesh, material: BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.9, 0.2, 0.2]), specular: .color(0), shininess: 1))))
    let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], debugMode: mode)
    let texture = try OffscreenRenderer(size: CGSize(width: 64, height: 64)).render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
    return value
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func debugModesReplaceMaterials() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = try render(nil, mesh: box)
    // Blinn-Phong red (BGRA).
    #expect(material.z > material.y)

    let shaded = try render(.shaded, mesh: box)
    #expect(shaded.x == shaded.y && shaded.y == shaded.z && shaded.x > 100)

    // The front face points at the camera (+Z), so its normal color is about (0.5, 0.5, 1): blue is largest.
    let normals = try render(.normals, mesh: box)
    #expect(normals.x > normals.y && normals.x > normals.z)

    var colors: Set<SIMD4<UInt8>> = []
    for mode in DebugMode.allCases where mode != .wireframe {
        colors.insert(try render(mode, mesh: box))
    }
    #expect(colors.count == DebugMode.allCases.count - 1)
}

// #195: each renderer shows its own version of a material channel; values are unlit.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func materialChannelsShowMaterialValues() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    func pixel(_ material: any SceneMaterial, _ channel: MaterialChannel, renderer: any MaterialRenderer) throws -> SIMD4<UInt8> {
        let root = SceneGraph.Node()
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 4, 1]))), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
        root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
        let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [renderer], materialChannel: channel)
        let texture = try OffscreenRenderer(size: CGSize(width: 64, height: 64)).render(element).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
        return value
    }
    // No lights in the scene: lit output would be (nearly) black, channels are not.
    let blinnPhong = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color([1, 0, 0]), specular: .color([0, 0, 1]), shininess: 2)
    let red = try pixel(blinnPhong, .baseColor, renderer: BlinnPhongMaterialRenderer())
    #expect(red.z > 200 && red.x < 20) // BGRA
    let specular = try pixel(blinnPhong, .specular, renderer: BlinnPhongMaterialRenderer())
    #expect(specular.x > 200 && specular.z < 20)
    #expect(try pixel(blinnPhong, .metallic, renderer: BlinnPhongMaterialRenderer()).z < 5)

    let pbr = PBRSceneMaterial(baseColor: [0, 1, 0], metallic: 1, roughness: 0.5)
    let metallic = try pixel(pbr, .metallic, renderer: PBRMaterialRenderer())
    #expect(metallic.x > 200 && metallic.y > 200 && metallic.z > 200)
    let base = try pixel(pbr, .baseColor, renderer: PBRMaterialRenderer())
    #expect(base.y > 150 && base.z < 40)
}

@Test
func debugLayoutMapsAttributesBySemantic() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let layout = SceneGraphDebugRenderer.vertexLayout(box.vertexDescriptor)
    #expect(layout.hasNormals)
    let position = try #require(box.vertexDescriptor.attributes.first { $0.semantic == .position })
    #expect(layout.descriptor.attributes[0].format == position.format)
    #expect(layout.descriptor.attributes[0].offset == position.offset)
    #expect(layout.descriptor.attributes[3].format == .invalid)
}
