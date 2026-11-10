import GeometryLite3D
import Metal
import MetalSprocketsParticles
import Observation
import simd
import SwiftECS
import SwiftMesh

extension SceneGraph {
    /// Observable, so SwiftUI views that read a node update when it changes. Caches and revisions are ignored: the
    /// renderer writes them every frame.
    @Observable
    public final class Node: Identifiable {
        /// What a node shows.
        public enum Content {
            /// Nothing. The node only groups and moves its children.
            case empty
            /// A mesh with one material for each submesh.
            ///
            /// `materials[i]` applies to submesh `i`. The last material covers any extra submeshes.
            case mesh(MetalMesh, materials: [any Material], castsShadow: Bool = true, receivesShadow: Bool = true)
            /// A light.
            case light(Light)
            /// A camera.
            case camera(Camera)

            /// A mesh with one material for all submeshes.
            public static func mesh(_ mesh: MetalMesh, material: any Material, castsShadow: Bool = true, receivesShadow: Bool = true) -> Self {
                .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        }

        /// Also the id of this node's entity while it is in a graph.
        public let id = EntityID()

        // Unowned, not weak: a weak reference gives the parent a side-table reference count, which slows every retain,
        // including the ancestor walk in bump() on each write (#283). deinit clears it in the children instead, so it
        // still reads nil after the parent is freed.
        @ObservationIgnored public private(set) unowned var parent: Node?

        // A child's parent is always the node whose `children` holds it. Reading `parent` here would trap: it points at
        // the node being freed.
        deinit {
            for child in children {
                child.parent = nil
            }
        }
        /// The child nodes, in order. Use ``addChild(_:)``, ``insertChild(_:at:)`` and ``removeChild(_:)`` to change
        /// them.
        public private(set) var children: [Node] = []
        // Set while the node is in a graph; see Node+Entity.swift.
        @ObservationIgnored @exclusivity(unchecked) var entityBinding: EntityBinding?
        // Backing for the properties in Node+Fields.swift.
        @ObservationIgnored @exclusivity(unchecked) var localTransformStorage = NodeFieldStorage<NodeTransformComponent>()
        @ObservationIgnored @exclusivity(unchecked) var contentStorage = NodeFieldStorage<NodeContentComponent>()
        @ObservationIgnored @exclusivity(unchecked) var labelStorage = NodeFieldStorage<NodeLabelComponent>()
        @ObservationIgnored @exclusivity(unchecked) var isVisibleStorage = NodeFieldStorage<NodeIsVisibleComponent>()
        @ObservationIgnored @exclusivity(unchecked) var isActiveStorage = NodeFieldStorage<NodeIsActiveComponent>()
        @ObservationIgnored @exclusivity(unchecked) var opacityStorage = NodeFieldStorage<NodeOpacityComponent>()
        @ObservationIgnored @exclusivity(unchecked) var pivotStorage = NodeFieldStorage<NodePivotComponent>()
        @ObservationIgnored @exclusivity(unchecked) var categoryBitMaskStorage = NodeFieldStorage<NodeCategoryBitMaskComponent>()
        @ObservationIgnored @exclusivity(unchecked) var lightCategoryBitMaskStorage = NodeFieldStorage<NodeLightCategoryBitMaskComponent>()
        @ObservationIgnored @exclusivity(unchecked) var renderingOrderStorage = NodeFieldStorage<NodeRenderingOrderComponent>()
        @ObservationIgnored @exclusivity(unchecked) var physicsBodyStorage = NodeFieldStorage<NodePhysicsBodyComponent>()
        @ObservationIgnored @exclusivity(unchecked) var levelsOfDetailStorage = NodeFieldStorage<NodeLevelsOfDetailComponent>()
        @ObservationIgnored @exclusivity(unchecked) var particleSystemsStorage = NodeFieldStorage<NodeParticleSystemsComponent>()
        @ObservationIgnored @exclusivity(unchecked) var audioPlayersStorage = NodeFieldStorage<NodeAudioPlayersComponent>()
        @ObservationIgnored @exclusivity(unchecked) var skinStorage = NodeFieldStorage<NodeSkinComponent>()
        @ObservationIgnored @exclusivity(unchecked) var skinVerticesStorage = NodeFieldStorage<NodeSkinVerticesComponent>()
        @ObservationIgnored @exclusivity(unchecked) var morphTargetsStorage = NodeFieldStorage<NodeMorphTargetsComponent>()
        @ObservationIgnored @exclusivity(unchecked) var morphWeightsStorage = NodeFieldStorage<NodeMorphWeightsComponent>()
        @ObservationIgnored @exclusivity(unchecked) var runningActionsStorage = NodeFieldStorage<NodeRunningActionsComponent>()
        @ObservationIgnored @exclusivity(unchecked) var actionSpeedStorage = NodeFieldStorage<NodeActionSpeedComponent>()
        @ObservationIgnored @exclusivity(unchecked) var constraintsStorage = NodeFieldStorage<NodeConstraintsComponent>()
        @ObservationIgnored @exclusivity(unchecked) var accelerationStatesStorage = NodeFieldStorage<NodeAccelerationStatesComponent>()
        @ObservationIgnored @exclusivity(unchecked) var subdivisionLevelStorage = NodeFieldStorage<NodeSubdivisionLevelComponent>()
        @ObservationIgnored @exclusivity(unchecked) var subdivisionBaseStorage = NodeFieldStorage<NodeSubdivisionBaseComponent>()
        /// Drawn, hit and counted in bounds, if its ancestors are too: visible and active.
        public var isShown: Bool {
            isVisible && isActive
        }

