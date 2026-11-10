import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

private var material: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
}

@Test
func hiddenNodeHidesSubtree() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let group = root.addChild(SceneGraph.Node(label: "group"))
    group.addChild(SceneGraph.Node(label: "child", content: .mesh(box, material: material)))
    group.addChild(SceneGraph.Node(label: "light", content: .light(Light(type: .point))))
    root.addChild(SceneGraph.Node(label: "other", content: .mesh(box, material: material)))
    let sceneGraph = SceneGraph(root: root)
    #expect(sceneGraph.meshEntries().count == 2)

    let before = sceneGraph.revision
    group.isVisible = false
    #expect(sceneGraph.revision.structure != before.structure)
    #expect(sceneGraph.meshEntries().map(\.node.label) == ["other"])
    #expect(sceneGraph.lightNodes().isEmpty)
    #expect(sceneGraph.nodesWithWorldTransforms().map(\.node.label) == [nil, "other"])
    #expect(sceneGraph.nodesWithWorldTransforms(includeHidden: true).count == 5)
}

@Test
func hiddenNodesAreExcludedFromBounds() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let far = root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    far.trs.translation = [10, 0, 0]
    root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    let sceneGraph = SceneGraph(root: root)
    #expect(sceneGraph.bounds?.max.x == 10.5)

    far.isVisible = false
    #expect(sceneGraph.bounds?.max.x == 0.5)
    #expect(sceneGraph.worldBounds(of: far) == nil)
}
