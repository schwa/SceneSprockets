import GeometryLite3D
import simd

// Entries without bounds are kept.
public func culledMeshEntries(_ entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4) -> [SceneGraph.MeshEntry] {
    zip(entries, meshEntriesInFrustum(entries, viewProjection: viewProjection)).filter(\.1).map(\.0)
}

// Parallel to `entries`: whether each one may be visible. Entries without bounds are kept.
public func meshEntriesInFrustum(_ entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4) -> [Bool] {
    let frustum = Frustum(viewProjection: viewProjection)
    return entries.map { entry in
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
public func sortedFrontToBack(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    // Sorts indices, not entries: MeshEntry is large, so moving it around dominates the sort.
    let distances = entries.map { distanceSquared(from: cameraPosition, toOriginOf: $0.worldTransform) }
    return entries.indices.sorted { distances[$0] < distances[$1] }.map { entries[$0] }
}

// Spelled out: GeometryLite3D's SIMD4.xyz is generic and not inlinable, so it is slow in per-entry loops.
public func distanceSquared(from position: SIMD3<Float>, toOriginOf transform: simd_float4x4) -> Float {
    let origin = transform.columns.3
    return simd_distance_squared(SIMD3(origin.x, origin.y, origin.z), position)
}
