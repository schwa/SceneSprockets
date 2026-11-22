import CoreGraphics
import Foundation
import ImageIO
import Metal
@testable import SceneSprocketsPBR
import simd
import Testing
import UniformTypeIdentifiers

// #528: MaterialX standard_surface and UsdPreviewSurface materials load as PBR materials.

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "MaterialXTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// A 2x2 image of one gray level.
private func writeGrayPNG(_ value: UInt8, to url: URL) throws {
    var pixels = [UInt8](repeating: value, count: 4)
    let image = try pixels.withUnsafeMutableBytes { bytes in
        let context = try #require(CGContext(data: bytes.baseAddress, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 2, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        return try #require(context.makeImage())
    }
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
}

private func load(_ xml: String, folder: URL) throws -> MaterialXDocument {
    let url = folder.appending(path: "test.mtlx")
    try Data(xml.utf8).write(to: url)
    return try MaterialXDocument(url: url)
}

@Test
func standardSurfaceConstantsBecomePBRFactors() throws {
    let document = try load("""
    <?xml version="1.0"?>
    <materialx version="1.38">
      <standard_surface name="SR_gold" type="surfaceshader">
        <input name="base" type="float" value="0.5" />
        <input name="base_color" type="color3" value="1, 0.8, 0.2" />
        <input name="metalness" type="float" value="1" />
        <input name="specular_roughness" type="float" value="0.25" />
        <input name="specular_IOR" type="float" value="1.6" />
        <input name="coat" type="float" value="0.7" />
        <input name="emission" type="float" value="2" />
        <input name="emission_color" type="color3" value="0, 0.5, 1" />
        <input name="opacity" type="color3" value="0.5, 0.5, 0.5" />
      </standard_surface>
      <surfacematerial name="Gold" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_gold" />
      </surfacematerial>
    </materialx>
    """, folder: try temporaryFolder())
    #expect(document.warnings.isEmpty, "\(document.warnings)")
    let gold = try #require(document["Gold"])
    let uniforms = gold.uniforms
    #expect(simd_distance(uniforms.baseColorFactor, [0.5, 0.4, 0.1, 0.5]) < 1e-6)
    #expect(uniforms.metallicFactor == 1)
    #expect(uniforms.roughnessFactor == 0.25)
    #expect(uniforms.ior == 1.6)
    #expect(uniforms.clearcoatFactor == 0.7)
    #expect(uniforms.emissiveFactor == [0, 1, 2])
    #expect(gold.isTransparent)
}

@Test
func imagesConnectThroughNodegraphsAndNormalMaps() throws {
    let folder = try temporaryFolder()
    try FileManager.default.createDirectory(at: folder.appending(path: "textures"), withIntermediateDirectories: true)
    for name in ["color", "rough", "metal", "normal"] {
        try writeGrayPNG(name == "rough" ? 64 : 200, to: folder.appending(path: "textures/\(name).png"))
    }
    let document = try load("""
    <materialx version="1.38" fileprefix="textures/">
      <nodegraph name="NG">
        <image name="color" type="color3"><input name="file" type="filename" value="color.png" /></image>
        <image name="rough" type="float"><input name="file" type="filename" value="rough.png" /></image>
        <image name="normalImage" type="vector3"><input name="file" type="filename" value="normal.png" /></image>
        <normalmap name="normalMap" type="vector3"><input name="in" type="vector3" nodename="normalImage" /></normalmap>
        <output name="color_out" type="color3" nodename="color" />
        <output name="rough_out" type="float" nodename="rough" />
        <output name="normal_out" type="vector3" nodename="normalMap" />
      </nodegraph>
      <tiledimage name="metal" type="float"><input name="file" type="filename" value="metal.png" /></tiledimage>
      <standard_surface name="SR" type="surfaceshader">
        <input name="base_color" type="color3" nodegraph="NG" output="color_out" />
        <input name="specular_roughness" type="float" nodegraph="NG" output="rough_out" />
        <input name="metalness" type="float" nodename="metal" />
        <input name="normal" type="vector3" nodegraph="NG" output="normal_out" />
      </standard_surface>
      <surfacematerial name="Textured" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR" />
      </surfacematerial>
    </materialx>
    """, folder: folder)
    #expect(document.warnings.isEmpty, "\(document.warnings)")
    let uniforms = try #require(document["Textured"]).uniforms
    #expect(uniforms.baseColor.enabled == 1)
    #expect(uniforms.metallicRoughness.enabled == 1)
    #expect(uniforms.normal.enabled == 1)
    // Textures carry the values; factors are white.
    #expect(uniforms.metallicFactor == 1 && uniforms.roughnessFactor == 1)
}

@Test
func usdPreviewSurfaceAndUnsupportedInputs() throws {
    let document = try load("""
    <materialx version="1.38">
      <add name="sum" type="float"><input name="in1" type="float" value="0.1" /><input name="in2" type="float" value="0.2" /></add>
      <UsdPreviewSurface name="SR_usd" type="surfaceshader">
        <input name="diffuseColor" type="color3" value="0.2, 0.4, 0.6" />
        <input name="metallic" type="float" value="0" />
        <input name="roughness" type="float" nodename="sum" />
        <input name="clearcoat" type="float" value="1" />
      </UsdPreviewSurface>
      <surfacematerial name="Usd" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_usd" />
      </surfacematerial>
      <open_pbr_surface name="SR_open" type="surfaceshader" />
      <surfacematerial name="Open" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_open" />
      </surfacematerial>
    </materialx>
    """, folder: try temporaryFolder())
    let usd = try #require(document["Usd"]).uniforms
    #expect(simd_distance(usd.baseColorFactor, [0.2, 0.4, 0.6, 1]) < 1e-6)
    #expect(usd.clearcoatFactor == 1)
    // The add node is not evaluated: roughness keeps UsdPreviewSurface's default.
    #expect(usd.roughnessFactor == 0.5)
    #expect(document.materials.map(\.name) == ["Usd"])
    #expect(document.warnings.contains { $0.contains("roughness") && $0.contains("add") }, "\(document.warnings)")
    #expect(document.warnings.contains { $0.contains("open_pbr_surface") }, "\(document.warnings)")
}

@Test
func notMaterialXThrows() throws {
    #expect(throws: MaterialXError.self) {
        try MaterialXDocument(data: Data("<scene/>".utf8), baseURL: FileManager.default.temporaryDirectory)
    }
}
