import GeometryLite3D
import simd

// Entries without bounds are kept.
func culledMeshEntries(_ entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4) -> [SceneGraph.MeshEntry] {
    let frustum = Frustum(viewProjection: viewProjection)
    return entries.filter { entry in
        guard let bounds = entry.node.meshBounds else {
            return true
        }
        return frustum.intersects(bounds.transformed(by: entry.worldTransform))
    }
}

// Sorts by camera distance to each entry's world bounds center (its origin without bounds), farthest first, so
// blended surfaces composite correctly.
func sortedBackToFront(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    entries
        .map { entry in
            let center = entry.node.meshBounds.map { ($0.min + $0.max) / 2 } ?? .zero
            let world = entry.worldTransform * SIMD4(center, 1)
            return (entry, simd_distance_squared(SIMD3(world.x, world.y, world.z), cameraPosition))
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
}

// Sorts by distance from the camera to each entry's world origin, nearest first, to reduce overdraw.
func sortedFrontToBack(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    entries
        .map { entry in
            let origin = entry.worldTransform.columns.3.xyz
            return (entry, simd_distance_squared(origin, cameraPosition))
        }
        .sorted { $0.1 < $1.1 }
        .map(\.0)
}
