import GeometryLite3D
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import SwiftMesh
import simd

public class SceneGraph {
    public var root: Node {
        didSet { rootRevision = Revision.next() }
    }
    private var rootRevision = Revision.next()
    // Background and image-based lighting; read every frame, so changing it does not change `revision`.
    public var environment = Environment()
    // Nil: no fog. Read every frame, so changing it does not change `revision`.
    public var fog: Fog?

    public init(root: Node) {
        self.root = root
    }

    // Changes whenever anything in the graph changes. Compare to skip work when nothing (or only transforms) changed.
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

    /// Recursive depth-first traversal, accumulating world transforms. Skips hidden subtrees unless `includeHidden`.
    public func visit(worldTransform initialTransform: float4x4 = .identity, includeHidden: Bool = false, _ visitor: (Node, float4x4) throws -> Void) rethrows {
        try Self.visit(node: root, parentTransform: initialTransform, includeHidden: includeHidden, visitor)
    }

    private static func visit(node: Node, parentTransform: float4x4, includeHidden: Bool, _ visitor: (Node, float4x4) throws -> Void) rethrows {
        guard includeHidden || node.isVisible else {
            return
        }
        let worldTransform = parentTransform * node.transform
        try visitor(node, worldTransform)
        for child in node.children {
            try visit(node: child, parentTransform: worldTransform, includeHidden: includeHidden, visitor)
        }
    }

    // MARK: - Queries

    public struct MeshEntry {
        public var node: Node
        public var worldTransform: float4x4
        public var mesh: MetalMesh
        public var submeshIndex: Int
        public var material: any Material
        public var castsShadow: Bool
        public var receivesShadow: Bool
    }

    struct Flattened {
        var meshes: [MeshEntry] = []
        var lights: [(node: Node, worldTransform: float4x4, light: Light)] = []
        var cameras: [(node: Node, worldTransform: float4x4, camera: Camera)] = []
    }

    private var flattenedCache: (revision: Revision, flattened: Flattened)?
    // Number of full traversals done for queries; for tests.
    private(set) var traversalCount = 0

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
                for submeshIndex in mesh.submeshes.indices {
                    let material = submeshIndex < materials.count ? materials[submeshIndex] : lastMaterial
                    result.meshes.append(MeshEntry(node: node, worldTransform: worldTransform, mesh: mesh, submeshIndex: submeshIndex, material: material, castsShadow: castsShadow, receivesShadow: receivesShadow))
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

    public func meshEntries(worldTransform initialTransform: float4x4 = .identity) -> [MeshEntry] {
        flattened(worldTransform: initialTransform).meshes
    }

    /// Returns one entry per submesh whose material matches the given type, with world transforms.
    public func meshNodes<M: Material>(withMaterial materialType: M.Type, worldTransform initialTransform: float4x4 = .identity) -> [(node: Node, worldTransform: float4x4, mesh: MetalMesh, submeshIndex: Int, material: M, castsShadow: Bool, receivesShadow: Bool)] {
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
