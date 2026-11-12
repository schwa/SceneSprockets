import GeometryLite3D
import simd
import SwiftMesh

extension SceneGraph {
    /// A simpler mesh drawn instead of a node's mesh from `distance` (world units from the camera to the node's
    /// origin) onwards, like SCNLevelOfDetail(geometry:worldSpaceDistance:). Materials map to its submeshes as for
    /// the node's own mesh. A nil mesh draws nothing.
    public struct LevelOfDetail {
        /// The mesh to draw, or `nil` to draw nothing.
        public var mesh: MetalMesh?
        /// The distance from the camera to the node's origin, in world units, where this level starts.
        public var distance: Float

        /// Creates a level of detail.
        ///
        /// - Parameters:
        ///   - mesh: The mesh to draw, or `nil` to draw nothing.
        ///   - distance: The camera distance, in world units, where this level starts.
        public init(mesh: MetalMesh?, distance: Float) {
            self.mesh = mesh
            self.distance = distance
        }
    }
}

// Swaps in each node's level of detail for the camera at `cameraPosition`. Nodes without levels pass through.
func applyLevelsOfDetail(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    guard entries.contains(where: { !$0.levelsOfDetail.isEmpty }) else {
        return entries
    }
    var result: [SceneGraph.MeshEntry] = []
    var handled = Set<SceneGraph.Node.ID>()
    for entry in entries {
        let nodeID = entry.nodeID
        guard !entry.levelsOfDetail.isEmpty else {
            result.append(entry)
            continue
        }
        // A node's entries are one per submesh; replace them all at its first.
        guard handled.insert(nodeID).inserted else {
            continue
        }
        let position = entry.worldTransform.columns.3.xyz
        let distance = simd_distance(position, cameraPosition)
        guard let level = entry.levelsOfDetail.filter({ $0.distance <= distance }).max(by: { $0.distance < $1.distance }) else {
            result += entries.filter { $0.nodeID == nodeID }
            continue
        }
        let materials = entry.nodeMaterials
        guard let mesh = level.mesh, let lastMaterial = materials.last else {
            continue
        }
        for submeshIndex in mesh.submeshes.indices {
            var replacement = entry
            replacement.mesh = mesh
            replacement.submeshIndex = submeshIndex
            replacement.material = submeshIndex < materials.count ? materials[submeshIndex] : lastMaterial
            result.append(replacement)
        }
    }
    return result
}
