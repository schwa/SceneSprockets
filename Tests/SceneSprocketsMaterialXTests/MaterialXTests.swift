import CoreGraphics
import Foundation
import ImageIO
import Metal
@testable import SceneSprocketsMaterialX
import SceneSprocketsPBR
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
    let xml = """
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
    """
    let document = try load(xml, folder: try temporaryFolder())
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
    let xml = """
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
    """
    let document = try load(xml, folder: folder)
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
    let xml = """
    <materialx version="1.38">
      <noise2d name="noise" type="float"><input name="amplitude" type="float" value="1" /></noise2d>
      <UsdPreviewSurface name="SR_usd" type="surfaceshader">
        <input name="diffuseColor" type="color3" value="0.2, 0.4, 0.6" />
        <input name="metallic" type="float" value="0" />
        <input name="roughness" type="float" nodename="noise" />
        <input name="clearcoat" type="float" value="1" />
      </UsdPreviewSurface>
      <surfacematerial name="Usd" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_usd" />
      </surfacematerial>
      <disney_brdf name="SR_disney" type="surfaceshader" />
      <surfacematerial name="Disney" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_disney" />
      </surfacematerial>
    </materialx>
    """
    let document = try load(xml, folder: try temporaryFolder())
    let usdMaterial = try #require(document["Usd"])
    let usd = usdMaterial.uniforms
    #expect(simd_distance(usd.baseColorFactor, [0.2, 0.4, 0.6, 1]) < 1e-6)
    #expect(usd.clearcoatFactor == 1)
    // The CPU cannot evaluate the noise, so the material is compiled to run per pixel (#667).
    #expect(usdMaterial.pbrMaterial.surfaceFunction != nil)
    #expect(document.materials.map(\.name) == ["Usd"])
    #expect(!document.warnings.contains { $0.contains("noise2d") }, "\(document.warnings)")
    #expect(document.warnings.contains { $0.contains("disney_brdf") }, "\(document.warnings)")
}

// #609: math nodes with constant inputs are folded, and an image times a constant becomes the texture's factor.
@Test
func constantMathNodesAreEvaluated() throws {
    let folder = try temporaryFolder()
    try writeGrayPNG(200, to: folder.appending(path: "color.png"))
    let xml = """
    <materialx version="1.38">
      <nodegraph name="NG">
        <input name="tint" type="color3" value="0.5, 1, 1" />
        <image name="color" type="color3"><input name="file" type="filename" value="color.png" /></image>
        <multiply name="tinted" type="color3"><input name="in1" type="color3" nodename="color" /><input name="in2" type="color3" interfacename="tint" /></multiply>
        <add name="sum" type="float"><input name="in1" type="float" value="0.1" /><input name="in2" type="float" value="0.2" /></add>
        <multiply name="half" type="float"><input name="in1" type="float" nodename="sum" /><input name="in2" type="float" value="2" /></multiply>
        <constant name="red" type="color3"><input name="value" type="color3" value="1, 0, 0" /></constant>
        <mix name="blend" type="color3"><input name="fg" type="color3" nodename="red" /><input name="bg" type="color3" value="0, 0, 1" /><input name="mix" type="float" value="0.25" /></mix>
        <extract name="green" type="float"><input name="in" type="color3" value="0.1, 0.7, 0.3" /><input name="index" type="integer" value="1" /></extract>
        <clamp name="clamped" type="float"><input name="in" type="float" value="3" /></clamp>
        <output name="color_out" type="color3" nodename="tinted" />
        <output name="rough_out" type="float" nodename="half" />
        <output name="emission_out" type="color3" nodename="blend" />
        <output name="metal_out" type="float" nodename="green" />
        <output name="coat_out" type="float" nodename="clamped" />
      </nodegraph>
      <standard_surface name="SR" type="surfaceshader">
        <input name="base_color" type="color3" nodegraph="NG" output="color_out" />
        <input name="specular_roughness" type="float" nodegraph="NG" output="rough_out" />
        <input name="metalness" type="float" nodegraph="NG" output="metal_out" />
        <input name="coat" type="float" nodegraph="NG" output="coat_out" />
        <input name="emission" type="float" value="1" />
        <input name="emission_color" type="color3" nodegraph="NG" output="emission_out" />
      </standard_surface>
      <surfacematerial name="Math" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR" />
      </surfacematerial>
    </materialx>
    """
    let document = try load(xml, folder: folder)
    #expect(document.warnings.isEmpty, "\(document.warnings)")
    let uniforms = try #require(document["Math"]).uniforms
    #expect(uniforms.baseColor.enabled == 1)
    #expect(simd_distance(uniforms.baseColorFactor, [0.5, 1, 1, 1]) < 1e-6)
    #expect(abs(uniforms.roughnessFactor - 0.6) < 1e-6)
    #expect(abs(uniforms.metallicFactor - 0.7) < 1e-6)
    #expect(uniforms.clearcoatFactor == 1)
    #expect(simd_distance(uniforms.emissiveFactor, [0.25, 0, 0.75]) < 1e-6)
}

