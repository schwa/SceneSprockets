import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

@MainActor
private func render(_ material: ShaderMaterial) throws -> SIMD4<UInt8> {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: .box(), device: device), material: material)))
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    return value
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func normalsMaterialShowsFrontFaceNormal() throws {
    // The box's front face points at the camera (+Z): normal color (0.5, 0.5, 1).
    let value = try render(.normals())
    #expect(value.x > 200) // Blue (BGRA).
    #expect(abs(Int(value.y) - Int(value.z)) < 10)
    #expect(value.y > 100 && value.y < 220)
}

// Two half-transparent quads over black at the same spot; whichever draws last dominates the blend.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [true, false])
@MainActor
func transparentDrawOrderFollowsRenderingOrder(blueLast: Bool) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let red = root.addChild(SceneGraph.Node(content: .mesh(quad, material: try ShaderMaterial.rim(color: [1, 0, 0, 0.5]))))
    let blue = root.addChild(SceneGraph.Node(trs: .init(translation: [0, 0, 0.1]), content: .mesh(quad, material: try ShaderMaterial.rim(color: [0, 0, 1, 0.5]))))
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

// #96: with equal rendering order, the nearer transparent quad draws last and dominates, whatever the scene order.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [true, false])
@MainActor
func transparentEntriesDrawBackToFront(nearFirstInScene: Bool) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let near = SceneGraph.Node(trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: try ShaderMaterial.rim(color: [1, 0, 0, 0.5])))
    let far = SceneGraph.Node(content: .mesh(quad, material: try ShaderMaterial.rim(color: [0, 0, 1, 0.5])))
    for node in nearFirstInScene ? [near, far] : [far, near] {
        root.addChild(node)
    }
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    // BGRA: z is red (near).
    #expect(Int(value.z) > Int(value.x) + 30)
}

@Test
@MainActor
func opaqueDrawsBeforeTransparentInABatch() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    let camera = root.addChild(SceneGraph.Node(trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    _ = camera
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let glass = root.addChild(SceneGraph.Node(content: .mesh(quad, material: try ShaderMaterial.rim(color: [1, 0, 0, 0.5]))))
    let solid = root.addChild(SceneGraph.Node(content: .mesh(quad, material: try ShaderMaterial.normals())))
    let sceneGraph = SceneGraph(root: root)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let batches = renderBatches(sceneGraph.meshEntries(), context: context)
    #expect(batches.map { $0.entries.map(\.node) }.flatMap(\.self).map { $0 === solid } == [true, false])
    _ = glass
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func rimMaterialUsesColorParameter() throws {
    let value = try render(.rim(color: [1, 0, 0, 1]))
    #expect(value.z > 200) // Red, fully facing the camera.
    #expect(value.x < 10 && value.y < 10)
}
