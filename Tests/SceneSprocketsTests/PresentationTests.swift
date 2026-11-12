import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #387: an immutable per-frame snapshot of what rendering reads.

@MainActor
private func makeGraph() throws -> (SceneGraph, mesh: SceneGraph.Node, light: SceneGraph.Node, label: SceneGraph.Node) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    let mesh = root.addChild(SceneGraph.Node(transform: .init(translation: [1, 2, 3]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: ShaderMaterialStub())))
    mesh.categoryBitMask = 0b10
    mesh.renderingOrder = 4
    let light = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 5, 0]), content: .light(Light(type: .point))))
    light.lightCategoryBitMask = 0b100
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 9]), content: .camera(Camera(projection: PerspectiveProjection()))))
    let label = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 1, 0])))
    label.text = SceneText("Hi")
    return (SceneGraph(root: root), mesh, light, label)
}

private struct ShaderMaterialStub: SceneMaterial {}

@Test
@MainActor
func presentationMatchesTheLiveGraph() throws {
    let (graph, mesh, light, label) = try makeGraph()
    let presentation = graph.presentation()
    #expect(presentation.revision == graph.revision)
    let entry = try #require(presentation.meshes.first)
    #expect(entry.nodeID == mesh.id)
    #expect(entry.worldTransform == mesh.worldTransform)
    #expect(entry.categoryBitMask == 0b10)
    #expect(entry.renderingOrder == 4)
    #expect(entry.meshBounds == mesh.meshBounds)
    #expect(presentation.lights.map(\.nodeID) == [light.id])
    #expect(presentation.lights.first?.lightCategoryBitMask == 0b100)
    #expect(presentation.cameras.count == 1)
    #expect(presentation.texts.map(\.text) == [SceneText("Hi")])
    #expect(presentation.texts.first?.worldTransform == label.worldTransform)
    #expect(presentation.bounds == graph.bounds)
}

@Test
@MainActor
func presentationIsReusedUntilTheRevisionChanges() throws {
    let (graph, mesh, _, label) = try makeGraph()
    _ = graph.presentation()
    let traversals = graph.traversalCount
    _ = graph.presentation()
    #expect(graph.traversalCount == traversals)
    mesh.transform = .init(translation: [7, 0, 0])
    #expect(graph.presentation().meshes.first?.worldTransform.columns.3 == [7, 0, 0, 1])
    // Text and particle systems bump the revision too, so the snapshot sees them.
    label.text = SceneText("Bye")
    #expect(graph.presentation().texts.map(\.text) == [SceneText("Bye")])
}

@Test
@MainActor
func presentationKeepsItsValuesWhenTheGraphChanges() throws {
    let (graph, mesh, _, _) = try makeGraph()
    let presentation = graph.presentation()
    mesh.transform = .init(translation: [-1, -1, -1])
    mesh.categoryBitMask = 1
    mesh.removeFromParent()
    let entry = try #require(presentation.meshes.first)
    #expect(entry.worldTransform.columns.3 == [1, 2, 3, 1])
    #expect(entry.categoryBitMask == 0b10)
}

// #388: SceneGraphElement draws the snapshot, not the live graph.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func sceneGraphElementDrawsTheSnapshot() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection()))))
    let box = root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: .box(), device: device), material: BlinnPhongSceneMaterial(ambient: .color(1), diffuse: .color(1), specular: .color(0), shininess: 1))))
    let graph = SceneGraph(root: root)
    graph.environment.background = .color([0, 0, 0, 1])
    let presentation = graph.presentation()
    // Gone from the live graph after the snapshot was made.
    box.removeFromParent()
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let texture = try renderer.render(SceneGraphElement(presentation: presentation, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1])])).texture
    var center = SIMD4<UInt8>.zero
    texture.getBytes(&center, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    #expect(center.x > 100, "\(center)")
}
