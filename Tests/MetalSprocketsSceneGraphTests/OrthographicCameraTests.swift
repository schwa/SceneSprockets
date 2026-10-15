import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsGLTF
import Testing
import simd
@testable import MetalSprocketsSceneGraph

// #87
@Test
func gltfOrthographicCameraLoads() throws {
    let json = """
    {
      "asset": {"version": "2.0"},
      "scene": 0,
      "scenes": [{"nodes": [0]}],
      "nodes": [{"name": "Camera", "camera": 0}],
      "cameras": [{"type": "orthographic", "orthographic": {"xmag": 4, "ymag": 3, "znear": 0.5, "zfar": 40}}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
    #expect(result.warnings.isEmpty)
    let node = try #require(result.nodes[0])
    guard case let .camera(camera) = node.content else {
        Issue.record("Expected camera content")
        return
    }
    let projection = try #require(camera.projection as? OrthographicProjection)
    #expect(projection.halfHeight == 3)
    #expect(projection.depthMode == .standard(zClip: 0.5 ... 40))
}

// A far-away quad keeps its size under an orthographic camera: 2 units tall in a 4-unit-tall view covers the middle
// half of the image.
@Test
@MainActor
func orthographicCameraRendersWithoutPerspective() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let root = SceneGraph.Node()
    let projection = OrthographicProjection(halfHeight: 2, depthMode: .standard(zClip: 0.1 ... 200))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: projection)))
    let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 1, 1]))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, -100]), content: .mesh(quad, material: material))
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero)])).texture
    func pixel(_ x: Int, _ y: Int) -> SIMD4<UInt8> {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return value
    }
    #expect(pixel(8, 8).x > 200)
    #expect(pixel(5, 8).x > 200)
    #expect(pixel(2, 8).x < 5)
}
