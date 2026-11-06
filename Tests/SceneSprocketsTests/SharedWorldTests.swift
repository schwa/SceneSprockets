@testable import SceneSprockets
import simd
import SwiftECS
import Testing

// #269: several graphs in one World, and graph lifetime.

@Test
func twoGraphsShareAWorldWithoutCrossTalk() throws {
    let world = World()
    let firstChild = SceneGraph.Node()
    let first = SceneGraph(root: SceneGraph.Node(children: [firstChild]), world: world)
    let secondChild = SceneGraph.Node()
    let second = SceneGraph(root: SceneGraph.Node(children: [secondChild]), world: world)
    #expect(world[firstChild.id]?[SceneGraphMembershipComponent.self]?.rootID == first.root.id)
    #expect(world[secondChild.id]?[SceneGraphMembershipComponent.self]?.rootID == second.root.id)

    // A direct write to one graph's node bumps only that graph.
    let firstBefore = first.revision
    let secondBefore = second.revision
    try #require(world[firstChild.id]).set(NodeOpacityComponent(value: 0.5))
    #expect(first.revision.transform != firstBefore.transform)
    #expect(second.revision == secondBefore)

    // Destroying one graph's entity only affects that graph.
    _ = try world.destroy(try #require(world[firstChild.id]))
    #expect(first.root.children.isEmpty)
    #expect(second.root.children.map(\.id) == [secondChild.id])
}

@Test
func freeingAGraphRemovesItsEntitiesFromAnAppWorld() {
    let world = World()
    let root = SceneGraph.Node()
    let child = SceneGraph.Node(parent: root)
    var graph: SceneGraph? = SceneGraph(root: root, world: world)
    #expect(world[child.id] != nil)
    _ = graph
    graph = nil
    #expect(world[child.id] == nil)
    #expect(world[root.id] == nil)
    #expect(child.world == nil)
}
