import SceneSprockets
@testable import SceneSprocketsComposerSupport
import Testing

// #490: a drag that was cancelled leaves its node in the model; a later drop of other text must not move it.
@MainActor
@Test func dropOfOtherTextMovesNothing() {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "A")
    model.addShape(.box(), label: "B")
    let nodes = model.sceneGraph.root.children
    let (a, b) = (nodes[0], nodes[1])

    // Drag A, then cancel: no drop arrives.
    _ = model.beginTreeDrag(a)
    // Text from another app, dropped on B.
    #expect(!model.dropTreeItems(["A"], onto: b))
    #expect(model.sceneGraph.root.children.map(\.label) == ["A", "B"])

    // A real drag of B onto A still moves it.
    let payload = model.beginTreeDrag(b)
    #expect(model.dropTreeItems([payload], onto: a))
    #expect(model.sceneGraph.root.children.map(\.label) == ["B", "A"])
}
