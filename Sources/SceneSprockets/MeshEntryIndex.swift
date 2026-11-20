import GeometryLite3D
import SceneSprocketsBVH
import simd

// The graph's mesh entries with a BVH over their posed world bounds, for queries that would otherwise test every entry
// (#337). Entries without bounds can be anywhere, so every query returns them. Skinned and morphed entries use
// conservative posed bounds (#585).
struct MeshEntryIndex {
    var entries: [SceneGraph.MeshEntry]
    var bvh: BVH
    var unbounded: [Int]

    init(entries: [SceneGraph.MeshEntry]) {
        self.entries = entries
        let bounds = entries.map(\.posedWorldBounds)
        bvh = BVH(itemBounds: bounds.map { $0 ?? Self.empty })
        unbounded = entries.indices.filter { bounds[$0] == nil }
    }

    private static let empty = BoundingBox3D(min: .init(repeating: .infinity), max: .init(repeating: -.infinity))

    // The index for `entries`: this one refitted when they are the same submeshes in the same order (only transforms
    // or poses changed), else a new one (#587).
    func updated(for entries: [SceneGraph.MeshEntry]) -> Self {
        guard entries.count == self.entries.count, zip(entries, self.entries).allSatisfy({ $0.nodeID == $1.nodeID && $0.submeshIndex == $1.submeshIndex }) else {
            return Self(entries: entries)
        }
        let bounds = entries.map(\.posedWorldBounds)
        var refitted = self
        guard refitted.bvh.refit(itemBounds: bounds.map { $0 ?? Self.empty }) else {
            return Self(entries: entries)
        }
        refitted.entries = entries
        return refitted
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
        let index = meshEntryIndexCache?.index.updated(for: meshEntries()) ?? MeshEntryIndex(entries: meshEntries())
        meshEntryIndexCache = (revision, index)
        return index
    }

    /// Mesh entries whose posed world bounds (``MeshEntry/posedWorldBounds``) overlap `box`, in traversal order. Entries
    /// without bounds are always included.
    public func meshEntries(overlapping box: BoundingBox3D) -> [MeshEntry] {
        let index = meshEntryIndex()
        return index.indices { bvh, visit in bvh.items(overlapping: box, visit) }.map { index.entries[$0] }
    }

    /// Mesh entries whose posed world bounds (``MeshEntry/posedWorldBounds``) may be inside `frustum`, in traversal order.
    /// Entries without bounds are always included.
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
