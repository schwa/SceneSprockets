import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import SceneSprockets
@testable import SceneSprocketsMaterialX
import SceneSprocketsPBR
import Testing

private let deviceSupportsMetal4 = MTLCreateSystemDefaultDevice()?.supportsFamily(.metal4) ?? false

// #667: a material whose base color depends on the texture coordinate renders per pixel.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func texcoordGraphRendersPerPixel() throws {
    let xml = """
    <?xml version="1.0"?>
    <materialx version="1.39">
      <nodegraph name="NG">
        <texcoord name="uv" type="vector2" />
        <extract name="u" type="float">
          <input name="in" type="vector2" nodename="uv" />
          <input name="index" type="integer" value="0" />
        </extract>
        <convert name="gray" type="color3">
          <input name="in" type="float" nodename="u" />
        </convert>
        <output name="out" type="color3" nodename="gray" />
      </nodegraph>
      <gltf_pbr name="SR" type="surfaceshader">
        <input name="base_color" type="color3" nodegraph="NG" output="out" />
      </gltf_pbr>
      <surfacematerial name="Ramp" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR" />
      </surfacematerial>
    </materialx>
    """
    let document = try MaterialXDocument(data: Data(xml.utf8), baseURL: FileManager.default.temporaryDirectory)
    #expect(document.warnings.isEmpty, "\(document.warnings)")
    let material = try #require(document["Ramp"])
    #expect(material.pbrMaterial.surfaceFunction != nil)

    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    root.addChild(SceneGraph.Node(content: .mesh(SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(), material: material)))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.environment.toneMapping = .linear
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer()], materialChannel: .baseColor)
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(element).texture
    func pixel(_ x: Int) -> SIMD4<UInt8> {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, 8, 1, 1), mipmapLevel: 0)
        return value
    }
    let left = pixel(3)
    let right = pixel(12)
    // Base color is u: dark on the left, light on the right.
    #expect(Int(right.x) > Int(left.x) + 60, "left \(left), right \(right)")
}

// A lit surface-function material with a flat normal map shades like a plain material with the same inputs. The
// surface context once used the raw vertex tangent, which is zero on meshes without tangents, and washed lit
// surfaces out.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func stitchedMaterialLightsLikePlainMaterial() throws {
    let xml = """
    <?xml version="1.0"?>
    <materialx version="1.39">
      <nodegraph name="NG">
        <texcoord name="uv" type="vector2" />
        <extract name="u" type="float">
          <input name="in" type="vector2" nodename="uv" />
          <input name="index" type="integer" value="0" />
        </extract>
        <multiply name="zero" type="float">
          <input name="in1" type="float" nodename="u" />
          <input name="in2" type="float" value="0" />
        </multiply>
        <add name="red" type="color3">
          <input name="in1" type="color3" value="0.4, 0.15, 0.02" />
          <input name="in2" type="float" nodename="zero" />
        </add>
        <output name="out" type="color3" nodename="red" />
        <normalmap name="flat" type="vector3">
          <input name="in" type="vector3" value="0.5, 0.5, 1" />
        </normalmap>
        <output name="normal_out" type="vector3" nodename="flat" />
      </nodegraph>
      <gltf_pbr name="SR" type="surfaceshader">
        <input name="base_color" type="color3" nodegraph="NG" output="out" />
        <input name="normal" type="vector3" nodegraph="NG" output="normal_out" />
        <input name="metallic" type="float" value="0" />
        <input name="roughness" type="float" value="0.6" />
      </gltf_pbr>
      <surfacematerial name="Red" type="material">
        <input name="surfaceshader" type="surfaceshader" nodename="SR" />
      </surfacematerial>
    </materialx>
    """
    let document = try MaterialXDocument(data: Data(xml.utf8), baseURL: FileManager.default.temporaryDirectory)
    let stitched = try #require(document["Red"])
    #expect(stitched.pbrMaterial.surfaceFunction != nil)
    let plain = PBRSceneMaterial(baseColor: [0.4, 0.15, 0.02], metallic: 0, roughness: 0.6)

    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    root.addChild(SceneGraph.Node(transform: .init(translation: [-0.55, 0, 0]), content: .mesh(SceneGraph.Shape.plane(width: 1, height: 2).metalMesh(), material: stitched)))
    root.addChild(SceneGraph.Node(transform: .init(translation: [0.55, 0, 0]), content: .mesh(SceneGraph.Shape.plane(width: 1, height: 2).metalMesh(), material: plain)))
    let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [PBRMaterialRenderer()])
    let texture = try OffscreenRenderer(size: CGSize(width: 32, height: 32)).render(element).texture
    func pixel(_ x: Int) -> SIMD4<Int> {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, 16, 1, 1), mipmapLevel: 0)
        return SIMD4<Int>(truncatingIfNeeded: value)
    }
    let difference = pixel(8) &- pixel(24)
    #expect(abs(difference.x) < 12 && abs(difference.y) < 12 && abs(difference.z) < 12, "stitched \(pixel(8)), plain \(pixel(24))")
}
