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
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
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

// #431: vertexColors draws each vertex's color, unlit, including line primitives.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func vertexColorsMaterialDrawsColoredLines() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // A horizontal red line and a vertical green one through the center.
    let positions: [SIMD3<Float>] = [[-1, 0, 0], [1, 0, 0], [0, -1, 0], [0, 1, 0]]
    let colors: [SIMD4<Float>] = [[1, 0, 0, 1], [1, 0, 0, 1], [0, 1, 0, 1], [0, 1, 0, 1]]
    let zeros = [SIMD3<Float>](repeating: .zero, count: 4)
    let mesh = MetalMesh(device: device, attributes: [.positions(positions), .normals(zeros), .textureCoordinates(Array(repeating: .zero, count: 4)), .colors(colors)], submeshes: [.init(indices: [0, 1, 2, 3], primitiveType: .line)])
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    root.addChild(SceneGraph.Node(content: .mesh(mesh, material: ShaderMaterial.vertexColors())))
    let size = 32
    let texture = try OffscreenRenderer(size: CGSize(width: size, height: size)).render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    // BGRA: red is z, green is y.
    #expect(pixels.contains { $0.z > 200 && $0.y < 50 }, "a red line")
    #expect(pixels.contains { $0.y > 200 && $0.z < 50 }, "a green line")
    #expect(pixels.count { $0.y > 100 || $0.z > 100 } < size * 4, "only thin lines")
}

// Two half-transparent quads over black at the same spot; whichever draws last dominates the blend.
@Test(.enabled(if: deviceSupportsMetal4), arguments: [true, false])
@MainActor
func transparentDrawOrderFollowsRenderingOrder(blueLast: Bool) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let red = root.addChild(SceneGraph.Node(content: .mesh(quad, material: ShaderMaterial.rim(color: [1, 0, 0], opacity: 0.5))))
    let blue = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 0.1]), content: .mesh(quad, material: ShaderMaterial.rim(color: [0, 0, 1], opacity: 0.5))))
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
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let near = SceneGraph.Node(transform: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: ShaderMaterial.rim(color: [1, 0, 0], opacity: 0.5)))
    let far = SceneGraph.Node(content: .mesh(quad, material: ShaderMaterial.rim(color: [0, 0, 1], opacity: 0.5)))
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
    let camera = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    _ = camera
    let quad = MetalMesh(mesh: .quad(extents: [2, 2]), device: device)
    let glass = root.addChild(SceneGraph.Node(content: .mesh(quad, material: ShaderMaterial.rim(color: [1, 0, 0], opacity: 0.5))))
    let solid = root.addChild(SceneGraph.Node(content: .mesh(quad, material: ShaderMaterial.normals())))
    let sceneGraph = SceneGraph(root: root)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let batches = renderBatches(sceneGraph.meshEntries(), context: context)
    #expect(batches.map { $0.entries.map(\.node) }.flatMap(\.self).map { $0 === solid } == [true, false])
    _ = glass
}

// #377: shader materials cull with MaterialRenderState.cullMode, like Blinn-Phong. The box's front face points at the
// camera (+Z normal, blue); culling it shows the inside of the back face (-Z normal, no blue).
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func shaderMaterialCullsFaces() throws {
    var material = ShaderMaterial.normals()
    material.renderState.cullMode = .back
    #expect(try render(material).x > 200)
    material.renderState.cullMode = .front
    #expect(try render(material).x < 10)
}

// #374: the alpha-blending setting reads back what was set; isTransparent is derived from it and the blend mode.
@Test
func alphaBlendingReadsBackAndTransparencyIsDerived() {
    var material = ShaderMaterial.normals()
    material.renderState.blendMode = .add
    material.usesAlphaBlending = false
    #expect(material.usesAlphaBlending == false)
    #expect(material.isTransparent) // Add blends with the background.
    material.renderState.blendMode = .alpha
    #expect(!material.isTransparent)
    material.usesAlphaBlending = true
    #expect(material.usesAlphaBlending)
    #expect(material.isTransparent)
    #expect(ShaderMaterial.rim(color: [1, 0, 0], opacity: 0.5).usesAlphaBlending)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func rimMaterialUsesColorParameter() throws {
    let value = try render(.rim(color: [1, 0, 0]))
    #expect(value.z > 200) // Red, fully facing the camera.
    #expect(value.x < 10 && value.y < 10)
}
