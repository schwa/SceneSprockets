import GeometryLite3D
import SceneSprocketsBVH
import simd
import SwiftMesh

extension SceneGraph {
    /// The point of a mesh nearest to a world point.
    public struct NearestPoint {
        /// The node of the mesh.
        public var node: Node
        public var submeshIndex: Int
        public var triangleIndex: Int
        /// World-space distance from the query point.
        public var distance: Float
        /// The nearest point, in world space.
        public var position: SIMD3<Float>
        /// Weights of the triangle's three vertices at `position`.
        public var barycentric: SIMD3<Float>
        public var vertexIndices: SIMD3<UInt32>
    }

    /// The point of any visible mesh triangle nearest to `point`, within `maximumDistance`.
    ///
    /// Triangles are compared in each mesh's own space, so for a node scaled non-uniformly the result can be a slightly
    /// farther point of the same mesh. Only triangle and triangle strip submeshes count; skinned and morphed meshes count
    /// as deformed on the CPU.
    public func nearestPoint(to point: SIMD3<Float>, maximumDistance: Float = .infinity, categoryBitMask: UInt = .max) -> NearestPoint? {
        let index = meshEntryIndex()
        let revision = self.revision
        var best: NearestPoint?
        // World squared distance of the entry's nearest point, recording it if nearer than `best`.
        func test(_ item: Int) -> Float? {
            guard let found = nearestPoint(in: index.entries[item], to: point, revision: revision, categoryBitMask: categoryBitMask) else {
                return nil
            }
            if found.distance < best?.distance ?? .infinity {
                best = found
            }
            return found.distance * found.distance
        }
        index.bvh.nearest(to: point, maximumDistance: maximumDistance, test)
        for item in index.unbounded {
            _ = test(item)
        }
        guard let best, best.distance <= maximumDistance else {
            return nil
        }
        return best
    }

    private func nearestPoint(in entry: MeshEntry, to point: SIMD3<Float>, revision: Revision, categoryBitMask: UInt) -> NearestPoint? {
        guard entry.node.categoryBitMask & categoryBitMask != 0 else {
            return nil
        }
        let geometry = HitTestGeometryCache.shared
        let deformed = entry.deformed(revision: revision)
        let mesh = (deformed?.mesh ?? entry.mesh).cpuReadable()
        let modelMatrix = deformed?.modelMatrix ?? entry.worldTransform
        let submesh = mesh.submeshes[entry.submeshIndex]
        guard submesh.primitiveType == .triangle || submesh.primitiveType == .triangleStrip else {
            return nil
        }
        let positions = geometry.positions(of: mesh)
        guard !positions.isEmpty else {
            return nil
        }
        let localPoint = (modelMatrix.inverse * SIMD4(point, 1)).xyz
        var nearest: (vertices: SIMD3<UInt32>, number: Int, closest: TriangleClosestPoint, distanceSquared: Float)?
        // Local squared distance to one triangle, keeping the nearest.
        func test(_ vertices: SIMD3<UInt32>, number: Int) -> Float? {
            guard Int(vertices.max()) < positions.count else {
                return nil
            }
            let closest = closestPoint(onTriangle: positions[Int(vertices.x)], positions[Int(vertices.y)], positions[Int(vertices.z)], to: localPoint)
            let distanceSquared = simd_distance_squared(closest.point, localPoint)
            if distanceSquared < nearest?.distanceSquared ?? .infinity {
                nearest = (vertices, number, closest, distanceSquared)
            }
            return distanceSquared
        }
        if deformed == nil, let triangles = geometry.triangles(of: mesh, submesh: submesh) {
            triangles.bvh.nearest(to: localPoint) { item in test(triangles.vertices[item], number: triangles.numbers[item]) }
        } else {
            let restartIndex: UInt32 = submesh.indexType == .uint16 ? 0xFFFF : 0xFFFF_FFFF
            let (vertices, numbers) = assembleTriangles(geometry.indices(of: submesh), isStrip: submesh.primitiveType == .triangleStrip, restartIndex: restartIndex)
            for (vertices, number) in zip(vertices, numbers) {
                _ = test(vertices, number: number)
            }
        }
        guard let nearest else {
            return nil
        }
        let position = (modelMatrix * SIMD4(nearest.closest.point, 1)).xyz
        return NearestPoint(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: nearest.number, distance: simd_distance(position, point), position: position, barycentric: nearest.closest.barycentrics, vertexIndices: nearest.vertices)
    }
}
