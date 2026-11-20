@testable import SceneSprockets
import Testing

// #593: the per-field lists must agree.

@Test
func everyNodeFieldStorageHasAWorldField() {
    let storageCount = Mirror(reflecting: SceneGraph.Node()).children.count { child in
        String(describing: type(of: child.value)).hasPrefix("NodeFieldStorage<")
    }
    #expect(storageCount == SceneGraph.Node.worldFields.count)
    let componentTypes = SceneGraph.Node.worldFields.map { "\($0.componentType)" }
    #expect(Set(componentTypes).count == componentTypes.count)
}

@Test
func everyArchiveKeyBelongsToOneField() {
    let fieldKeys = SceneGraph.Node.worldFields.flatMap(\.archiveKeys)
    #expect(Set(fieldKeys).count == fieldKeys.count)
    // Not fields: the subtree and a loaded model's file.
    let otherKeys: Set<SceneGraph.Node.ArchiveKeys> = [.children, .model]
    #expect(Set(fieldKeys).union(otherKeys) == Set(SceneGraph.Node.ArchiveKeys.allCases))
}

@Test
func cloneCopiesWorldFields() {
    let node = SceneGraph.Node(label: "a")
    node.opacity = 0.5
    node.renderingOrder = 3
    node.actionSpeed = 2
    node.categoryBitMask = 4
    node.morphWeights = [0.25]
    let copy = node.clone()
    #expect(copy.label == "a")
    #expect(copy.opacity == 0.5)
    #expect(copy.renderingOrder == 3)
    #expect(copy.actionSpeed == 2)
    #expect(copy.categoryBitMask == 4)
    #expect(copy.morphWeights == [0.25])
}
