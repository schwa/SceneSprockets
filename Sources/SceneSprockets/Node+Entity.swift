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

// Finds the node for an entity, so writes made directly to the World can reach it.
struct NodeReferenceComponent: Component {
    weak var node: SceneGraph.Node?
}

extension SceneGraph {
    // The World behind a scene graph. Turns component changes made directly in the World into the same revision
    // bumps and Observation notifications that Node's setters make (#266).
    final class NodeStore {
        let world = World()
        // Above 0 while a Node setter writes, so its own change event is not handled twice.
        var nodeWriteDepth = 0

        init() {
            world.observe(NodeTransformComponent.self) { [weak self] event in
                self?.handle(event, keyPath: \.localTransform, structure: false)
            }
            world.observe(NodeContentComponent.self) { [weak self] event in
                self?.handle(event, keyPath: \.content, structure: true)
            }
        }

        private func handle<T: Component, Member>(
            _ event: ComponentEvent<T>, keyPath: KeyPath<Node, Member>, structure: Bool
        ) {
            guard nodeWriteDepth == 0 else {
                return
            }
            switch event {
            case .added:
                break
            case let .changed(entity, _):
                entity[NodeReferenceComponent.self]?.node?.worldDidChange(keyPath, structure: structure)
            case let .removed(entity, _):
                // The node goes back to local storage with default values on its next read.
                entity[NodeReferenceComponent.self]?.node?.worldDidChange(keyPath, structure: true)
            }
        }

        func writeFromNode(_ body: () -> Void) {
            nodeWriteDepth += 1
            defer { nodeWriteDepth -= 1 }
            body()
        }
    }
}

extension SceneGraph.Node {
    final class EntityBinding {
        let store: SceneGraph.NodeStore
        // The World's structuralRevision when the refs were made. Any other value means the rows may have moved.
        var revision: UInt64
        var transform: ComponentRef<NodeTransformComponent>
        var content: ComponentRef<NodeContentComponent>

        var world: World {
            store.world
        }

        init?(store: SceneGraph.NodeStore, id: EntityID) {
            let world = store.world
            guard let transform = world.componentRef(NodeTransformComponent.self, for: id),
                  let content = world.componentRef(NodeContentComponent.self, for: id) else {
                return nil
            }
            self.store = store
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

    // Untracked reads: Node's own Observation covers these properties, so the World's is not needed.
    @inline(__always)
    func readLocalTransform() -> SceneGraph.LocalTransform {
        if entityBinding != nil, let binding = currentBinding() {
            return binding.transform.untrackedValue.localTransform
        }
        return storedLocalTransform
    }

    @inline(__always)
    func readContent() -> Content {
        if entityBinding != nil, let binding = currentBinding() {
            return binding.content.untrackedValue.content
        }
        return storedContent
    }

    func worldDidChange<Member>(_ keyPath: KeyPath<SceneGraph.Node, Member>, structure: Bool) {
        withMutation(keyPath: keyPath) {}
        bump(structure: structure)
    }

    // Gives this node and its subtree entities in `store`'s World. A subtree in another World leaves it first.
    func attach(to store: SceneGraph.NodeStore, parent: SceneGraph.Node?, siblingIndex: Int) {
        if let binding = currentBinding() {
            if binding.store === store {
                linkInWorld(parent: parent, siblingIndex: siblingIndex)
                return
            }
            detach()
        }
        store.world.createEntity(
            id: id,
            NodeTransformComponent(localTransform: storedLocalTransform),
            NodeContentComponent(content: storedContent),
            SiblingIndexComponent(index: siblingIndex),
            NodeReferenceComponent(node: self)
        )
        entityBinding = EntityBinding(store: store, id: id)
        linkInWorld(parent: parent, siblingIndex: siblingIndex)
        for (index, child) in children.enumerated() {
            child.attach(to: store, parent: self, siblingIndex: index)
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
        storedLocalTransform = binding.transform.untrackedValue.localTransform
        storedContent = binding.content.untrackedValue.content
        entityBinding = nil
        if let entity = binding.world[id] {
            _ = try? binding.world.destroy(entity)
        }
    }

    // Detaches only from `store`, so a subtree that moved to another graph keeps its entities there.
    func detach(from store: SceneGraph.NodeStore) {
        guard let binding = currentBinding(), binding.store === store else {
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
            children[childIndex].attach(to: binding.store, parent: self, siblingIndex: childIndex)
        }
    }
}
