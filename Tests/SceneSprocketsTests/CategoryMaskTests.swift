import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

private var material: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color([0.5, 0.5, 0.5]), diffuse: .color([0.5, 0.5, 0.5]), specular: .color(0), shininess: 1)
}

private func scene(cameraMask: UInt = .max) throws -> (SceneGraph, box: SceneGraph.Node) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let mesh = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)), categoryBitMask: cameraMask)))
    let box = SceneGraph.Node(parent: root, content: .mesh(mesh, material: material))
    return (SceneGraph(root: root), box)
}

@Test
@MainActor
func cameraMaskHidesNodes() throws {
    let (sceneGraph, box) = try scene(cameraMask: 0b01)
    box.categoryBitMask = 0b10
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    #expect(value.x < 3 && value.y < 3 && value.z < 3)
}

// Regression for #99: a Blinn-Phong batch that no light reaches hit an assertion in Lighting.
@Test
@MainActor
func blinnPhongDrawsMeshesNoLightReaches() throws {
    let (sceneGraph, _) = try scene()
    let light = SceneGraph.Node(parent: sceneGraph.root, content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1)))
    light.lightCategoryBitMask = 0b10
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1])])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    // Ambient only.
    #expect(value.x > 20)
}

@Test
func hitTestRespectsMask() throws {
    let (sceneGraph, box) = try scene()
    box.categoryBitMask = 0b10
    let ray = Ray3D(origin: [0, 0, 4], direction: [0, 0, -1])
    #expect(!sceneGraph.hitTest(ray).isEmpty)
    #expect(sceneGraph.hitTest(ray, categoryBitMask: 0b01).isEmpty)
    #expect(!sceneGraph.hitTest(ray, categoryBitMask: 0b10).isEmpty)
}

@Test
func batchesFilterLightsAndSortByRenderingOrder() throws {
    let (sceneGraph, box) = try scene()
    let root = sceneGraph.root
    let device = try #require(MTLCreateSystemDefaultDevice())
    let overlay = SceneGraph.Node(parent: root, content: .mesh(MetalMesh(mesh: .box(), device: device), material: material))
    overlay.renderingOrder = -1
    overlay.categoryBitMask = 0b10
    let everything = SceneGraph.Node(parent: root, content: .light(Light(type: .point)))
    let onlyTwo = SceneGraph.Node(parent: root, content: .light(Light(type: .directional)))
    onlyTwo.lightCategoryBitMask = 0b10
    _ = everything

    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let batches = renderBatches(sceneGraph.meshEntries(), context: context)
    #expect(batches.count == 2)
    #expect(batches[0].entries.allSatisfy { $0.node === overlay })
    #expect(batches[0].context.lights.count == 2)
    #expect(batches[1].entries.allSatisfy { $0.node === box })
    #expect(batches[1].context.lights.map(\.light.type) == [.point])
}
