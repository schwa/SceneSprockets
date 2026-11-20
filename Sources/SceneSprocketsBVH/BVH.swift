import GeometryLite3D
import simd

/// A bounding volume hierarchy over items with axis-aligned boxes: triangles of a mesh, or nodes of a scene.
///
/// The hierarchy holds item indices, not items. Queries call back with indices, so the caller does the exact test
/// (a triangle, or a node's own bounds) only for items whose box passes. It is static: rebuild it when items move.
public struct BVH: Sendable {
    struct Node: Sendable {
        var bounds: BoundingBox3D
        /// Leaf: first index into `itemIndices`. Interior: index of the right child (the left child follows this node).
        var start: Int
        /// Items in a leaf; 0 for an interior node.
        var leafItems: Int
        var isLeaf: Bool { leafItems != 0 }
    }

    var nodes: [Node]
    /// Item indices, grouped so that each leaf's items are contiguous.
    var itemIndices: [Int]
    /// Each item's box, indexed by item.
    let itemBounds: [BoundingBox3D]

    /// Items with empty bounds are left out.
    public var itemCount: Int { itemIndices.count }

    /// The bounds of every item; empty when there are none.
    public var bounds: BoundingBox3D { nodes.first?.bounds ?? BoundingBox3D(min: .init(repeating: .infinity), max: .init(repeating: -.infinity)) }

    /// - Parameters:
    ///   - itemBounds: One box per item, indexed by item. Items whose box is empty (min > max) are left out.
    ///   - leafSize: The most items in one leaf.
    public init(itemBounds: [BoundingBox3D], leafSize: Int = 4) {
        precondition(leafSize > 0)
        var indices = itemBounds.indices.filter { itemBounds[$0].min.x <= itemBounds[$0].max.x && itemBounds[$0].min.y <= itemBounds[$0].max.y && itemBounds[$0].min.z <= itemBounds[$0].max.z }
        let centers = itemBounds.map { ($0.min + $0.max) * 0.5 }
        var nodes: [Node] = []
        nodes.reserveCapacity(max(2 * indices.count / leafSize, 1))
        if !indices.isEmpty {
            Self.build(&nodes, &indices, range: 0 ..< indices.count, itemBounds: itemBounds, centers: centers, leafSize: leafSize)
        }
        self.nodes = nodes
        itemIndices = indices
        self.itemBounds = itemBounds
    }

    // Splits at the median of the item centers along the longest axis of their extent.
    private static func build(_ nodes: inout [Node], _ indices: inout [Int], range: Range<Int>, itemBounds: [BoundingBox3D], centers: [SIMD3<Float>], leafSize: Int) {
        var bounds = itemBounds[indices[range.lowerBound]]
        var centerMin = centers[indices[range.lowerBound]]
        var centerMax = centerMin
        for position in range {
            let item = indices[position]
            bounds = BoundingBox3D(min: simd.min(bounds.min, itemBounds[item].min), max: simd.max(bounds.max, itemBounds[item].max))
            centerMin = simd.min(centerMin, centers[item])
            centerMax = simd.max(centerMax, centers[item])
        }
        let nodeIndex = nodes.count
        nodes.append(Node(bounds: bounds, start: range.lowerBound, leafItems: range.count))
        let extent = centerMax - centerMin
        guard range.count > leafSize, extent.max() > 0 else {
            return
        }
        let axis = extent.x >= extent.y && extent.x >= extent.z ? 0 : (extent.y >= extent.z ? 1 : 2)
        let middle = range.lowerBound + range.count / 2
        indices[range].sort { centers[$0][axis] < centers[$1][axis] }
        build(&nodes, &indices, range: range.lowerBound ..< middle, itemBounds: itemBounds, centers: centers, leafSize: leafSize)
        nodes[nodeIndex].start = nodes.count
        nodes[nodeIndex].leafItems = 0
        build(&nodes, &indices, range: middle ..< range.upperBound, itemBounds: itemBounds, centers: centers, leafSize: leafSize)
    }

    /// Calls `visit` with every item whose box overlaps `box`.
    public func items(overlapping box: BoundingBox3D, _ visit: (Int) -> Void) {
        items(where: { all($0.min .<= box.max) && all($0.max .>= box.min) }, visit)
    }

    /// Calls `visit` with every item whose box may be inside `frustum`.
    public func items(in frustum: Frustum, _ visit: (Int) -> Void) {
        items(where: { frustum.intersects($0) }, visit)
    }

    /// Calls `visit` with every item whose box passes `test`. `test` must also pass every box that contains a
    /// passing box, as overlap and containment tests do.
    public func items(where test: (BoundingBox3D) -> Bool, _ visit: (Int) -> Void) {
        guard !nodes.isEmpty else {
            return
        }
        var stack = [0]
        while let index = stack.popLast() {
            let node = nodes[index]
            guard test(node.bounds) else {
                continue
            }
            if node.isLeaf {
                for position in node.start ..< node.start + node.leafItems where test(itemBounds[itemIndices[position]]) {
                    visit(itemIndices[position])
                }
            } else {
                stack.append(node.start)
                stack.append(index + 1)
            }
        }
    }

    /// Calls `visit` with each item whose box the ray enters within `maximumDistance`, nearer boxes' subtrees first.
    /// `visit` returns the distance of the item's own hit, or nil for a miss. Subtrees entered beyond the nearest hit so
    /// far are skipped when `nearestOnly` is true; otherwise every candidate is visited.
    public func items(hitBy ray: Ray3D, maximumDistance: Float = .infinity, nearestOnly: Bool = false, _ visit: (Int) -> Float?) {
        guard !nodes.isEmpty else {
            return
        }
        var limit = maximumDistance
        var stack: [(index: Int, entry: Float)] = []
        if let entry = Self.entryDistance(ray, nodes[0].bounds), entry <= limit {
            stack.append((0, entry))
        }
        while let (index, entry) = stack.popLast() {
            guard entry <= limit else {
                continue
            }
            let node = nodes[index]
            if node.isLeaf {
                for position in node.start ..< node.start + node.leafItems {
                    if let distance = visit(itemIndices[position]), nearestOnly {
                        limit = min(limit, distance)
                    }
                }
                continue
            }
            // Push the farther child first, so the nearer one is visited next.
            let children = [index + 1, node.start].compactMap { child in Self.entryDistance(ray, nodes[child].bounds).map { (child, $0) } }
            for child in children.sorted(by: { $0.1 > $1.1 }) where child.1 <= limit {
                stack.append((child.0, child.1))
            }
        }
    }

    // Distance along the ray to where it enters `box` (0 from inside), or nil if it misses.
    static func entryDistance(_ ray: Ray3D, _ box: BoundingBox3D) -> Float? {
        let inverseDirection = 1 / ray.direction
        let t1 = (box.min - ray.origin) * inverseDirection
        let t2 = (box.max - ray.origin) * inverseDirection
        var near = simd.min(t1, t2)
        var far = simd.max(t1, t2)
        // A zero direction component gives NaN on a face plane; decide those slabs from the origin alone.
        let parallel = ray.direction .== 0
        let inside = (ray.origin .>= box.min) .& (ray.origin .<= box.max)
        let infinity = SIMD3<Float>(repeating: .infinity)
        near.replace(with: infinity.replacing(with: -infinity, where: inside), where: parallel)
        far.replace(with: (-infinity).replacing(with: infinity, where: inside), where: parallel)
        let entry = near.max()
        let exit = far.min()
        guard entry <= exit, exit >= 0 else {
            return nil
        }
        return max(entry, 0)
    }
}
