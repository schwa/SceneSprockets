import GeometryLite3D
import Observation
import simd
import SwiftECS
import SwiftMesh

/// A tree of nodes with meshes, lights and cameras, and the settings that apply to the whole scene.
///
/// The scene graph caches traversals, bounds and mesh entries by ``revision``, and stores node data in a SwiftECS
/// ``world``. It is `@Observable`, so SwiftUI views update when it changes.
@Observable
public class SceneGraph {
    /// The root node. Its descendants are the scene.
    public var root: Node {
        didSet {
            if oldValue !== root {
                oldValue.detach(from: store)
                store.rootID = root.id
                root.attach(to: store, parent: nil, siblingIndex: 0)
            }
            rootRevision = Revision.next()
        }
    }
    @ObservationIgnored let store: NodeStore

    /// Holds every node under `root` as an entity with Node*Component values (#250, #269). An ECS app can add its own
    /// components to these entities and query or write the node components directly:
    /// - Writes update the nodes, their revisions and SwiftUI observation, like the Node API.
    /// - They are not animated by Transaction.animate (#272).
    /// - ChildOf and SiblingIndexComponent edits move nodes in the tree; setParent(nil) removes the node from the
    ///   graph, like removeFromParent(). Destroying an entity removes its node from the tree (#271, #273).
    /// - Entities without a Node, and ChildOf edges to them, are ignored.
    /// Several graphs can share one World; SceneGraphMembershipComponent tells their entities apart.
    public var world: World {
        store.world
    }
    @ObservationIgnored private var rootRevision = Revision.next()
    /// Background and image-based lighting; read every frame, so changing it does not change `revision`.
    public var environment = Environment()
    /// Nil: no fog. Read every frame, so changing it does not change `revision`.
    public var fog: Fog?
    /// Nil: no post-processing. Read every frame, like `fog`.
    public var postProcessing: PostProcessing?

    /// Creates a scene graph with a new SwiftECS world.
    public convenience init(root: Node) {
        self.init(root: root, world: World())
    }

    /// Uses an app-owned World, held strongly, instead of creating one.
    public init(root: Node, world: World) {
        store = NodeStore(world: world, rootID: root.id)
        self.root = root
        root.attach(to: store, parent: nil, siblingIndex: 0)
    }

    // The World may outlive the graph, so the graph's entities leave it.
    deinit {
        root.detach(from: store)
    }

    /// For SceneArchive; see SceneGraph+Archive.swift.
    public required convenience init(from decoder: Decoder) throws {
        self.init(root: Node())
        try decodeArchive(from: decoder)
    }

    /// Changes whenever anything in the graph changes. Compare to skip work when nothing (or only transforms) changed.
    public var revision: Revision {
        Revision(structure: max(root.revision.structure, rootRevision), transform: root.revision.transform)
    }

    // MARK: - Traversal

    /// Flattened traversal of all nodes with their accumulated world transforms.
    public func nodesWithWorldTransforms(worldTransform initialTransform: float4x4 = .identity, includeHidden: Bool = false) -> [(node: Node, worldTransform: float4x4)] {
        var result: [(node: Node, worldTransform: float4x4)] = []
        visit(worldTransform: initialTransform, includeHidden: includeHidden) { node, worldTransform in
            result.append((node, worldTransform))
        }
        return result
    }

    // Every node except inactive subtrees, hidden or not, for simulation: actions, constraints and particles (#196).
    func visitActive(_ visitor: (Node, float4x4) throws -> Void) rethrows {
        try traverse(includeHidden: true) { node, worldTransform in
            guard node.isActive else {
                return .skipChildren
            }
            try visitor(node, worldTransform)
            return .continue
        }
    }

    /// Recursive depth-first traversal, accumulating world transforms. Skips hidden and inactive subtrees unless
    /// `includeHidden`.
    public func visit(worldTransform initialTransform: float4x4 = .identity, includeHidden: Bool = false, _ visitor: (Node, float4x4) throws -> Void) rethrows {
        try Self.visit(node: root, parentTransform: initialTransform, includeHidden: includeHidden, visitor)
    }

    /// What a traversal does after a visitor returns.
    public enum VisitResult: Sendable {
        /// The traversal continues with the node's children.
        case `continue`
        /// The traversal skips the node's descendants.
        case skipChildren
        /// The traversal ends.
        case stop
    }

