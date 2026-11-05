import SwiftECS

// A Node property that lives in the graph's World while the node is under a SceneGraph's root, and on the node
// otherwise (#265, #274). Declare it on Node with a NodeFieldStorage, a computed property that calls
// getField/setField, and an entry in Node.worldFields.
protocol NodeField: Component, SendableMetatype {
    associatedtype Value
    var value: Value { get }
    init(value: Value)
    // Used when the entity is destroyed outside the scene graph.
    static var defaultValue: Value { get }
    // The revision a change bumps, for Node setters and direct World writes alike.
    static var revision: NodeFieldRevision { get }
    // Called after every change made through the Node API.
    static func didChange(_ node: SceneGraph.Node, from oldValue: Value)
}

enum NodeFieldRevision {
    case none
    case transform
    case structure
}

extension NodeField {
    static func didChange(_ node: SceneGraph.Node, from oldValue: Value) {
        node.bump(revision)
    }
}

// ChildOf does not keep an order we can change, so each child stores its index among its siblings.
struct SiblingIndexComponent: Component {
    var index: Int
}

// Finds the node for an entity, so writes made directly to the World can reach it. Its presence also marks the
// entity as a live scene graph node.
struct NodeReferenceComponent: Component {
    weak var node: SceneGraph.Node?
}

// The local value of a node field, and a cached ref while the node is in a graph.
struct NodeFieldStorage<Field: NodeField> {
    var local = Field.defaultValue
    var ref: ComponentRef<Field>?
    // The World's structuralRevision when `ref` was made.
    var refRevision: UInt64 = 0
}

typealias NodeFieldStorageKeyPath<Field: NodeField> = ReferenceWritableKeyPath<SceneGraph.Node, NodeFieldStorage<Field>>

// Type-erased access to one node field, for code that handles every field.
struct NodeFieldSlot: Sendable {
    let component: @Sendable (SceneGraph.Node) -> any Component
    let copyBack: @Sendable (SceneGraph.Node) -> Void
    let reset: @Sendable (SceneGraph.Node) -> Void
    let observe: @Sendable (SceneGraph.NodeStore) -> Void

    init<Field: NodeField>(
        _ wrappedKeyPath: ReferenceWritableKeyPath<SceneGraph.Node, Field.Value> & Sendable,
        _ storageKeyPath: NodeFieldStorageKeyPath<Field> & Sendable
    ) {
        component = { node in
            Field(value: node[keyPath: storageKeyPath].local)
        }
        copyBack = { node in
            node[keyPath: storageKeyPath].local = node.readField(storageKeyPath)
            node[keyPath: storageKeyPath].ref = nil
        }
        reset = { node in
            node[keyPath: storageKeyPath].local = Field.defaultValue
            node[keyPath: storageKeyPath].ref = nil
        }
        observe = { store in
            store.world.observe(Field.self) { [weak store] event in
                store?.handle(event, keyPath: wrappedKeyPath)
            }
        }
    }
}

extension SceneGraph {
    // The World behind a scene graph. Turns component changes made directly in the World into the same revision
    // bumps and Observation notifications that Node's setters make (#266).
    final class NodeStore {
        let world = World()
        // Above 0 while a Node setter writes, so its own change event is not handled twice.
        var nodeWriteDepth = 0

        init() {
            for slot in Node.worldFields {
                slot.observe(self)
            }
        }

