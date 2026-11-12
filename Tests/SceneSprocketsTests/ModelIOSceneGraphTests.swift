import Foundation
import GeometryLite3D
import Metal
import MetalKit
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import ModelIO
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

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

@Test(.enabled(if: deviceSupportsMetal4))
func objLoadsWithPerSubmeshMaterials() throws {
    let result = try ModelIOImport(url: try makeOBJ())
    let entries = result.sceneGraph.meshEntries()
    #expect(entries.count == 2)
    let colors = entries.compactMap { ($0.material as? PBRSceneMaterial)?.pbrMaterial.uniforms.baseColorFactor }
    #expect(Set(colors.map { [$0.x, $0.y, $0.z] }) == [[1, 0, 0], [0, 0, 1]])
    #expect(result.animations.isEmpty)

    let model = try PBRSceneGraphModelBuilder().makeModel(entries: entries)
    #expect(model.opaqueInstances.count == 2)
}

@Test
func objLoadsAsBlinnPhong() throws {
    let result = try ModelIOImport(url: try makeOBJ(), materials: .blinnPhong)
    #expect(result.sceneGraph.meshEntries().allSatisfy { $0.material is BlinnPhongSceneMaterial })
}

@Test
func usdHierarchyAndTransformsAreKept() throws {
    let result = try ModelIOImport(url: try makeUSDA())
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
        (.metallic, map("metallic", [0, 200], channels: 1))
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
    let result = try ModelIOImport(asset: asset)
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

// #302: an orthographic USD camera loads. USD orthographic apertures are in tenths of a scene unit.
@Test
func orthographicCameraLoads() throws {
    let url = try temporaryDirectory().appendingPathComponent("ortho.usda")
    let usda = """
    #usda 1.0
    (
        upAxis = "Y"
    )
    def Camera "Ortho"
    {
        token projection = "orthographic"
        float verticalAperture = 40
        float horizontalAperture = 60
        float2 clippingRange = (0.5, 200)
    }
    """
    try Data(usda.utf8).write(to: url)
    let result = try ModelIOImport(url: url)
    var cameras: [Camera] = []
    result.sceneGraph.visit { node, _ in
        if case let .camera(camera) = node.content {
            cameras.append(camera)
        }
    }
    let projection = try #require(cameras.first?.projection as? OrthographicProjection)
    #expect(abs(projection.halfHeight - 2) < 1e-5)
    #expect(projection.depthMode == .standard(zClip: 0.5 ... 200))
    #expect(!result.warnings.contains { $0.contains("Camera") })
}

// A two-joint leg. The knee's rest pose is 1 unit above its bind pose, so the top of the leg moves up by 1.
private func skinnedLegUSDA(animation: String = "") -> String {
    """
    #usda 1.0
    (
        defaultPrim = "Root"
        upAxis = "Y"
    )
    def SkelRoot "Root"
    {
        double3 xformOp:translate = (10, 0, 0)
        uniform token[] xformOpOrder = ["xformOp:translate"]
        def Skeleton "Skel" (
            prepend apiSchemas = ["SkelBindingAPI"]
        )
        {
            uniform token[] joints = ["Hip", "Hip/Knee"]
            uniform matrix4d[] bindTransforms = [((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,0,0,1)), ((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,1,0,1))]
            uniform matrix4d[] restTransforms = [((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,0,0,1)), ((1,0,0,0),(0,1,0,0),(0,0,1,0),(0,2,0,1))]
            \(animation.isEmpty ? "" : "rel skel:animationSource = </Root/Skel/Anim>")
            \(animation)
        }
        def Mesh "Leg" (
            prepend apiSchemas = ["SkelBindingAPI"]
        )
        {
            int[] faceVertexCounts = [4]
            int[] faceVertexIndices = [0, 1, 2, 3]
            point3f[] points = [(-0.5,0,0), (0.5,0,0), (0.5,2,0), (-0.5,2,0)]
            int[] primvars:skel:jointIndices = [0, 0, 1, 1] (
                elementSize = 1
                interpolation = "vertex"
            )
            float[] primvars:skel:jointWeights = [1, 1, 1, 1] (
                elementSize = 1
                interpolation = "vertex"
            )
            rel skel:skeleton = </Root/Skel>
        }
    }
    """
}

@Test
func skinLoadsAndDeformsTheMesh() throws {
    let url = try temporaryDirectory().appendingPathComponent("skin.usda")
    try Data(skinnedLegUSDA().utf8).write(to: url)
    let result = try ModelIOImport(url: url)
    let entry = try #require(result.sceneGraph.meshEntries().first)
    let skin = try #require(entry.node.skin)
    #expect(skin.joints.map(\.label) == ["Hip", "Knee"])
    #expect(entry.node.skinVertices.count == entry.mesh.vertexCount)
    let deformed = try #require(entry.deformed(revision: result.sceneGraph.revision))
    let bounds = try #require(deformed.mesh.positionBounds())
    #expect(abs(bounds.min.x - 9.5) < 1e-4)
    #expect(abs(bounds.min.y) < 1e-4)
    #expect(abs(bounds.max.y - 3) < 1e-4)
    #expect(!result.warnings.contains { $0.contains("skin") })
}

@Test
func jointAnimationBecomesChannels() throws {
    let url = try temporaryDirectory().appendingPathComponent("skinAnimation.usda")
    let animation = """
    def SkelAnimation "Anim"
    {
        uniform token[] joints = ["Hip/Knee"]
        float3[] translations.timeSamples = { 0: [(0, 1, 0)], 24: [(0, 3, 0)] }
        quatf[] rotations = [(1, 0, 0, 0)]
        half3[] scales = [(1, 1, 1)]
    }
    """
    try Data(skinnedLegUSDA(animation: animation).utf8).write(to: url)
    let result = try ModelIOImport(url: url)
    let clip = try #require(result.animations.first)
    let knee = try #require(result.sceneGraph.meshEntries().first?.node.skin?.joints.last)
    let translation = try #require(clip.channels.first { $0.target === knee && $0.path == .translation })
    #expect(translation.sampler.values.first.map { abs($0) < 1e-4 } == true)
    #expect(translation.sampler.values.count == translation.sampler.times.count * 3)
    #expect(translation.sampler.values.suffix(2).first.map { abs($0 - 3) < 1e-4 } == true)
    // #371: ModelFile returns the same clip in its animations array, with no glTF-only parts.
    let loaded = try ModelFile.load(url)
    #expect(loaded.animations.count == 1)
    #expect(loaded.variants == nil)
    #expect(loaded.environmentMap == nil)
}