    /// Depth-first traversal that the visitor can prune or end early, like enumerateHierarchy's stop flag.
    public func traverse(worldTransform initialTransform: float4x4 = .identity, includeHidden: Bool = false, _ visitor: (Node, float4x4) throws -> VisitResult) rethrows {
        _ = try Self.traverse(node: root, parentTransform: initialTransform, includeHidden: includeHidden, visitor)
    }

    // Returns false when the traversal stopped.
    private static func traverse(node: Node, parentTransform: float4x4, includeHidden: Bool, _ visitor: (Node, float4x4) throws -> VisitResult) rethrows -> Bool {
        guard let composedTransform = node.traversalTransform(includeHidden: includeHidden) else {
            return true
        }
        let worldTransform = parentTransform * composedTransform
        switch try visitor(node, worldTransform) {
        case .stop:
            return false
        case .skipChildren:
            return true
        case .continue:
            for child in node.children where try !traverse(node: child, parentTransform: worldTransform, includeHidden: includeHidden, visitor) {
                return false
            }
            return true
        }
    }

    private static func visit(node: Node, parentTransform: float4x4, includeHidden: Bool, _ visitor: (Node, float4x4) throws -> Void) rethrows {
        guard let composedTransform = node.traversalTransform(includeHidden: includeHidden) else {
            return
        }
        let worldTransform = parentTransform * composedTransform
        try visitor(node, worldTransform)
        for child in node.children {
            try visit(node: child, parentTransform: worldTransform, includeHidden: includeHidden, visitor)
        }
    }

    // MARK: - Queries

    /// Copy-on-write: renderers copy entries through several stages every frame, so the fields live in one shared
    /// object and a copy is a single retain (#133).
    public struct MeshEntry {
        private final class Storage {
            var node: Node
            var worldTransform: float4x4
            var mesh: MetalMesh
            var submeshIndex: Int
            var material: any Material
            var castsShadow: Bool
            var receivesShadow: Bool
            var opacity: Float

            init(node: Node, worldTransform: float4x4, mesh: MetalMesh, submeshIndex: Int, material: any Material, castsShadow: Bool, receivesShadow: Bool, opacity: Float) {
                self.node = node
                self.worldTransform = worldTransform
                self.mesh = mesh
                self.submeshIndex = submeshIndex
                self.material = material
                self.castsShadow = castsShadow
                self.receivesShadow = receivesShadow
                self.opacity = opacity
            }

            func copy() -> Storage {
                Storage(node: node, worldTransform: worldTransform, mesh: mesh, submeshIndex: submeshIndex, material: material, castsShadow: castsShadow, receivesShadow: receivesShadow, opacity: opacity)
            }
        }

        private var storage: Storage

        /// Creates a mesh entry.
        public init(node: Node, worldTransform: float4x4, mesh: MetalMesh, submeshIndex: Int, material: any Material, castsShadow: Bool, receivesShadow: Bool, opacity: Float = 1) {
            storage = Storage(node: node, worldTransform: worldTransform, mesh: mesh, submeshIndex: submeshIndex, material: material, castsShadow: castsShadow, receivesShadow: receivesShadow, opacity: opacity)
        }

        private mutating func uniqueStorage() -> Storage {
            if !isKnownUniquelyReferenced(&storage) {
                storage = storage.copy()
            }
            return storage
        }

        /// The node that has the mesh.
        public var node: Node {
            get { storage.node }
            set { uniqueStorage().node = newValue }
        }

        /// The node's world transform.
        public var worldTransform: float4x4 {
            get { storage.worldTransform }
            set { uniqueStorage().worldTransform = newValue }
        }

        /// The mesh, or its level of detail for the camera distance.
        public var mesh: MetalMesh {
            get { storage.mesh }
            set { uniqueStorage().mesh = newValue }
        }

        /// The index of the submesh to draw.
        public var submeshIndex: Int {
            get { storage.submeshIndex }
            set { uniqueStorage().submeshIndex = newValue }
        }

        /// The material of the submesh.
        public var material: any Material {
            get { storage.material }
            set { uniqueStorage().material = newValue }
        }

        /// Whether the submesh casts shadows.
        public var castsShadow: Bool {
            get { storage.castsShadow }
            set { uniqueStorage().castsShadow = newValue }
        }

        /// Whether shadows darken the submesh.
        public var receivesShadow: Bool {
            get { storage.receivesShadow }
            set { uniqueStorage().receivesShadow = newValue }
        }

        /// The node's opacity times its ancestors'.
        public var opacity: Float {
            get { storage.opacity }
            set { uniqueStorage().opacity = newValue }
        }

