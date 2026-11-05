import SwiftECS

// Hierarchy edits made directly in the World update the node tree (#273). SceneGraph's own edits run inside
// writeFromNode, so they are skipped here.
extension SceneGraph.NodeStore {
    // Direct ChildOf edits move the node: last among its new siblings, or out of the graph when unparented, like
    // removeFromParent(). Edges to entities without a Node are ignored.
    func handleChildOf(_ event: RelationshipEvent) {
        guard nodeWriteDepth == 0 else {
            return
        }
        switch event {
        case let .added(source, target):
            guard let child = nodes[source]?.node, let parent = nodes[target]?.node, child.parent !== parent else {
                return
            }
            writeFromNode { parent.addChild(child) }
        case let .removed(source, target):
            // Replacing a parent removes the old edge after the new one exists; only a real unparent is handled.
            guard let child = nodes[source]?.node, child.parent?.id == target, world[source]?.parent == nil else {
                return
            }
            writeFromNode { child.removeFromParent() }
        }
    }

    // A direct sibling-index write re-sorts the parent's children; ties keep their current order.
    func handleSiblingIndex(_ event: ComponentEvent<SiblingIndexComponent>) {
        guard nodeWriteDepth == 0, case let .changed(entity, _) = event,
              let parent = entity[NodeReferenceComponent.self]?.node?.parent else {
            return
        }
        writeFromNode { parent.sortChildrenBySiblingIndex() }
    }
}