        var inheritedOpacity: Float {
            var result = opacity
            var node = parent
            while let current = node {
                result *= current.opacity
                node = current.parent
            }
            return result
        }

        /// Revision of this node's subtree; changes propagate to ancestors.
        @ObservationIgnored public private(set) var revision = Revision(structure: Revision.next(), transform: Revision.next())

        struct BoundsCache {
            var mesh: (revision: Int, bounds: BoundingBox3D?)?
            var subtree: (revision: Revision, bounds: BoundingBox3D?)?
        }

        @ObservationIgnored var boundsCache = BoundsCache()
        @ObservationIgnored var deformationCache: (revision: Revision, mesh: MetalMesh)?
        @ObservationIgnored var shapeStorage: Shape?
        func applySubdivision() {
            guard case let .mesh(mesh, materials, castsShadow, receivesShadow) = content else {
                return
            }
            let base = subdivisionBase ?? mesh
            subdivisionBase = subdivisionLevel > 0 ? base : nil
            let result = base.subdivided(levels: max(subdivisionLevel, 0)) ?? base
            content = .mesh(result, materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
        }

        /// The model file this node's subtree was loaded from. A scene archive then stores the file instead of the
        /// subtree, so the subtree should not be edited (#157).
        @ObservationIgnored public var modelSource: ModelSource?
        func bump(structure: Bool) {
            let value = Revision.next()
            var node: Node? = self
            while let current = node {
                if structure {
                    current.revision.structure = value
                } else {
                    current.revision.transform = value
                }
                node = current.parent
            }
        }

        // Keyed by the pivot it inverts, so a pivot written directly to the World is not missed.
        @ObservationIgnored private var pivotInverseCache: (pivot: float4x4, inverse: float4x4)?

        /// The local transform with the pivot applied; what world transforms and bounds are built from.
        public var composedTransform: float4x4 {
            composedTransform(transform: transform, pivot: pivot)
        }

        @inline(__always)
        func composedTransform(transform: float4x4, pivot: float4x4) -> float4x4 {
            // simd's constant, not GeometryLite3D's `.identity`, which is not inlinable (#283).
            guard pivot != matrix_identity_float4x4 else {
                return transform
            }
            if let pivotInverseCache, pivotInverseCache.pivot == pivot {
                return transform * pivotInverseCache.inverse
            }
            let inverse = pivot.inverse
            pivotInverseCache = (pivot, inverse)
            return transform * inverse
        }

        /// Setting this stores a matrix. Does not include `pivot`.
        public var transform: float4x4 {
            get { localTransform.matrix }
            set { localTransform = .matrix(newValue) }
        }

        /// Setting this stores TRS. Reading a matrix transform decomposes it.
        public var trs: Transform3D {
            get { localTransform.trs }
            set { localTransform = .trs(newValue) }
        }

        /// Creates a node with a matrix transform.
        ///
        /// - Parameters:
        ///   - children: The children to add to the node.
        ///   - label: A name for the node, for debugging and outlines.
        ///   - transform: The local transform, as a matrix.
        ///   - content: What the node shows.
        public init(
            children: [Node] = [],
            label: String? = nil,
            transform: float4x4 = .identity,
            content: Content = .empty
        ) {
            self.labelStorage.local = label
            self.localTransformStorage.local = .matrix(transform)
            self.contentStorage.local = content
            for child in children {
                addChild(child)
            }
        }

        /// For SceneArchive; see SceneGraph+Archive.swift.
        public required convenience init(from decoder: Decoder) throws {
            self.init()
            try decodeArchive(from: decoder)
        }

        /// Creates a node with a translation, rotation and scale.
        ///
        /// - Parameters:
        ///   - children: The children to add to the node.
        ///   - label: A name for the node, for debugging and outlines.
        ///   - trs: The local translation, rotation and scale.
        ///   - content: What the node shows.
        public convenience init(
            children: [Node] = [],
            label: String? = nil,
            trs: Transform3D,
            content: Content = .empty
        ) {
            self.init(children: children, label: label, content: content)
            self.localTransform = .trs(trs)
        }

        // MARK: - Hierarchy

        /// Returns whether this node is the parent of a node, or an ancestor of its parent.
        public func isAncestor(of node: Node) -> Bool {
            var current = node.parent
            while let ancestor = current {
                if ancestor === self {
                    return true
                }
                current = ancestor.parent
            }
            return false
        }

        /// False if `child` is this node or one of its ancestors.
        public func canAddChild(_ child: Node) -> Bool {
            child !== self && !child.isAncestor(of: self)
        }

        /// Adds a node at the end of the children, and removes it from its old parent first.
        ///
        /// A child that makes a cycle causes a precondition failure.
        ///
        /// - Returns: `child`.
        @discardableResult
        public func addChild<Child: Node>(_ child: Child) -> Child {
            insertChild(child, at: children.count)
            return child
        }

        /// Moves `child` from its current parent, if any.
        public func insertChild(_ child: Node, at index: Int) {
            precondition(canAddChild(child), "Adding this child would create a cycle")
            var index = index
            if child.parent === self, let current = children.firstIndex(where: { $0 === child }), current < index {
                index -= 1
            }
            // Unlink without detaching, so a move inside one graph keeps the child's entity.
            child.parent?.unlinkChild(child)
            children.insert(child, at: index)
            child.parent = self
            if currentBinding() != nil {
                syncChildrenInWorld(from: index)
            } else {
                child.detach()
            }
            bump(structure: true)
        }

        /// Removes a child. A node that is not a child does not change.
        public func removeChild(_ child: Node) {
            guard child.parent === self else {
                return
            }
            unlinkChild(child)
            child.detach()
        }

        // Orders children by their SiblingIndexComponent in the World, ties keeping their current order, then
        // renumbers them 0, 1, 2... (#273).
        func sortChildrenBySiblingIndex() {
            guard let world else {
                return
            }
            let sorted = children.enumerated()
                .map { position, child in
                    let index = world[child.id]?[SiblingIndexComponent.self]?.index ?? position
                    return (index: index, position: position, child: child)
                }
                .sorted { ($0.index, $0.position) < ($1.index, $1.position) }
                .map(\.child)
            let changed = sorted.map(\.id) != children.map(\.id)
            children = sorted
            syncChildrenInWorld(from: 0)
            if changed {
                bump(structure: true)
            }
        }

        // Code outside the scene graph destroyed this node's entity (#271). The node leaves the tree like
        // removeFromParent(), with default values; its subtree comes along and leaves the World.
        func entityWasDestroyed() {
            lostEntity(notify: true)
            for child in children {
                child.detach()
            }
            parent?.unlinkChild(self)
        }

        private func unlinkChild(_ child: Node) {
            guard let index = children.firstIndex(where: { $0 === child }) else {
                return
            }
            children.remove(at: index)
            child.parent = nil
            syncChildrenInWorld(from: index)
            bump(structure: true)
        }

        /// Removes the node from its parent.
        public func removeFromParent() {
            parent?.removeChild(self)
        }

        /// Removes every child of the node.
        public func removeAllChildren() {
            for child in children {
                child.parent = nil
                child.detach()
            }
            children.removeAll()
            bump(structure: true)
        }

        /// Puts `newChild` where `child` was, like SCNNode.replaceChildNode(_:with:). Does nothing when `child` is not
        /// a child of this node.
        public func replaceChild(_ child: Node, with newChild: Node) {
            guard child !== newChild, let index = children.firstIndex(where: { $0 === child }) else {
                return
            }
            removeChild(child)
            insertChild(newChild, at: min(index, children.count))
        }

        /// A copy of this node and its subtree, like SCNNode.clone(). Meshes, materials, skins and constraints are
        /// shared, not copied; running actions are not copied. The copy has no parent.
        public func clone() -> Node {
            let copy = Node(label: label, content: content)
            copy.localTransform = localTransform
            copy.pivot = pivot
            copy.morphTargets = morphTargets
            copy.morphWeights = morphWeights
            copy.skin = skin
            copy.skinVertices = skinVertices
            copy.isVisible = isVisible
            copy.isActive = isActive
            copy.opacity = opacity
            copy.physicsBody = physicsBody
            copy.constraints = constraints
            copy.categoryBitMask = categoryBitMask
            copy.lightCategoryBitMask = lightCategoryBitMask
            copy.renderingOrder = renderingOrder
            copy.levelsOfDetail = levelsOfDetail
            copy.particleSystems = particleSystems
            copy.subdivisionBase = subdivisionBase
            copy.subdivisionLevel = subdivisionLevel
            copy.actionSpeed = actionSpeed
            copy.modelSource = modelSource
            copy.shapeStorage = shapeStorage
            for child in children {
                copy.addChild(child.clone())
            }
            return copy
        }
    }
}

extension SceneGraph.Node {
    /// The first node named `label` in depth-first order (this node excluded), like
    /// SCNNode.childNode(withName:recursively:).
    public func childNode(withLabel label: String, recursively: Bool = true) -> SceneGraph.Node? {
        for child in children {
            if child.label == label {
                return child
            }
            if recursively, let found = child.childNode(withLabel: label) {
                return found
            }
        }
        return nil
    }
}