        func handle<Field: NodeField>(_ event: ComponentEvent<Field>, keyPath: KeyPath<Node, Field.Value>) {
            guard nodeWriteDepth == 0 else {
                return
            }
            switch event {
            case .added:
                break
            case let .changed(entity, _):
                entity[NodeReferenceComponent.self]?.node?.worldDidChange(keyPath, revision: Field.revision)
            case let .removed(entity, _):
                // The node goes back to local storage with default values on its next read.
                entity[NodeReferenceComponent.self]?.node?.worldDidChange(keyPath, revision: .structure)
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
        // The World's structuralRevision when the entity was last seen.
        var revision: UInt64

        var world: World {
            store.world
        }

        init(store: SceneGraph.NodeStore) {
            self.store = store
            revision = store.world.structuralRevision
        }

        // False when the entity is gone.
        func refresh(id: EntityID) -> Bool {
            if revision == world.structuralRevision {
                return true
            }
            guard world.componentRef(NodeReferenceComponent.self, for: id) != nil else {
                return false
            }
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
        lostEntity()
        return nil
    }

    private func lostEntity() {
        entityBinding = nil
        for slot in Self.worldFields {
            slot.reset(self)
        }
    }

    // Nil when the node is not in a graph. Refreshes the cached ref when the World's rows may have moved.
    @inline(__always)
    private func fieldRef<Field: NodeField>(_ storageKeyPath: NodeFieldStorageKeyPath<Field>) -> ComponentRef<Field>? {
        guard let binding = currentBinding() else {
            return nil
        }
        let revision = binding.world.structuralRevision
        if let ref = self[keyPath: storageKeyPath].ref, self[keyPath: storageKeyPath].refRevision == revision {
            return ref
        }
        guard let ref = binding.world.componentRef(Field.self, for: id) else {
            // An app removed this component; treat it like a destroyed entity.
            lostEntity()
            return nil
        }
        self[keyPath: storageKeyPath].ref = ref
        self[keyPath: storageKeyPath].refRevision = revision
        return ref
    }

    @inline(__always)
    func getField<Field: NodeField>(
        _ wrappedKeyPath: KeyPath<SceneGraph.Node, Field.Value>, _ storageKeyPath: NodeFieldStorageKeyPath<Field>
    ) -> Field.Value {
        access(keyPath: wrappedKeyPath)
        return readField(storageKeyPath)
    }

    @inline(__always)
    func setField<Field: NodeField>(
        _ wrappedKeyPath: KeyPath<SceneGraph.Node, Field.Value>, _ storageKeyPath: NodeFieldStorageKeyPath<Field>,
        _ value: Field.Value
    ) {
        let oldValue = readField(storageKeyPath)
        withMutation(keyPath: wrappedKeyPath) {
            writeField(storageKeyPath, value)
        }
        Field.didChange(self, from: oldValue)
    }

    // Untracked: Node's own Observation covers the property, so the World's is not needed.
    @inline(__always)
    func readField<Field: NodeField>(_ storageKeyPath: NodeFieldStorageKeyPath<Field>) -> Field.Value {
        if entityBinding != nil, let ref = fieldRef(storageKeyPath) {
            return ref.untrackedValue.value
        }
        return self[keyPath: storageKeyPath].local
    }

    @inline(__always)
    func writeField<Field: NodeField>(_ storageKeyPath: NodeFieldStorageKeyPath<Field>, _ value: Field.Value) {
        if entityBinding != nil, let ref = fieldRef(storageKeyPath), let binding = entityBinding {
            let component = Field(value: value)
            binding.store.writeFromNode { ref.value = component }
        } else {
            self[keyPath: storageKeyPath].local = value
        }
    }

    func worldDidChange<Member>(_ keyPath: KeyPath<SceneGraph.Node, Member>, revision: NodeFieldRevision) {
        withMutation(keyPath: keyPath) {}
        bump(revision)
    }

    func bump(_ revision: NodeFieldRevision) {
        switch revision {
        case .none:
            break
        case .transform:
            bump(structure: false)
        case .structure:
            bump(structure: true)
        }
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
        var components: [any Component] = [
            SiblingIndexComponent(index: siblingIndex),
            NodeReferenceComponent(node: self)
        ]
        components += Self.worldFields.map { $0.component(self) }
        store.world.createEntity(id: id, components: components)
        entityBinding = EntityBinding(store: store)
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
        for slot in Self.worldFields {
            slot.copyBack(self)
        }
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
