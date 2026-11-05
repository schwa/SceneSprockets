import GeometryLite3D
import Metal
import SceneSprocketsAudio
import MetalSprocketsParticles
import Observation
import SwiftECS
import SwiftMesh
import simd

extension SceneGraph {
    // Observable, so SwiftUI views that read a node update when it changes. Caches and revisions are ignored: the
    // renderer writes them every frame.
    @Observable
    public class Node: Identifiable {
        public enum Content {
            case empty
            // materials[i] applies to submesh i; the last material covers any extra submeshes.
            case mesh(MetalMesh, materials: [any Material], castsShadow: Bool = true, receivesShadow: Bool = true)
            case light(Light)
            case camera(Camera)

            public static func mesh(_ mesh: MetalMesh, material: any Material, castsShadow: Bool = true, receivesShadow: Bool = true) -> Self {
                .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        }

        // Also the id of this node's entity while it is in a graph.
        public let id = EntityID()

        @ObservationIgnored public private(set) weak var parent: Node?
        public private(set) var children: [Node] = []
        // Set while the node is in a graph; see Node+Entity.swift.
        @ObservationIgnored var entityBinding: EntityBinding?
        // Backing for the properties in Node+Fields.swift.
        @ObservationIgnored var localTransformStorage = NodeFieldStorage<NodeTransformComponent>()
        @ObservationIgnored var contentStorage = NodeFieldStorage<NodeContentComponent>()
        @ObservationIgnored var labelStorage = NodeFieldStorage<NodeLabelComponent>()
        @ObservationIgnored var isVisibleStorage = NodeFieldStorage<NodeIsVisibleComponent>()
        @ObservationIgnored var isActiveStorage = NodeFieldStorage<NodeIsActiveComponent>()
        @ObservationIgnored var opacityStorage = NodeFieldStorage<NodeOpacityComponent>()
        @ObservationIgnored var pivotStorage = NodeFieldStorage<NodePivotComponent>()
        @ObservationIgnored var categoryBitMaskStorage = NodeFieldStorage<NodeCategoryBitMaskComponent>()
        @ObservationIgnored var lightCategoryBitMaskStorage = NodeFieldStorage<NodeLightCategoryBitMaskComponent>()
        @ObservationIgnored var renderingOrderStorage = NodeFieldStorage<NodeRenderingOrderComponent>()
        // Blend shapes for this node's mesh (MetalMesh cannot carry them). Weighted by morphWeights.
        public var morphTargets: [MorphTarget] = [] {
            didSet { bump(structure: true) }
        }
        // Drawn, hit and counted in bounds, if its ancestors are too: visible and active.
        public var isShown: Bool {
            isVisible && isActive
        }

