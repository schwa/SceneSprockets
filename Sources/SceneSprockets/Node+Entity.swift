import SwiftECS

// A node under a SceneGraph's root stores these in the graph's World (#265). A node outside any graph keeps them
// itself and has no entity.
struct NodeTransformComponent: Component {
    var localTransform: SceneGraph.LocalTransform
}

struct NodeContentComponent: Component {
    var content: SceneGraph.Node.Content
}

// ChildOf does not keep an order we can change, so each child stores its index among its siblings.
struct SiblingIndexComponent: Component {
    var index: Int
}

extension SceneGraph.Node {
    final class EntityBinding {
        let world: World
        // The World's structuralRevision when the refs were made. Any other value means the rows may have moved.
        var revision: UInt64
        var transform: ComponentRef<NodeTransformComponent>
        var content: ComponentRef<NodeContentComponent>

        init?(world: World, id: EntityID) {
            guard let transform = world.componentRef(NodeTransformComponent.self, for: id),
                  let content = world.componentRef(NodeContentComponent.self, for: id) else {
                return nil
            }
            self.world = world
            self.revision = world.structuralRevision
            self.transform = transform
            self.content = content
        }

        // False when the entity or one of its components is gone.
        func refresh(id: EntityID) -> Bool {
            if revision == world.structuralRevision {
                return true
            }
            guard let transform = world.componentRef(NodeTransformComponent.self, for: id),
                  let content = world.componentRef(NodeContentComponent.self, for: id) else {
                return false
            }
            self.transform = transform
            self.content = content
            revision = world.structuralRevision
            return true
        }
    }

    var world: World? {
        currentBinding()?.world
    }

    // Nil when the node is not in a graph. Code outside SceneSprockets can destroy the entity; the node then goes
    // back to local storage with default values.
    func currentBinding() -> EntityBinding? {
        guard let entityBinding else {
            return nil
        }
        if entityBinding.refresh(id: id) {
            return entityBinding
        }
        self.entityBinding = nil
        storedLocalTransform = .matrix(.identity)
        storedContent = .empty
        return nil
    }

    // Gives this node and its subtree entities in `world`. A subtree in another World leaves it first.
    func attach(to world: World, parent: SceneGraph.Node?, siblingIndex: Int) {
        if let binding = currentBinding() {
            if binding.world === world {
                linkInWorld(parent: parent, siblingIndex: siblingIndex)
                return
            }
            detach()
        }
        world.createEntity(
            id: id,
            NodeTransformComponent(localTransform: storedLocalTransform),
            NodeContentComponent(content: storedContent),
            SiblingIndexComponent(index: siblingIndex)
        )
        entityBinding = EntityBinding(world: world, id: id)
        linkInWorld(parent: parent, siblingIndex: siblingIndex)
        for (index, child) in children.enumerated() {
            child.attach(to: world, parent: self, siblingIndex: index)
        }
    }

    // Copies values back to local storage and destroys this subtree's entities.
    func detach() {
        for child in children {
            child.detach()
        }
        guard let binding = currentBinding() else {
            return
        }
        storedLocalTransform = binding.transform.value.localTransform
        storedContent = binding.content.value.content
        entityBinding = nil
        if let entity = binding.world[id] {
            _ = try? binding.world.destroy(entity)
        }
    }

    // Detaches only from `world`, so a subtree that moved to another graph keeps its entities there.
    func detach(from world: World) {
        guard let binding = currentBinding(), binding.world === world else {
            return
        }
        detach()
    }

    private func linkInWorld(parent: SceneGraph.Node?, siblingIndex: Int) {
        guard let binding = currentBinding(), let entity = binding.world[id] else {
            return
        }
        if entity[SiblingIndexComponent.self]?.index != siblingIndex {
            entity.set(SiblingIndexComponent(index: siblingIndex))
        }
        let parentEntity = parent.flatMap { binding.world[$0.id] }
        if entity.parent?.id != parentEntity?.id {
            // ChildOf is acyclic; the node tree already rejects cycles, so this does not throw.
            try? entity.setParent(parentEntity)
        }
    }

    // After `children` changes on an attached node: attaches and renumbers children from `index` on. Appending
    // touches one child.
    func syncChildrenInWorld(from index: Int) {
        guard let binding = currentBinding() else {
            return
        }
        for childIndex in children.indices where childIndex >= index {
            children[childIndex].attach(to: binding.world, parent: self, siblingIndex: childIndex)
        }
    }
}
