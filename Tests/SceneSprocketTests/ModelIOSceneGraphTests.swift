import Foundation
import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalKit
import ModelIO
import simd
import Testing
@testable import SceneSprocket
@testable import SceneSprocketBlinnPhong
@testable import SceneSprocketPBR

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// Two triangles in one OBJ object, each with its own MTL material.
private func makeOBJ() throws -> URL {
    let directory = try temporaryDirectory()
    let mtl = """
    newmtl Red
    Kd 1 0 0
    newmtl Blue
    Kd 0 0 1
    """
    let obj = """
    mtllib scene.mtl
    o Triangles
    v 0 0 0
    v 1 0 0
    v 0 1 0
    v 2 0 0
    v 3 0 0
    v 2 1 0
    usemtl Red
    f 1 2 3
    usemtl Blue
    f 4 5 6
    """
    try Data(mtl.utf8).write(to: directory.appendingPathComponent("scene.mtl"))
    let url = directory.appendingPathComponent("scene.obj")
    try Data(obj.utf8).write(to: url)
    return url
}

// A mesh under a translated transform.
private func makeUSDA() throws -> URL {
    let usda = """
    #usda 1.0
    (
        defaultPrim = "Root"
        upAxis = "Y"
    )
    def Xform "Root"
    {
        def Xform "Group"
        {
            double3 xformOp:translate = (5, 0, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]

            def Mesh "Triangle"
            {
                int[] faceVertexCounts = [3]
                int[] faceVertexIndices = [0, 1, 2]
                point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            }
        }
    }
    """
    let url = try temporaryDirectory().appendingPathComponent("scene.usda")
    try Data(usda.utf8).write(to: url)
    return url
}

@Test
func objLoadsWithPerSubmeshMaterials() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try ModelIOSceneGraph(url: try makeOBJ(), device: device)
    let entries = result.sceneGraph.meshEntries()
    #expect(entries.count == 2)
    let colors = entries.compactMap { ($0.material as? PBRSceneMaterial)?.pbrMaterial.uniforms.baseColorFactor }
    #expect(Set(colors.map { [$0.x, $0.y, $0.z] }) == [[1, 0, 0], [0, 0, 1]])
    #expect(result.animation == nil)

    let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: entries)
    #expect(model.opaqueInstances.count == 2)
}

@Test
func objLoadsAsBlinnPhong() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try ModelIOSceneGraph(url: try makeOBJ(), device: device, materials: .blinnPhong)
    #expect(result.sceneGraph.meshEntries().allSatisfy { $0.material is BlinnPhongSceneMaterial })
}

@Test
func usdHierarchyAndTransformsAreKept() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try ModelIOSceneGraph(url: try makeUSDA(), device: device)
    let entries = result.sceneGraph.meshEntries()
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.node.label == "Triangle")
    #expect(entry.node.parent?.label == "Group")
    #expect(entry.worldTransform.columns.3 == [5, 0, 0, 1])
}

// #55: normal, occlusion, metallic and roughness maps reach the PBR material.
@Test
func pbrMaterialMapsAreImported() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func map(_ name: String, _ bytes: [UInt8], channels: Int) -> MDLMaterialProperty {
        let texture = MDLTexture(data: Data(bytes), topLeftOrigin: true, name: name, dimensions: [2, 1], rowStride: 2 * channels, channelCount: channels, channelEncoding: .uInt8, isCube: false)
        return MDLMaterialProperty(name: name, semantic: .none, textureSampler: { let sampler = MDLTextureSampler(); sampler.texture = texture; return sampler }())
    }
    let material = MDLMaterial(name: "Mapped", scatteringFunction: MDLPhysicallyPlausibleScatteringFunction())
    for (semantic, property) in [
        (MDLMaterialSemantic.tangentSpaceNormal, map("normal", [128, 128, 255, 255, 128, 128, 255, 255], channels: 4)),
        (.ambientOcclusion, map("occlusion", [255, 255, 255, 255, 64, 64, 64, 255], channels: 4)),
        (.metallic, map("metallic", [0, 200], channels: 1)),
    ] {
        property.semantic = semantic
        material.remove(material.property(with: semantic) ?? property)
        material.setProperty(property)
    }
    material.setProperty(MDLMaterialProperty(name: "roughness", semantic: .roughness, float: 0.3))
    let mesh = MDLMesh(boxWithExtent: [1, 1, 1], segments: [1, 1, 1], inwardNormals: false, geometryType: .triangles, allocator: MTKMeshBufferAllocator(device: device))
    for case let submesh as MDLSubmesh in mesh.submeshes ?? [] {
        submesh.material = material
    }
    let asset = MDLAsset()
    asset.add(mesh)
    let result = try ModelIOSceneGraph(asset: asset, device: device)
    let pbr = try #require(result.sceneGraph.meshEntries().first?.material as? PBRSceneMaterial)
    let uniforms = pbr.pbrMaterial.uniforms
    #expect(uniforms.normal.enabled == 1)
    #expect(uniforms.occlusion.enabled == 1)
    #expect(uniforms.metallicRoughness.enabled == 1)
    #expect(uniforms.metallicFactor == 1)
    #expect(abs(uniforms.roughnessFactor - 0.3) < 1e-6)
    let packed = pbr.pbrMaterial.textureBindings[Int(kPBRTextureMetallicRoughness.rawValue)].texture
    var pixels = [UInt8](repeating: 0, count: 8)
    packed.getBytes(&pixels, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 1), mipmapLevel: 0)
    // RGBA: roughness (no map) 255 in green, metallic map in blue.
    #expect(pixels == [255, 255, 0, 255, 255, 255, 200, 255])
    #expect(result.warnings.isEmpty)
}