        // Simulated by SceneSprocketsPhysics when set.
        public var physicsBody: PhysicsBody? {
            didSet { bump(structure: true) }
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
        // Skinned meshes are placed by their joints, not by this node's transform.
        public var skin: Skin? {
            didSet { bump(structure: true) }
        }
        // Per-vertex joint influences for this node's mesh; indexed like its vertices.
        public var skinVertices: [SkinVertex] = [] {
            didSet { bump(structure: true) }
        }
        // Morph target weights for this node's mesh; animated like transforms.
        public var morphWeights: [Float] = [] {
            didSet {
                SceneGraph.Transaction.current?.recordMorphWeights(of: self, oldValue: oldValue)
                bump(structure: false)
            }
        }

        // Revision of this node's subtree; changes propagate to ancestors.
        @ObservationIgnored public private(set) var revision = Revision(structure: Revision.next(), transform: Revision.next())

        struct BoundsCache {
            var mesh: (revision: Int, bounds: BoundingBox3D?)?
            var subtree: (revision: Revision, bounds: BoundingBox3D?)?
        }

        @ObservationIgnored var boundsCache = BoundsCache()
        @ObservationIgnored var deformationCache: (revision: Revision, mesh: MetalMesh)?
        @ObservationIgnored var shapeStorage: (shape: Shape, device: MTLDevice)?
        @ObservationIgnored var runningActions: [RunningAction] = []
        // Multiplies the time this node's actions advance by; 0 pauses them. Not inherited by children.
        public var actionSpeed: Float = 1
        // Loop-subdivides this node's mesh, like SCNGeometry.subdivisionLevel; 0 restores the original. Triangle
        // meshes only. Setting `shape` rebuilds and subdivides again.
        public var subdivisionLevel = 0 {
            didSet {
                guard subdivisionLevel != oldValue else {
                    return
                }
                applySubdivision()
            }
        }
        @ObservationIgnored var subdivisionBase: MetalMesh?

        func applySubdivision() {
            guard case let .mesh(mesh, materials, castsShadow, receivesShadow) = content else {
                return
            }
            let base = subdivisionBase ?? mesh
            subdivisionBase = subdivisionLevel > 0 ? base : nil
            let result = base.subdivided(levels: max(subdivisionLevel, 0)) ?? base
            content = .mesh(result, materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
        }

        // The model file this node's subtree was loaded from. A scene archive then stores the file instead of the
        // subtree, so the subtree should not be edited (#157).
        @ObservationIgnored public var modelSource: ModelSource?
        // Particle effects at this node; see SceneParticleSystem. Shared, not copied, by clone().
        public var particleSystems: [SceneParticleSystem] = []
        // Sounds that play from this node; see SceneAudio. Not copied by clone().
        public var audioPlayers: [AudioPlayer] = []
        // Simpler meshes for distant cameras; see LevelOfDetail. Order does not matter.
        public var levelsOfDetail: [LevelOfDetail] = [] {
            didSet { bump(structure: true) }
        }
        // Applied in order by SceneGraph.applyConstraints(pointOfView:deltaTime:).
        public var constraints: [Constraint] = [] {
            didSet { accelerationStates = [:] }
        }
        // Smoothed position and velocity of each acceleration constraint, by index in `constraints`.
        @ObservationIgnored var accelerationStates: [Int: AccelerationState] = [:]

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

        // The local transform with the pivot applied; what world transforms and bounds are built from.
        public var composedTransform: float4x4 {
            let pivot = self.pivot
            guard pivot != .identity else {
                return transform
            }
            if let pivotInverseCache, pivotInverseCache.pivot == pivot {
                return transform * pivotInverseCache.inverse
            }
            let inverse = pivot.inverse
            pivotInverseCache = (pivot, inverse)
            return transform * inverse
        }

        // Setting this stores a matrix. Does not include `pivot`.
        public var transform: float4x4 {
            get { localTransform.matrix }
            set { localTransform = .matrix(newValue) }
        }

        // Setting this stores TRS. Reading a matrix transform decomposes it.
        public var trs: Transform3D {
            get { localTransform.trs }
            set { localTransform = .trs(newValue) }
        }

        public init(
            parent: Node? = nil,
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
            parent?.addChild(self)
        }

        // For SceneArchive; see SceneGraph+Archive.swift.
        public required convenience init(from decoder: Decoder) throws {
            self.init()
            try decodeArchive(from: decoder)
        }

        public convenience init(
            parent: Node? = nil,
            children: [Node] = [],
            label: String? = nil,
            trs: Transform3D,
            content: Content = .empty
        ) {
            self.init(parent: parent, children: children, label: label, content: content)
            self.localTransform = .trs(trs)
        }

        // MARK: - Hierarchy

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

        // False if `child` is this node or one of its ancestors.
        public func canAddChild(_ child: Node) -> Bool {
            child !== self && !child.isAncestor(of: self)
        }

        public func addChild(_ child: Node) {
            insertChild(child, at: children.count)
        }

        // Moves `child` from its current parent, if any.
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

        public func removeChild(_ child: Node) {
            guard child.parent === self else {
                return
            }
            unlinkChild(child)
            child.detach()
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

        public func removeFromParent() {
            parent?.removeChild(self)
        }

        public func removeAllChildren() {
            for child in children {
                child.parent = nil
                child.detach()
            }
            children.removeAll()
            bump(structure: true)
        }

        // Puts `newChild` where `child` was, like SCNNode.replaceChildNode(_:with:). Does nothing when `child` is not
        // a child of this node.
        public func replaceChild(_ child: Node, with newChild: Node) {
            guard child !== newChild, let index = children.firstIndex(where: { $0 === child }) else {
                return
            }
            removeChild(child)
            insertChild(newChild, at: min(index, children.count))
        }

        // The first node named `label` in depth-first order (this node excluded), like
        // SCNNode.childNode(withName:recursively:).
        public func childNode(withLabel label: String, recursively: Bool = true) -> Node? {
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

        // A copy of this node and its subtree, like SCNNode.clone(). Meshes, materials, skins and constraints are
        // shared, not copied; running actions are not copied. The copy has no parent.
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
