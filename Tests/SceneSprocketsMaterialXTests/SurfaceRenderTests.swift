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