        /// Blends: the material is transparent, or it applies node opacity and that is below 1.
        public var isTransparent: Bool {
            material.isTransparent || (material.appliesNodeOpacity && opacity < 1)
        }
    }

    struct Flattened {
        var meshes: [MeshEntry] = []
        var lights: [(node: Node, worldTransform: float4x4, light: Light)] = []
        var cameras: [(node: Node, worldTransform: float4x4, camera: Camera)] = []
    }

    @ObservationIgnored private var flattenedCache: (revision: Revision, flattened: Flattened)?
    // Number of full traversals done for queries; for tests. Not observed: queries run during SwiftUI view updates,
    // and writing an observed property then crashes SwiftUI (#212).
    @ObservationIgnored private(set) var traversalCount = 0

    // One traversal fills every query. Cached until the revision changes when starting from identity.
    func flattened(worldTransform initialTransform: float4x4 = .identity) -> Flattened {
        let isCacheable = initialTransform == .identity
        let revision = self.revision
        if isCacheable, let flattenedCache, flattenedCache.revision == revision {
            return flattenedCache.flattened
        }
        traversalCount += 1
        var result = Flattened()
        visit(worldTransform: initialTransform) { node, worldTransform in
            switch node.content {
            case let .mesh(mesh, materials, castsShadow, receivesShadow):
                guard let lastMaterial = materials.last else {
                    return
                }
                let opacity = node.inheritedOpacity
                for submeshIndex in mesh.submeshes.indices {
                    let material = submeshIndex < materials.count ? materials[submeshIndex] : lastMaterial
                    result.meshes.append(MeshEntry(node: node, worldTransform: worldTransform, mesh: mesh, submeshIndex: submeshIndex, material: material, castsShadow: castsShadow, receivesShadow: receivesShadow, opacity: opacity))
                }
            case let .light(light):
                result.lights.append((node, worldTransform, light))
            case let .camera(camera):
                result.cameras.append((node, worldTransform, camera))
            case .empty:
                break
            }
        }
        if isCacheable {
            flattenedCache = (revision, result)
        }
        return result
    }

    /// Returns one entry for each visible submesh, with world transforms. The result is cached by revision.
    public func meshEntries(worldTransform initialTransform: float4x4 = .identity) -> [MeshEntry] {
        flattened(worldTransform: initialTransform).meshes
    }

    /// Returns one entry per submesh whose material matches the given type, with world transforms.
    public func meshNodes<M: Material>(withMaterial _: M.Type, worldTransform initialTransform: float4x4 = .identity) -> [(node: Node, worldTransform: float4x4, mesh: MetalMesh, submeshIndex: Int, material: M, castsShadow: Bool, receivesShadow: Bool)] {
        meshEntries(worldTransform: initialTransform).compactMap { entry in
            guard let material = entry.material as? M else {
                return nil
            }
            return (entry.node, entry.worldTransform, entry.mesh, entry.submeshIndex, material, entry.castsShadow, entry.receivesShadow)
        }
    }

    /// Returns all light nodes with their world transforms.
    public func lightNodes(worldTransform initialTransform: float4x4 = .identity) -> [(node: Node, worldTransform: float4x4, light: Light)] {
        flattened(worldTransform: initialTransform).lights
    }

    /// Returns all camera nodes with their world transforms.
    public func cameraNodes(worldTransform initialTransform: float4x4 = .identity) -> [(node: Node, worldTransform: float4x4, camera: Camera)] {
        flattened(worldTransform: initialTransform).cameras
    }

    /// Returns all mesh nodes that cast shadows, with their world transforms.
    public func shadowCasters(worldTransform initialTransform: float4x4 = .identity) -> [(node: Node, worldTransform: float4x4, mesh: MetalMesh)] {
        nodesWithWorldTransforms(worldTransform: initialTransform).compactMap { entry in
            guard case let .mesh(mesh, _, castsShadow, _) = entry.node.content, castsShadow else {
                return nil
            }
            return (entry.node, entry.worldTransform, mesh)
        }
    }

    /// Returns all mesh nodes that receive shadows, with their world transforms.
    public func shadowReceivers(worldTransform initialTransform: float4x4 = .identity) -> [(node: Node, worldTransform: float4x4, mesh: MetalMesh)] {
        nodesWithWorldTransforms(worldTransform: initialTransform).compactMap { entry in
            guard case let .mesh(mesh, _, _, receivesShadow) = entry.node.content, receivesShadow else {
                return nil
            }
            return (entry.node, entry.worldTransform, mesh)
        }
    }
}
