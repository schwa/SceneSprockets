import GeometryLite3D
import Metal
import SwiftMesh
import simd

extension SceneGraph {
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

        public var id: ObjectIdentifier {
            ObjectIdentifier(self)
        }

        public private(set) weak var parent: Node?
        public private(set) var children: [Node] = []
        public var label: String?
        public var localTransform: LocalTransform {
            didSet {
                SceneGraph.Transaction.current?.recordTransform(of: self, oldValue: oldValue)
                bump(structure: false)
            }
        }
        public var content: Content {
            didSet { bump(structure: true) }
        }
        // Blend shapes for this node's mesh (MetalMesh cannot carry them). Weighted by morphWeights.
        public var morphTargets: [MorphTarget] = [] {
            didSet { bump(structure: true) }
        }
        // False hides this node and its subtree from traversal, rendering and bounds.
        public var isVisible = true {
            didSet { bump(structure: true) }
        }
        // 0 is invisible, 1 opaque; multiplies with the ancestors' opacity, like SCNNode.opacity. Applied by materials
        // with appliesNodeOpacity (Blinn-Phong, ShaderMaterial, PBR). Bumps the transform revision, not the structure
        // one, so fading does not rebuild renderer caches.
        public var opacity: Float = 1 {
            didSet { bump(structure: false) }
        }

        // Simulated by MetalSprocketsSceneGraphPhysics when set.
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
        public private(set) var revision = Revision(structure: Revision.next(), transform: Revision.next())

        struct BoundsCache {
            var mesh: (revision: Int, bounds: BoundingBox3D?)?
            var subtree: (revision: Revision, bounds: BoundingBox3D?)?
        }

        var boundsCache = BoundsCache()
        var deformationCache: (revision: Revision, mesh: MetalMesh)?
        var shapeStorage: (shape: Shape, device: MTLDevice)?
        var runningActions: [RunningAction] = []
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
        var subdivisionBase: MetalMesh?

        func applySubdivision() {
            guard case let .mesh(mesh, materials, castsShadow, receivesShadow) = content else {
                return
            }
            let base = subdivisionBase ?? mesh
            subdivisionBase = subdivisionLevel > 0 ? base : nil
            let result = base.subdivided(levels: max(subdivisionLevel, 0)) ?? base
            content = .mesh(result, materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
        }

        // Particle emitters at this node; see ParticleSystem. Shared, not copied, by clone().
        public var particleSystems: [ParticleSystem] = []
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
        var accelerationStates: [Int: AccelerationState] = [:]
        // Matched against camera, light and hit-test masks, like SCNNode.categoryBitMask. Not inherited by children.
        public var categoryBitMask: UInt = 1 {
            didSet { bump(structure: true) }
        }
        // For light nodes: lights only meshes whose categoryBitMask shares a bit with this, like
        // SCNLight.categoryBitMask.
        public var lightCategoryBitMask: UInt = .max {
            didSet { bump(structure: true) }
        }
        // Lower values draw first, like SCNNode.renderingOrder. Within one value, each renderer keeps its own order
        // (for example PBR draws opaque before blended).
        public var renderingOrder: Int = 0 {
            didSet { bump(structure: true) }
        }

        private func bump(structure: Bool) {
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

        // The point position, rotation and scale apply around, like SCNNode.pivot: content and children are drawn
        // at transform * pivot.inverse. Identity by default.
        public var pivot: float4x4 = .identity {
            didSet {
                pivotInverse = pivot.inverse
                bump(structure: false)
            }
        }
        private var pivotInverse: float4x4 = .identity

        // The local transform with the pivot applied; what world transforms and bounds are built from.
        public var composedTransform: float4x4 {
            pivot == .identity ? transform : transform * pivotInverse
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
            self.label = label
            self.localTransform = .matrix(transform)
            self.content = content
            for child in children {
                addChild(child)
            }
            parent?.addChild(self)
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
            child.removeFromParent()
            children.insert(child, at: index)
            child.parent = self
            bump(structure: true)
        }

        public func removeChild(_ child: Node) {
            guard child.parent === self else {
                return
            }
            children.removeAll { $0 === child }
            child.parent = nil
            bump(structure: true)
        }

        public func removeFromParent() {
            parent?.removeChild(self)
        }

        public func removeAllChildren() {
            for child in children {
                child.parent = nil
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
            copy.shapeStorage = shapeStorage
            for child in children {
                copy.addChild(child.clone())
            }
            return copy
        }
    }
}
