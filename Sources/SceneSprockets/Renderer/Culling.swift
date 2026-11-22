import GeometryLite3D
import MetalSprockets
import simd

/// Entries without bounds are kept.
package func culledMeshEntries(_ entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4) -> [SceneGraph.MeshEntry] {
    zip(entries, meshEntriesInFrustum(entries, viewProjection: viewProjection)).filter(\.1).map(\.0)
}

/// Returns, for each mesh entry, whether its bounds may be inside a view frustum.
///
/// For custom ``MaterialRenderer`` types that cull. Entries without bounds count as visible. Far from the
/// world origin, prefer ``meshEntriesInFrustum(_:projectionMatrix:cameraMatrix:)``.
///
/// - Parameters:
///   - entries: The mesh entries to test.
///   - viewProjection: The projection matrix times the view matrix.
/// - Returns: One value per entry, in the same order.
public func meshEntriesInFrustum(_ entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4) -> [Bool] {
    let frustum = Frustum(viewProjection: viewProjection)
    return entries.map { entry in
        guard let bounds = entry.meshBounds else {
            return true
        }
        return frustum.intersects(bounds.transformed(by: entry.worldTransform))
    }
}

/// Returns, for each mesh entry, whether its bounds may be inside the camera's frustum.
///
/// The test is camera-relative, so it stays precise far from the world origin (#257). Entries without bounds count
/// as visible.
///
/// - Parameters:
///   - entries: The mesh entries to test.
///   - projectionMatrix: The camera's projection matrix, for example ``RenderContext/projectionMatrix``.
///   - cameraMatrix: The camera's world transform, for example ``RenderContext/cameraMatrix``.
///   - stereoViews: The views drawn at once, for example ``RenderContext/stereoViews``. With more than one view, an
///     entry is visible if any view's frustum holds it, so an object only one eye sees is not culled (#383).
/// - Returns: One value per entry, in the same order.
public func meshEntriesInFrustum(_ entries: [SceneGraph.MeshEntry], projectionMatrix: simd_float4x4, cameraMatrix: simd_float4x4, stereoViews: StereoViews? = nil) -> [Bool] {
    let cameraPosition = cameraMatrix.columns.3.xyz
    // Every frustum is relative to the same point, so entries move into that space once.
    let frustums: [Frustum] = if let stereoViews, stereoViews.isStereo {
        zip(stereoViews.projectionMatrices, stereoViews.cameraMatrices).map { projection, camera in
            Frustum(viewProjection: projection * camera.cameraRelative(to: cameraPosition).inverse)
        }
    } else {
        [Frustum(viewProjection: projectionMatrix * cameraMatrix.cameraRelative(to: cameraPosition).inverse)]
    }
    return entries.map { entry in
        guard let bounds = entry.meshBounds else {
            return true
        }
        let relative = bounds.transformed(by: entry.worldTransform.cameraRelative(to: cameraPosition))
        return frustums.contains { $0.intersects(relative) }
    }
}

// Sorts by camera distance to each entry's world bounds center (its origin without bounds), farthest first, so
// blended surfaces composite correctly. In stereo, callers pass the center camera, so both eyes draw in the same
// order (#383).
func sortedBackToFront(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    entries
        .map { entry in
            let center = entry.meshBounds.map { ($0.min + $0.max) / 2 } ?? .zero
            let world = entry.worldTransform * SIMD4(center, 1)
            return (entry, simd_distance_squared(SIMD3(world.x, world.y, world.z), cameraPosition))
        }
        .sorted { $0.1 > $1.1 }
        .map(\.0)
}

/// Sorts by distance from the camera to each entry's world origin, nearest first, to reduce overdraw.
package func sortedFrontToBack(_ entries: [SceneGraph.MeshEntry], cameraPosition: SIMD3<Float>) -> [SceneGraph.MeshEntry] {
    // Sorts indices, not entries: MeshEntry is large, so moving it around dominates the sort.
    let distances = entries.map { distanceSquared(from: cameraPosition, toOriginOf: $0.worldTransform) }
    return entries.indices.sorted { distances[$0] < distances[$1] }.map { entries[$0] }
}

/// Spelled out: GeometryLite3D's SIMD4.xyz is generic and not inlinable, so it is slow in per-entry loops.
package func distanceSquared(from position: SIMD3<Float>, toOriginOf transform: simd_float4x4) -> Float {
    let origin = transform.columns.3
    return simd_distance_squared(SIMD3(origin.x, origin.y, origin.z), position)
}
