import GeometryLite3D
import Metal
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
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
            var mesh: (revision: Int, bounds: BoundingBox?)?
            var subtree: (revision: Revision, bounds: BoundingBox?)?
        }

        var boundsCache = BoundsCache()
        var deformationCache: (revision: Revision, mesh: MetalMesh)?
        var shapeStorage: (shape: Shape, device: MTLDevice)?
        var runningActions: [RunningAction] = []
        // Applied in order by SceneGraph.applyConstraints(pointOfView:).
        public var constraints: [Constraint] = []
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

        // Setting this stores a matrix.
        public var transform: float4x4 {
            get { localTransform.matrix }
            set { localTransform = .matrix(newValue) }
        }

        // Setting this stores TRS. Reading a matrix transform decomposes it.
        public var trs: TRS {
            get {
                switch localTransform {
                case .trs(let trs):
                    trs
                case .matrix(let matrix):
                    TRS(matrix: matrix)
                }
            }
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
            trs: TRS,
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
    }
}
