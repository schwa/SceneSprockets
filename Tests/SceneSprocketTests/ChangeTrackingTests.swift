import Testing
import simd
@testable import SceneSprocket

@Test
func transformChangeBumpsOnlyTransformRevision() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    let grandchild = SceneGraph.Node(parent: child)
    let sceneGraph = SceneGraph(root: root)
    let before = sceneGraph.revision

    grandchild.trs.translation = [1, 0, 0]

    #expect(sceneGraph.revision.transform != before.transform)
    #expect(sceneGraph.revision.structure == before.structure)
}

@Test
func hierarchyAndContentChangesBumpStructureRevision() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    let sceneGraph = SceneGraph(root: root)

    var before = sceneGraph.revision
    child.addChild(SceneGraph.Node())
    #expect(sceneGraph.revision.structure != before.structure)

    before = sceneGraph.revision
    child.content = .light(Light(type: .point))
    #expect(sceneGraph.revision.structure != before.structure)

    before = sceneGraph.revision
    child.removeFromParent()
    #expect(sceneGraph.revision.structure != before.structure)
}

@Test
func detachedNodeChangesDoNotAffectGraph() {
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    let sceneGraph = SceneGraph(root: root)
    child.removeFromParent()
    let before = sceneGraph.revision

    child.transform = matrix_identity_float4x4
    child.content = .empty

    #expect(sceneGraph.revision == before)
}

@Test
func replacingRootBumpsStructureRevision() {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    let before = sceneGraph.revision
    sceneGraph.root = SceneGraph.Node()
    #expect(sceneGraph.revision.structure != before.structure)
}
