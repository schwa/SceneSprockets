import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsShaderMaterial
import Testing

// BGRA pixels of a 32x32 render, camera at z = 4 looking at the origin.
@MainActor
private func render(_ cloud: PointCloud) throws -> [SIMD4<UInt8>] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    root.addChild(try cloud.makeNode(device: device))
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: 32 * 32)
    texture.getBytes(&pixels, bytesPerRow: 32 * 4, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
    return pixels
}

@Test
@MainActor
func pointDrawsAsARoundDotOfItsSizeAndColor() throws {
    let pixels = try render(PointCloud(points: [.init(position: .zero, color: [1, 0, 0, 1])], pointSize: 8))
    let red = pixels.filter { $0.z > 200 && $0.x < 50 && $0.y < 50 }
    // A round dot 8 pixels across covers about 50 pixels; a square would cover 64.
    #expect(red.count > 30 && red.count < 64)
    // Centered: the middle pixel is red.
    #expect(pixels[16 * 32 + 16].z > 200)
}

@Test
@MainActor
func emptyCloudMakesAnEmptyNode() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = try PointCloud(points: []).makeNode(device: device)
    guard case .empty = node.content else {
        Issue.record("The node has content")
        return
    }
}

@Test
func translucentPointsMakeATransparentMaterial() throws {
    #expect(try PointCloud(points: [.init(position: .zero)]).makeMaterial().isTransparent == false)
    #expect(try PointCloud(points: [.init(position: .zero, color: [1, 1, 1, 0.5])]).makeMaterial().isTransparent)
}
