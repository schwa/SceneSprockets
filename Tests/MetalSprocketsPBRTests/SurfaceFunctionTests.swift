import CoreGraphics
import Foundation
import GeometryLite3D
import MaterialX
import MaterialXMetal
import Metal
import MetalSprockets
@testable import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import Testing

// #666: a stitched MaterialX surface function sets a PBR material's shading inputs.
@Suite(.requiresMetal4)
@MainActor
struct SurfaceFunctionTests {
    let models: TestModels
    let size = CGSize(width: 32, height: 32)
    let view = LookAt(position: [0, 0, 3], target: .zero, up: [0, 1, 0]).viewMatrix
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 3), depthMode: .reversed(zClip: 0.1 ... 20)).projectionMatrix(aspectRatio: 1)

    init() throws {
        models = try TestModels()
    }

    static let document = """
    <?xml version="1.0"?>
    <materialx version="1.39">
      <gltf_pbr name="pbr" type="surfaceshader">
        <input name="base_color" type="color3" value="0, 1, 0" />
        <input name="metallic" type="float" value="0" />
        <input name="roughness" type="float" value="0.5" />
      </gltf_pbr>
    </materialx>
    """

    func surfaceFunction() throws -> PBRMaterial.SurfaceFunction {
        let device = models.device
        let document = try MaterialXDocument(data: Data(Self.document.utf8))
        let stitcher = try GraphStitcher(nodeLibrary: MetalNodeLibrary(device: device))
        let shader = try #require(document.nodes.first { $0.name == "pbr" })
        let graph = try stitcher.stitchSurface(shader, in: document, functionName: "test_surface")
        let parameterData = graph.parameterData.isEmpty ? [SIMD4<Float>.zero] : graph.parameterData
        let parameters = try #require(device.makeBuffer(bytes: parameterData, length: MemoryLayout<SIMD4<Float>>.stride * parameterData.count))
        return PBRMaterial.SurfaceFunction(
            function: try VisibleFunction(library: graph.library, name: graph.functionName),
            parameters: parameters,
            textureTable: try StitchedGraph.makeTextureTable([], device: device)
        )
    }

    @Test
    func surfaceFunctionReplacesBaseColor() throws {
        // Both quads' uniforms are red; the left one's surface function makes it green.
        let surface = try surfaceFunction()
        let red = models.material(color: [1, 0, 0, 1])
        let stitched = PBRMaterial(uniforms: red.uniforms, placeholder: models.placeholder, surfaceFunction: surface)
        let model = try models.model([(position: [-0.6, 0, 0], material: stitched), (position: [0.6, 0, 0], material: red)])
        #expect(model.surfaceFunctions.count == 1)
        let scene = PBRScene(model: model, viewMatrix: view, projectionMatrix: projection, viewportSize: size)
        let pixels = try rgbaPixels(OffscreenRenderer(size: size, clearDepth: 0).render(scene).cgImage)
        let width = Int(size.width)
        let middle = Int(size.height) / 2 * width
        let left = pixels[middle + width / 4]
        let right = pixels[middle + width * 3 / 4]
        #expect(Int(left.y) > Int(left.x) + 30, "The stitched quad is green: \(left)")
        #expect(Int(right.x) > Int(right.y) + 30, "The plain quad stays red: \(right)")
    }
}
