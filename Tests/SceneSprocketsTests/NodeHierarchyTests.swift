import Observation
@testable import SceneSprockets
import Testing

@Test
func addChildKeepsParentAndChildrenInSync() {
    let root = SceneGraph.Node(label: "root")
    let child = SceneGraph.Node(label: "child")
    root.addChild(child)
    #expect(child.parent === root)
    #expect(root.children.map(\.label) == ["child"])
}

// #77
@Test
func nodeUtilitiesFindReplaceAndClone() {
    let root = SceneGraph.Node(label: "root")
    let a = root.addChild(SceneGraph.Node(label: "a"))
    let b = root.addChild(SceneGraph.Node(label: "b"))
    let deep = a.addChild(SceneGraph.Node(label: "deep", transform: .init(translation: [1, 2, 3])))
    deep.categoryBitMask = 4
    deep.morphWeights = [0.5]
    #expect(root.childNode(withLabel: "deep") === deep)
    #expect(root.childNode(withLabel: "deep", recursively: false) == nil)

    let replacement = SceneGraph.Node(label: "c")
    root.replaceChild(a, with: replacement)
    #expect(root.children.map(\.label) == ["c", "b"])
    #expect(a.parent == nil)
    _ = b

    let copy = a.clone()
    #expect(copy !== a && copy.parent == nil)
    let copiedDeep = copy.childNode(withLabel: "deep")
    #expect(copiedDeep !== deep)
    #expect(copiedDeep?.transform.translation == [1, 2, 3])
    #expect(copiedDeep?.categoryBitMask == 4)
    #expect(copiedDeep?.morphWeights == [0.5])
    #expect(deep.parent === a)
}

@Test
func traverseCanSkipAndStop() {
    let root = SceneGraph.Node(label: "root")
    let a = root.addChild(SceneGraph.Node(label: "a"))
    a.addChild(SceneGraph.Node(label: "a1"))
    root.addChild(SceneGraph.Node(label: "b"))
    root.addChild(SceneGraph.Node(label: "c"))
    let sceneGraph = SceneGraph(root: root)
    var visited: [String] = []
    sceneGraph.traverse { node, _ in
        visited.append(node.label ?? "")
        switch node.label {
        case "a": return .skipChildren
        case "b": return .stop
        default: return .continue
        }
    }
    #expect(visited == ["root", "a", "b"])
}

@Test
func initWithParentAddsToParent() {
    let root = SceneGraph.Node(label: "root")
    let child = root.addChild(SceneGraph.Node(label: "child"))
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
    let child = first.addChild(SceneGraph.Node(label: "child"))
    second.addChild(child)
    #expect(first.children.isEmpty)
    #expect(second.children.count == 1)
    #expect(child.parent === second)
}

@Test
func removeFromParentClearsBothSides() {
    let root = SceneGraph.Node()
    let child = root.addChild(SceneGraph.Node())
    child.removeFromParent()
    #expect(child.parent == nil)
    #expect(root.children.isEmpty)
}

@Test
func insertChildAtIndex() {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(label: "a"))
    root.addChild(SceneGraph.Node(label: "c"))
    root.insertChild(SceneGraph.Node(label: "b"), at: 1)
    #expect(root.children.map(\.label) == ["a", "b", "c"])
}

@Test
func cycleDetection() {
    let root = SceneGraph.Node()
    let child = root.addChild(SceneGraph.Node())
    let grandchild = child.addChild(SceneGraph.Node())
    #expect(root.isAncestor(of: grandchild))
    #expect(!grandchild.isAncestor(of: root))
    #expect(!root.canAddChild(root))
    #expect(!grandchild.canAddChild(root))
    #expect(root.canAddChild(SceneGraph.Node()))
}

// #486: a node is found from its ID without walking the scene.
@Test
func nodeIsFoundByID() {
    let root = SceneGraph.Node()
    let child = root.addChild(SceneGraph.Node())
    let hidden = child.addChild(SceneGraph.Node())
    hidden.isVisible = false
    let sceneGraph = SceneGraph(root: root)
    #expect(sceneGraph.node(withID: root.id) === root)
    #expect(sceneGraph.node(withID: hidden.id) === hidden)

    // Added and removed after the graph was made.
    let late = child.addChild(SceneGraph.Node())
    #expect(sceneGraph.node(withID: late.id) === late)
    late.removeFromParent()
    #expect(sceneGraph.node(withID: late.id) == nil)

    // Not in this graph.
    let other = SceneGraph.Node()
    _ = SceneGraph(root: other)
    #expect(sceneGraph.node(withID: other.id) == nil)
    #expect(sceneGraph.node(withID: SceneGraph.Node().id) == nil)
}

// #486: a view that looks up a node must not depend on the other nodes.
@Test
func lookupByIDDoesNotObserveOtherNodes() {
    let root = SceneGraph.Node()
    let selected = root.addChild(SceneGraph.Node())
    let other = root.addChild(SceneGraph.Node())
    let sceneGraph = SceneGraph(root: root)
    nonisolated(unsafe) var fired = false
    withObservationTracking {
        _ = sceneGraph.node(withID: selected.id)
    } onChange: {
        fired = true
    }
    other.transform.translation.x += 1
    #expect(!fired)
}
