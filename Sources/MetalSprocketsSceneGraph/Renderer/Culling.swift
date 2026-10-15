import GeometryLite3D
import simd

// Conservative: false only when all eight corners are outside the same clip plane (Metal clip space, z in 0...w).
func isInFrustum(_ bounds: BoundingBox, viewProjection: simd_float4x4) -> Bool {
    let corners = (0..<8).map { index -> SIMD4<Float> in
        let corner = SIMD3<Float>(
            index & 1 == 0 ? bounds.min.x : bounds.max.x,
            index & 2 == 0 ? bounds.min.y : bounds.max.y,
            index & 4 == 0 ? bounds.min.z : bounds.max.z
        )
        return viewProjection * SIMD4(corner, 1)
    }
    let outsideTests: [(SIMD4<Float>) -> Bool] = [
        { $0.x < -$0.w }, { $0.x > $0.w },
        { $0.y < -$0.w }, { $0.y > $0.w },
        { $0.z < 0 }, { $0.z > $0.w },
    ]
    return !outsideTests.contains { test in corners.allSatisfy(test) }
}

// Entries without bounds are kept.
func culledMeshEntries(_ entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4) -> [SceneGraph.MeshEntry] {
    entries.filter { entry in
        guard let bounds = entry.node.meshBounds else {
            return true
        }
        return isInFrustum(bounds.transformed(by: entry.worldTransform), viewProjection: viewProjection)
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
