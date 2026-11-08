import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import SceneSprockets
import SceneSprocketsAddOns
import Testing

// BGRA pixels of a 32x32 render, camera at z = 4 looking at the origin.
@MainActor
private func render(_ cloud: PointCloud) throws -> [SIMD4<UInt8>] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    root.addChild(try cloud.makeNode(device: device))
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [PointCloudRenderer()])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: 32 * 32)
    texture.getBytes(&pixels, bytesPerRow: 32 * 4, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
    return pixels
}

private var isSupported: Bool {
    MTLCreateSystemDefaultDevice()?.supportsFamily(.apple8) ?? false
}

@Test(.enabled(if: isSupported))
@MainActor
func pointDrawsAsARoundDotOfItsSizeAndColor() throws {
    let pixels = try render(PointCloud(points: [.init(position: .zero, color: [1, 0, 0, 1])], pointSize: 8))
    let red = pixels.filter { $0.z > 200 && $0.x < 50 && $0.y < 50 }
    // A disc 8 pixels across covers about 50 pixels; a square would cover 64.
    #expect(red.count > 30 && red.count < 64)
    #expect(pixels[16 * 32 + 16].z > 200)
}

@Test(.enabled(if: isSupported))
@MainActor
func nodeTransformMovesThePoints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    let cloud = try PointCloud(points: [.init(position: .zero, color: [0, 1, 0, 1])], pointSize: 4).makeNode(device: device)
    cloud.trs.translation = [1, 0, 0]
    root.addChild(cloud)
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [PointCloudRenderer()])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: 32 * 32)
    texture.getBytes(&pixels, bytesPerRow: 32 * 4, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
    let green = pixels.indices.filter { pixels[$0].y > 200 }
    #expect(!green.isEmpty)
    // Moved right of center.
    #expect(green.allSatisfy { $0 % 32 > 18 })
}

@Test
func emptyCloudMakesAnEmptyNode() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = try PointCloud(points: []).makeNode(device: device)
    guard case .empty = node.content else {
        Issue.record("The node has content")
        return
    }
}

@Test
func materialHoldsThePackedPoints() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = try PointCloud(points: [.init(position: [1, 2, 3], color: [1, 0.5, 0, 1])], pointSize: 6, shape: .ring).makeNode(device: device)
    guard case let .mesh(_, materials, _, _) = node.content, let material = materials.first as? PointCloudMaterial else {
        Issue.record("The node has no point cloud material")
        return
    }
    #expect(material.pointCount == 1)
    #expect(material.pointSize == 6)
    #expect(material.shape == .ring)
    let point = material.points.contents().load(as: PointCloudPoint.self)
    #expect(point.position == [1, 2, 3])
    // RGBA8 with red in the lowest byte.
    #expect(point.color == 0xFF00_80FF)
}
