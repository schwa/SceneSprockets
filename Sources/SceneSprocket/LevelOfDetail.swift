import GeometryLite3D
import simd
import SwiftMesh

extension SceneGraph {
    // A simpler mesh drawn instead of a node's mesh from `distance` (world units from the camera to the node's
    // origin) onwards, like SCNLevelOfDetail(geometry:worldSpaceDistance:). Materials map to its submeshes as for
    // the node's own mesh. A nil mesh draws nothing.
    public struct LevelOfDetail {
        public var mesh: MetalMesh?
        public var distance: Float

        public init(mesh: MetalMesh?, distance: Float) {
            self.mesh = mesh
            self.distance = distance
        }
    }
}

// Swaps in each node's level of detail for the camera at `cameraPosition`. Nodes without levels pass through.
func applyLevelsOfDetail(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    guard entries.contains(where: { !$0.node.levelsOfDetail.isEmpty }) else {
        return entries
    }
    var result: [SceneGraph.MeshEntry] = []
    var handled = Set<ObjectIdentifier>()
    for entry in entries {
        let node = entry.node
        guard !node.levelsOfDetail.isEmpty else {
            result.append(entry)
            continue
        }
        // A node's entries are one per submesh; replace them all at its first.
        guard handled.insert(ObjectIdentifier(node)).inserted else {
            continue
        }
        let position = entry.worldTransform.columns.3.xyz
        let distance = simd_distance(position, cameraPosition)
        guard let level = node.levelsOfDetail.filter({ $0.distance <= distance }).max(by: { $0.distance < $1.distance }) else {
            result += entries.filter { $0.node === node }
            continue
        }
        guard let mesh = level.mesh, case let .mesh(_, materials, _, _) = node.content, let lastMaterial = materials.last else {
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
