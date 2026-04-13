import Testing
@testable import MetalSprocketsSceneGraph

@Test
func addChildKeepsParentAndChildrenInSync() {
    let root = SceneGraph.Node(label: "root")
    let child = SceneGraph.Node(label: "child")
    root.addChild(child)
    #expect(child.parent === root)
    #expect(root.children.map(\.label) == ["child"])
}

@Test
func initWithParentAddsToParent() {
    let root = SceneGraph.Node(label: "root")
    let child = SceneGraph.Node(parent: root, label: "child")
    #expect(child.parent === root)
    #expect(root.children.count == 1)
}

@Test
func initWithChildrenSetsTheirParent() {
    let child = SceneGraph.Node(label: "child")
    let root = SceneGraph.Node(children: [child], label: "root")
    #expect(child.parent === root)
}

@Test
func reparentingRemovesFromOldParent() {
    let first = SceneGraph.Node(label: "first")
    let second = SceneGraph.Node(label: "second")
    let child = SceneGraph.Node(parent: first, label: "child")
    second.addChild(child)
    #expect(first.children.isEmpty)
    #expect(second.children.count == 1)
    #expect(child.parent === second)
}

@Test
func removeFromParentClearsBothSides() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    child.removeFromParent()
    #expect(child.parent == nil)
    #expect(root.children.isEmpty)
}

@Test
func insertChildAtIndex() {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, label: "a")
    _ = SceneGraph.Node(parent: root, label: "c")
    root.insertChild(SceneGraph.Node(label: "b"), at: 1)
    #expect(root.children.map(\.label) == ["a", "b", "c"])
}

@Test
func cycleDetection() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    let grandchild = SceneGraph.Node(parent: child)
    #expect(root.isAncestor(of: grandchild))
    #expect(!grandchild.isAncestor(of: root))
    #expect(!root.canAddChild(root))
    #expect(!grandchild.canAddChild(root))
    #expect(root.canAddChild(SceneGraph.Node()))
}
