import GeometryLite3D
@testable import SceneSprocketsBVH
import simd
import Testing

struct BVHTests {
    // Unit boxes along x, at 0, 2, 4, ...
    func row(_ count: Int) -> [BoundingBox3D] {
        (0 ..< count).map { index in
            let center = SIMD3<Float>(Float(index) * 2, 0, 0)
            return BoundingBox3D(min: center - 0.5, max: center + 0.5)
        }
    }

    func bruteForce(_ boxes: [BoundingBox3D], overlapping box: BoundingBox3D) -> Set<Int> {
        Set(boxes.indices.filter { all(boxes[$0].min .<= box.max) && all(boxes[$0].max .>= box.min) })
    }

    @Test func emptyHierarchyFindsNothing() {
        let bvh = BVH(itemBounds: [])
        var found: [Int] = []
        bvh.items(overlapping: BoundingBox3D(min: [-10, -10, -10], max: [10, 10, 10])) { found.append($0) }
        bvh.items(hitBy: Ray3D(origin: .zero, direction: [1, 0, 0])) { found.append($0); return nil }
        #expect(found.isEmpty && bvh.itemCount == 0)
    }

    @Test func emptyItemBoundsAreLeftOut() {
        let empty = BoundingBox3D(min: .init(repeating: .infinity), max: .init(repeating: -.infinity))
        let bvh = BVH(itemBounds: [row(1)[0], empty])
        #expect(bvh.itemCount == 1)
    }

    // Box queries match a brute-force scan, for random boxes and query regions.
    @Test func overlapMatchesBruteForce() {
        var generator = SystemRandomNumberGenerator()
        let boxes = (0 ..< 500).map { _ in
            let center = SIMD3<Float>.random(in: -50 ... 50, using: &generator)
            let half = SIMD3<Float>.random(in: 0.1 ... 3, using: &generator)
            return BoundingBox3D(min: center - half, max: center + half)
        }
        let bvh = BVH(itemBounds: boxes)
        #expect(bvh.itemCount == 500)
        for _ in 0 ..< 50 {
            let center = SIMD3<Float>.random(in: -50 ... 50, using: &generator)
            let query = BoundingBox3D(min: center - 8, max: center + 8)
            var found = Set<Int>()
            bvh.items(overlapping: query) { found.insert($0) }
            #expect(found == bruteForce(boxes, overlapping: query))
        }
    }

    // A ray visits every box it passes through, nearer subtrees first, and none it misses.
    @Test func rayVisitsCandidatesNearestFirst() {
        let boxes = row(20)
        let bvh = BVH(itemBounds: boxes, leafSize: 1)
        var visited: [Int] = []
        bvh.items(hitBy: Ray3D(origin: [-5, 0, 0], direction: [1, 0, 0])) { item in
            visited.append(item)
            return Float(item) * 2 + 4.5
        }
        #expect(visited == Array(0 ..< 20))
        var missed: [Int] = []
        bvh.items(hitBy: Ray3D(origin: [-5, 5, 0], direction: [1, 0, 0])) { missed.append($0); return nil }
        #expect(missed.isEmpty)
    }

    @Test func nearestOnlySkipsFartherSubtrees() {
        let bvh = BVH(itemBounds: row(64), leafSize: 1)
        var visited: [Int] = []
        bvh.items(hitBy: Ray3D(origin: [-5, 0, 0], direction: [1, 0, 0]), nearestOnly: true) { item in
            visited.append(item)
            return Float(item) * 2 + 4.5
        }
        #expect(visited.first == 0)
        #expect(visited.count < 4, "Visited \(visited)")
    }

    @Test func maximumDistanceLimitsTheRay() {
        let bvh = BVH(itemBounds: row(20), leafSize: 1)
        var visited: [Int] = []
        bvh.items(hitBy: Ray3D(origin: [-5, 0, 0], direction: [1, 0, 0]), maximumDistance: 9) { visited.append($0); return nil }
        #expect(visited.sorted() == [0, 1, 2])
    }

    @Test func frustumQuery() {
        let boxes = row(20)
        let bvh = BVH(itemBounds: boxes)
        let view = LookAt(position: [0, 0, 10], target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .standard(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)
        let frustum = Frustum(viewProjection: projection * view)
        var found = Set<Int>()
        bvh.items(in: frustum) { found.insert($0) }
        #expect(found == Set(boxes.indices.filter { frustum.intersects(boxes[$0]) }))
        #expect(found.contains(0) && !found.contains(19))
    }
}
