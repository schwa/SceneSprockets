import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

// #46
@Test
func levelOfDetailPicksMeshByDistance() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let full = MetalMesh(mesh: .sphere(), device: device)
    let simple = MetalMesh(mesh: .box(), device: device)
    let node = SceneGraph.Node(content: .mesh(full, material: try ShaderMaterial.normals()))
    node.levelsOfDetail = [.init(mesh: simple, distance: 10), .init(mesh: nil, distance: 50)]
    let entries = SceneGraph(root: node).meshEntries()
    #expect(applyLevelsOfDetail(entries, cameraPosition: [0, 0, 5]).first?.mesh.vertexBuffer === full.vertexBuffer)
    #expect(applyLevelsOfDetail(entries, cameraPosition: [0, 0, 20]).first?.mesh.vertexBuffer === simple.vertexBuffer)
    #expect(applyLevelsOfDetail(entries, cameraPosition: [0, 0, 60]).isEmpty)
}

@Test
@MainActor
func levelOfDetailAppliesWhenRendering() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 20]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(10)))))
    let node = SceneGraph.Node(parent: root, content: .mesh(MetalMesh(mesh: .box(), device: device), material: try ShaderMaterial.normals()))
    func centerPixel() throws -> SIMD4<UInt8> {
        let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
        let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
        return value
    }
    #expect(try centerPixel().x > 100)
    node.levelsOfDetail = [.init(mesh: nil, distance: 15)]
    #expect(try centerPixel().x < 5)
}
