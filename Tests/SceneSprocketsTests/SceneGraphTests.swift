@testable import SceneSprockets
import simd
import Testing

@Test
func testEmptySceneGraph() {
    let root = SceneGraph.Node()
    let sceneGraph = SceneGraph(root: root)
    let nodes = sceneGraph.nodesWithWorldTransforms()
    #expect(nodes.count == 1)
}

@Test
func testHierarchyTraversal() {
    let root = SceneGraph.Node(label: "root")
    let child1 = root.addChild(SceneGraph.Node(label: "child1"))
    root.addChild(SceneGraph.Node(label: "child2"))

    child1.addChild(SceneGraph.Node(label: "grandchild"))

    let sceneGraph = SceneGraph(root: root)
    let nodes = sceneGraph.nodesWithWorldTransforms()
    #expect(nodes.count == 4)
}

@Test
func traversalIsDepthFirstAndAccumulatesTransforms() {
    func translation(_ x: Float, _ y: Float, _ z: Float) -> float4x4 {
        float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
    }
    let root = SceneGraph.Node(label: "root", transform: translation(1, 0, 0))
    let a = root.addChild(SceneGraph.Node(label: "a", transform: translation(0, 2, 0)))
    a.addChild(SceneGraph.Node(label: "a1", transform: translation(0, 0, 3)))
    root.addChild(SceneGraph.Node(label: "b", transform: float4x4(diagonal: [2, 2, 2, 1])))

    let nodes = SceneGraph(root: root).nodesWithWorldTransforms()
    #expect(nodes.map(\.node.label) == ["root", "a", "a1", "b"])
    #expect(nodes[2].worldTransform.columns.3 == SIMD4<Float>(1, 2, 3, 1))
    #expect(nodes[3].worldTransform.columns.0.x == 2)
    #expect(nodes[2].worldTransform == nodes[2].node.worldTransform)
}

@Test
func testLightNodeQuery() {
    let root = SceneGraph.Node(label: "root")
    root.addChild(SceneGraph.Node(label: "light", content: .light(Light(type: .point))))
    root.addChild(SceneGraph.Node(label: "empty"))

    let sceneGraph = SceneGraph(root: root)
    let lights = sceneGraph.lightNodes()
    #expect(lights.count == 1)
    #expect(lights[0].light.type == .point)
}
