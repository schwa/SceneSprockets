import GeometryLite3D
import SceneSprocketsBVH
import simd

// The graph's mesh entries with a BVH over their world bounds, for queries that would otherwise test every entry
// (#337). Entries without bounds can be anywhere, so every query returns them; so are skinned and morphed entries,
// which move outside their rest bounds.
struct MeshEntryIndex {
    var entries: [SceneGraph.MeshEntry]
    var bvh: BVH
    var unbounded: [Int]

    init(entries: [SceneGraph.MeshEntry]) {
        self.entries = entries
        let empty = BoundingBox3D(min: .init(repeating: .infinity), max: .init(repeating: -.infinity))
        let isUnbounded = entries.map { $0.meshBounds == nil || $0.skin != nil || !$0.morphTargets.isEmpty }
        let bounds = entries.indices.map { index in
            isUnbounded[index] ? empty : entries[index].meshBounds?.transformed(by: entries[index].worldTransform) ?? empty
        }
        bvh = BVH(itemBounds: bounds)
        unbounded = entries.indices.filter { isUnbounded[$0] }
    }

    // Indices of entries that may pass `query`, in entry (traversal) order.
    func indices(_ query: (BVH, (Int) -> Void) -> Void) -> [Int] {
        var found = unbounded
        query(bvh) { found.append($0) }
        return found.sorted()
    }
}

extension SceneGraph {
    // Cached until the revision changes, like the mesh entries.
    func meshEntryIndex() -> MeshEntryIndex {
        let revision = self.revision
        if let meshEntryIndexCache, meshEntryIndexCache.revision == revision {
            return meshEntryIndexCache.index
        }
        let index = MeshEntryIndex(entries: meshEntries())
        meshEntryIndexCache = (revision, index)
        return index
    }

    /// Mesh entries whose world bounds overlap `box`, in traversal order. Entries without bounds, and skinned or morphed
    /// ones, are always included.
    public func meshEntries(overlapping box: BoundingBox3D) -> [MeshEntry] {
        let index = meshEntryIndex()
        return index.indices { bvh, visit in bvh.items(overlapping: box, visit) }.map { index.entries[$0] }
    }

    /// Mesh entries whose world bounds may be inside `frustum`, in traversal order. Entries without bounds, and skinned
    /// or morphed ones, are always included.
    public func meshEntries(in frustum: Frustum) -> [MeshEntry] {
        let index = meshEntryIndex()
        return index.indices { bvh, visit in bvh.items(in: frustum, visit) }.map { index.entries[$0] }
    }

    // Entries whose world bounds `ray` enters, in traversal order; entries without bounds are included.
    func meshEntries(hitBy ray: Ray3D, maximumDistance: Float) -> [MeshEntry] {
        let index = meshEntryIndex()
        let found = index.indices { bvh, visit in
            bvh.items(hitBy: ray, maximumDistance: maximumDistance) { item in
                visit(item)
                return nil
            }
        }
        return found.map { index.entries[$0] }
    }
}