// #609: gltf_pbr and open_pbr_surface shaders load.
@Test
func gltfAndOpenPBRShadersLoad() throws {
    let xml = """
    <materialx version="1.39">
      <gltf_pbr name="SR_gltf" type="surfaceshader">
        <input name="base_color" type="color3" value="0.2, 0.4, 0.6" />
        <input name="metallic" type="float" value="0.3" />
        <input name="roughness" type="float" value="0.4" />
        <input name="alpha" type="float" value="0.5" />
        <input name="emissive" type="color3" value="1, 0.5, 0" />
        <input name="emissive_strength" type="float" value="2" />
        <input name="clearcoat" type="float" value="0.8" />
        <input name="transmission" type="float" value="0.1" />
      </gltf_pbr>
      <surfacematerial name="Gltf" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_gltf" />
      </surfacematerial>
      <open_pbr_surface name="SR_open" type="surfaceshader">
        <input name="base_weight" type="float" value="0.5" />
        <input name="base_color" type="color3" value="1, 0.8, 0.6" />
        <input name="base_metalness" type="float" value="1" />
        <input name="specular_roughness" type="float" value="0.35" />
        <input name="specular_ior" type="float" value="1.7" />
        <input name="coat_weight" type="float" value="0.6" />
        <input name="geometry_opacity" type="float" value="1" />
      </open_pbr_surface>
      <surfacematerial name="Open" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR_open" />
      </surfacematerial>
    </materialx>
    """
    let document = try load(xml, folder: try temporaryFolder())
    #expect(document.warnings.isEmpty, "\(document.warnings)")
    let gltf = try #require(document["Gltf"])
    #expect(simd_distance(gltf.uniforms.baseColorFactor, [0.2, 0.4, 0.6, 0.5]) < 1e-6)
    #expect(gltf.uniforms.metallicFactor == 0.3 && gltf.uniforms.roughnessFactor == 0.4)
    #expect(gltf.uniforms.emissiveFactor == [2, 1, 0])
    #expect(gltf.uniforms.clearcoatFactor == 0.8 && gltf.uniforms.transmissionFactor == 0.1)
    #expect(gltf.isTransparent)
    let open = try #require(document["Open"]).uniforms
    #expect(simd_distance(open.baseColorFactor, [0.5, 0.4, 0.3, 1]) < 1e-6)
    #expect(open.metallicFactor == 1 && open.roughnessFactor == 0.35)
    #expect(open.ior == 1.7 && open.clearcoatFactor == 0.6)
}

// #665: documents are read with MetalSprocketsMaterialX, which follows xi:include.
@Test
func includedShadersAreFollowed() throws {
    let folder = try temporaryFolder()
    let shaders = """
    <?xml version="1.0"?>
    <materialx version="1.39">
      <standard_surface name="Shader" type="surfaceshader">
        <input name="metalness" type="float" value="0.75" />
      </standard_surface>
    </materialx>
    """
    try Data(shaders.utf8).write(to: folder.appending(path: "shaders.mtlx"))
    let material = """
    <?xml version="1.0"?>
    <materialx version="1.39" xmlns:xi="http://www.w3.org/2001/XInclude">
      <xi:include href="shaders.mtlx" />
      <surfacematerial name="Included" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="Shader" />
      </surfacematerial>
    </materialx>
    """
    let document = try load(material, folder: folder)
    #expect(document.warnings.isEmpty)
    #expect(try #require(document["Included"]).uniforms.metallicFactor == 0.75)
}

@Test
func notMaterialXThrows() throws {
    #expect(throws: MaterialXError.self) {
        try MaterialXDocument(data: Data("<scene/>".utf8), baseURL: FileManager.default.temporaryDirectory)
    }
}
