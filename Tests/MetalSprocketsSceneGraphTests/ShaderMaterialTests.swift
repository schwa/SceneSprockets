import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

@MainActor
private func render(_ material: ShaderMaterial) throws -> SIMD4<UInt8> {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    _ = SceneGraph.Node(parent: root, content: .mesh(MetalMesh(mesh: .box(), device: device), material: material))
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    return value
}

@Test
@MainActor
func normalsMaterialShowsFrontFaceNormal() throws {
    // The box's front face points at the camera (+Z): normal color (0.5, 0.5, 1).
    let value = try render(.normals())
    #expect(value.x > 200) // Blue (BGRA).
    #expect(abs(Int(value.y) - Int(value.z)) < 10)
    #expect(value.y > 100 && value.y < 220)
}

// Two half-transparent quads over black at the same spot; whichever draws last dominates the blend.
@Test(arguments: [true, false])
@MainActor
func transparentDrawOrderFollowsRenderingOrder(blueLast: Bool) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let red = SceneGraph.Node(parent: root, content: .mesh(quad, material: try ShaderMaterial.rim(color: [1, 0, 0, 0.5])))
    let blue = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0.1]), content: .mesh(quad, material: try ShaderMaterial.rim(color: [0, 0, 1, 0.5])))
    red.renderingOrder = blueLast ? 1 : 2
    blue.renderingOrder = blueLast ? 2 : 1
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    // BGRA: x is blue, z is red.
    if blueLast {
        #expect(Int(value.x) > Int(value.z) + 30)
    } else {
        #expect(Int(value.z) > Int(value.x) + 30)
    }
}

@Test
@MainActor
func rimMaterialUsesColorParameter() throws {
    let value = try render(.rim(color: [1, 0, 0, 1]))
    #expect(value.z > 200) // Red, fully facing the camera.
    #expect(value.x < 10 && value.y < 10)
}
