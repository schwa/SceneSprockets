import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsPBR
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

// #539: stochastic transparency turns alpha into random coverage, drawn with the opaque meshes.
private let size = CGSize(width: 64, height: 64)

// A plane filling the view in front of a white background. Returns the fraction of pixels it covers, at one sample
// (each pixel is covered or not).
@MainActor
private func coverage(_ material: any SceneMaterial) throws -> Double {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 2]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .light(.point(intensity: 40))))
    root.addChild(SceneGraph.Node(shape: .plane(width: 10, height: 10), material: material))
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.background = .color([1, 1, 1, 1])
    let renderer = try OffscreenRenderer(size: size)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer(environmentIntensity: 0), BlinnPhongMaterialRenderer()])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: Int(size.width * size.height))
    texture.getBytes(&pixels, bytesPerRow: Int(size.width) * 4, from: MTLRegionMake2D(0, 0, Int(size.width), Int(size.height)), mipmapLevel: 0)
    // The plane is dark red; the background white: covered pixels have little green.
    let covered = pixels.filter { $0.y < 128 }.count
    return Double(covered) / Double(pixels.count)
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: [Float(0.2), 0.5, 0.8])
@MainActor
func stochasticCoverageFollowsAlpha(alpha: Float) throws {
    var pbr = PBRSceneMaterial(baseColor: [0.8, 0, 0], opacity: alpha, roughness: 1)
    pbr.renderState = PBRRenderState(blendMode: .stochastic)
    #expect(!pbr.isTransparent)
    #expect(pbr.pbrMaterial.usesStochasticTransparency)
    let pbrCoverage = try coverage(pbr)
    #expect(abs(pbrCoverage - Double(alpha)) < 0.1, "PBR coverage \(pbrCoverage) for alpha \(alpha)")

    let blinnPhong = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color([0.8, 0, 0]), specular: .color(0), shininess: 1, opacity: alpha, renderState: MaterialRenderState(blendMode: .stochastic))
    #expect(!blinnPhong.isTransparent)
    let blinnPhongCoverage = try coverage(blinnPhong)
    #expect(abs(blinnPhongCoverage - Double(alpha)) < 0.1, "Blinn-Phong coverage \(blinnPhongCoverage) for alpha \(alpha)")
}

@Test
@MainActor
func stochasticBlendModeIsArchived() throws {
    var material = PBRSceneMaterial(opacity: 0.5)
    material.renderState = PBRRenderState(blendMode: .stochastic)
    let sceneGraph = SceneGraph(linearRoot: SceneGraph.Node(children: [SceneGraph.Node(shape: .box(), material: material)]))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = Archive(materialTypes: [PBRSceneMaterial.self])
    try archive.write(sceneGraph, to: url)
    let (loaded, _) = try archive.read(from: url)
    let node = try #require(loaded.root.children.first)
    guard case let .mesh(_, materials, _, _) = node.content else {
        Issue.record("No mesh")
        return
    }
    #expect((materials.first as? PBRSceneMaterial)?.renderState.blendMode == .stochastic)
}
