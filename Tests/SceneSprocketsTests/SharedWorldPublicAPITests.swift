import SceneSprockets
import SwiftECS
import Testing
import simd

// #269: only the public API, so this file fails to compile if any of it is missing.

private struct Velocity: Component {
    var value: SIMD3<Float>
}

@Test
func appOwnedWorldHoldsTheGraphsNodes() throws {
    let world = World()
    let root = SceneGraph.Node(label: "Root")
    let child = SceneGraph.Node(parent: root, transform: simd_float4x4(translation: [1, 0, 0]))
    let graph = SceneGraph(root: root, world: world)
    #expect(graph.world === world)

    let entity = try #require(world[child.id])
    #expect(entity[NodeTransformComponent.self]?.value.matrix.columns.3.x == 1)
    #expect(entity[NodeLabelComponent.self] != nil)
    #expect(entity[SceneGraphMembershipComponent.self]?.rootID == root.id)
    #expect(entity[NodeReferenceComponent.self]?.node === child)
    #expect(entity[SiblingIndexComponent.self]?.index == 0)

    // An ECS app attaches its own components and edits node components directly.
    entity.set(Velocity(value: [0, 1, 0]))
    entity.set(NodeTransformComponent(value: .matrix(simd_float4x4(translation: [2, 0, 0]))))
    #expect(child.transform.columns.3.x == 2)
    #expect(entity[Velocity.self]?.value == [0, 1, 0])
}

@Test
func ownWorldIsPublicToo() {
    let graph = SceneGraph(root: SceneGraph.Node())
    #expect(graph.world[graph.root.id] != nil)
}
