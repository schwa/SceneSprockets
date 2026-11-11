import Foundation
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftECS
import Testing

// #280: archive and clone read node fields through the World when the node is in a graph.

private struct AppTag: Component {
    var value: Int
}

// Values set after the graph exists, so they live only in the World.
private func makeGraphEditedInPlace() -> (SceneGraph, SceneGraph.Node) {
    let root = SceneGraph.Node(label: "Root")
    let graph = SceneGraph(root: root)
    let material = BlinnPhongSceneMaterial(
        ambient: .color(0.1), diffuse: .color(0.5), specular: .color(0.3), shininess: 24
    )
    let box = root.addChild(SceneGraph.Node(shape: .box(), material: material))
    let child = box.addChild(SceneGraph.Node(label: "Child"))
    box.label = "Box"
    box.transform = .init(translation: [1, 2, 3])
    box.pivot = simd_float4x4(translation: [0.5, 0, 0])
    box.opacity = 0.25
    box.categoryBitMask = 6
    box.lightCategoryBitMask = 9
    box.renderingOrder = 4
    box.isVisible = false
    box.actionSpeed = 2
    box.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 1))
    box.morphWeights = [0.5]
    child.isActive = false
    graph.world[box.id]?.set(AppTag(value: 42))
    return (graph, box)
}

private func expectEditedValues(_ box: SceneGraph.Node) {
    #expect(box.label == "Box")
    #expect(simd_distance(box.transform.translation, [1, 2, 3]) < 1e-5)
    #expect(box.pivot == simd_float4x4(translation: [0.5, 0, 0]))
    #expect(box.opacity == 0.25)
    #expect(box.categoryBitMask == 6)
    #expect(box.lightCategoryBitMask == 9)
    #expect(box.renderingOrder == 4)
    #expect(box.isVisible == false)
    #expect(box.actionSpeed == 2)
    #expect(box.physicsBody == .init(type: .dynamic, shape: .sphere(radius: 1)))
    #expect(box.morphWeights == [0.5])
    #expect(box.children.map(\.label) == ["Child"])
    #expect(box.children.first?.isActive == false)
}

@Test
func archiveRoundTripsValuesStoredInTheWorld() throws {
    let (graph, _) = makeGraphEditedInPlace()
    let archive = SceneArchive(materialTypes: [BlinnPhongSceneMaterial.self])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(SceneArchive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let warnings = try archive.write(graph, to: url)
    #expect(warnings.isEmpty, "\(warnings)")

    let (loaded, _) = try archive.read(from: url)
    let box = try #require(loaded.root.children.first)
    expectEditedValues(box)
    // The loaded nodes are in the loaded graph's World. App components are not part of the archive.
    #expect(box.world === loaded.world)
    #expect(loaded.world[box.id]?[AppTag.self] == nil)
}

@Test
func cloneCopiesValuesStoredInTheWorld() {
    let (graph, box) = makeGraphEditedInPlace()
    let copy = box.clone()
    #expect(copy.world == nil)
    #expect(copy.id != box.id)
    expectEditedValues(copy)

    graph.root.addChild(copy)
    #expect(copy.world === graph.world)
    expectEditedValues(copy)
    // clone() copies node fields, not app components; the original keeps its own.
    #expect(graph.world[copy.id]?[AppTag.self] == nil)
    #expect(graph.world[box.id]?[AppTag.self]?.value == 42)
}
