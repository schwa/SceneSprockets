import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #95: SceneGraphElement multisamples the scene pass.
@MainActor
private func edgePixelCount(sampleCount: Int) throws -> Int {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let white = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(1))
    let root = SceneGraph.Node()
    // Turned 30° so its edges are not aligned with the pixel grid.
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: .pi / 6, axis: [0, 0, 1])), content: .mesh(MetalMesh(mesh: .box(), device: device), material: white)))
    let camera = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    let sceneGraph = SceneGraph(linearRoot: root)
    let renderer = try OffscreenRenderer(size: CGSize(width: 64, height: 64))
    let element = SceneGraphElement(sceneGraph: sceneGraph, camera: camera, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], sampleCount: sampleCount)
    let texture = try renderer.render(element).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: 64 * 64)
    texture.getBytes(&pixels, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
    return pixels.count { (20...235).contains($0.x) }
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func multisamplingSmoothsEdges() throws {
    #expect(try edgePixelCount(sampleCount: 1) < 5)
    #expect(try edgePixelCount(sampleCount: 4) > 20)
}
