import Metal
@testable import MetalSprocketsGLTF
import SwiftGLTF
import Testing

// #562: each Resources.load step runs on its own, and warnings carry a kind.

@Test func requiredExtensionsStepWarnsOrThrows() throws {
    let document = try Container(url: makeAnimatedTriangleFile()).document
    #expect(try GLTFAsset.Resources.checkRequiredExtensions(document, options: GLTFLoadOptions()).isEmpty)
    var required = document
    required.extensionsRequired = ["TEST_unknown"]
    #expect(throws: GLTFUnsupportedExtensionsError.self) {
        try GLTFAsset.Resources.checkRequiredExtensions(required, options: GLTFLoadOptions())
    }
    let warnings = try GLTFAsset.Resources.checkRequiredExtensions(required, options: GLTFLoadOptions(loadsUnsupportedRequiredExtensions: true))
    #expect(warnings.map(\.kind) == [.requiredExtensionsLoadedAnyway(["TEST_unknown"])])
}

@Test(.requiresMetal4) func geometryAndSkinStepsRunAlone() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let container = try Container(url: makeAnimatedTriangleFile())
    let geometry = try GLTFAsset.Resources.loadGeometry(container, device: device)
    #expect(geometry.meshes.map(\.count) == [1])
    #expect(geometry.warnings.isEmpty)
    #expect(try GLTFAsset.Resources.loadSkins(container).isEmpty)
}

@Test func extensionTableDrivesBuiltInExtensions() {
    let names = ["EXT_mesh_gpu_instancing", "EXT_lights_image_based", "KHR_node_visibility", "KHR_materials_variants", "KHR_animation_pointer", "KHR_xmp_json_ld"]
    #expect(GLTFExtensionFeature.extensionNames == Set(names))
    #expect(GLTFExtensionFeature.extensionNames.isSubset(of: GLTFAsset.builtInExtensions))
    #expect(GLTFMaterialFeature.extensionNames.isSubset(of: GLTFAsset.builtInExtensions))
}
