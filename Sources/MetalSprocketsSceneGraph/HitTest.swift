import GeometryLite3D
import Metal
import MetalSupport
import SwiftMesh
import simd

extension SceneGraph {
    public struct Ray: Sendable, Equatable {
        public var origin: SIMD3<Float>
        // Normalized by the initializer.
        public var direction: SIMD3<Float>

        public init(origin: SIMD3<Float>, direction: SIMD3<Float>) {
            self.origin = origin
            self.direction = simd_normalize(direction)
        }

        // The ray through `point` (in view coordinates, origin top-left) of a view of `viewSize`.
        // `projectionMatrix` must map to Metal clip space; standard and reversed depth both work.
        public init(viewPoint point: SIMD2<Float>, viewSize: SIMD2<Float>, cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4) {
            let ndc = SIMD2<Float>(point.x / viewSize.x * 2 - 1, 1 - point.y / viewSize.y * 2)
            let inverse = cameraMatrix * projectionMatrix.inverse
            func unproject(_ depth: Float) -> SIMD3<Float> {
                let world = inverse * SIMD4(ndc.x, ndc.y, depth, 1)
                return SIMD3(world.x, world.y, world.z) / world.w
            }
            let first = unproject(0)
            let second = unproject(1)
            // With reversed depth, z = 1 is the near plane.
            let cameraPosition = SIMD3(cameraMatrix.columns.3.x, cameraMatrix.columns.3.y, cameraMatrix.columns.3.z)
            let (near, far) = simd_distance_squared(first, cameraPosition) <= simd_distance_squared(second, cameraPosition) ? (first, second) : (second, first)
            self.init(origin: near, direction: far - near)
        }
    }

    public struct Hit {
        public var node: Node
        public var submeshIndex: Int
        public var triangleIndex: Int
        // World-space distance from the ray origin.
        public var distance: Float
        public var position: SIMD3<Float>
        // World-space face normal, facing the ray origin.
        public var normal: SIMD3<Float>
    }

    // Every triangle hit by `ray`, nearest first. Uses CPU-deformed geometry for skinned and morphed meshes.
    // Only triangle and triangle strip submeshes can be hit; vertex buffers must be CPU-visible.
    // Only nodes whose categoryBitMask shares a bit with `categoryBitMask` can be hit.
    public func hitTest(_ ray: Ray, categoryBitMask: UInt = .max) -> [Hit] {
        let revision = self.revision
        var hits: [Hit] = []
        var positionsCache: [PositionsKey: [SIMD3<Float>]] = [:]
        for entry in meshEntries() where entry.node.categoryBitMask & categoryBitMask != 0 {
            let deformed = entry.deformed(revision: revision)
            let mesh = deformed?.mesh ?? entry.mesh
            let modelMatrix = deformed?.modelMatrix ?? entry.worldTransform
            let submesh = mesh.submeshes[entry.submeshIndex]
            guard submesh.primitiveType == .triangle || submesh.primitiveType == .triangleStrip else {
                continue
            }
            let inverse = modelMatrix.inverse
            let localOrigin = (inverse * SIMD4(ray.origin, 1)).xyz
            let localDirection = (inverse * SIMD4(ray.direction, 0)).xyz
            if let bounds = submesh.bounds ?? (deformed == nil ? entry.node.meshBounds : nil), !intersects(origin: localOrigin, direction: localDirection, bounds: bounds) {
                continue
            }
            let key = PositionsKey(buffers: mesh.vertexBuffers.values.map { ObjectIdentifier($0) }.sorted { $0.hashValue < $1.hashValue }, offsets: mesh.vertexBufferOffsets, vertexCount: mesh.vertexCount)
            let positions = positionsCache[key] ?? mesh.positions()
            positionsCache[key] = positions
            guard !positions.isEmpty else {
                continue
            }
            let indices = submesh.indices
            let triangleCount = submesh.primitiveType == .triangle ? indices.count / 3 : max(indices.count - 2, 0)
            for triangle in 0..<triangleCount {
                let (a, b, c): (UInt32, UInt32, UInt32) = submesh.primitiveType == .triangle
                    ? (indices[triangle * 3], indices[triangle * 3 + 1], indices[triangle * 3 + 2])
                    : (indices[triangle], indices[triangle + 1], indices[triangle + 2])
                guard Int(max(a, b, c)) < positions.count,
                      let t = intersect(origin: localOrigin, direction: localDirection, positions[Int(a)], positions[Int(b)], positions[Int(c)])
                else {
                    continue
                }
                let position = (modelMatrix * SIMD4(localOrigin + localDirection * t, 1)).xyz
                let localNormal = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
                var normal = simd_normalize((inverse.transpose * SIMD4(localNormal, 0)).xyz)
                if simd_dot(normal, ray.direction) > 0 {
                    normal = -normal
                }
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: triangle, distance: simd_distance(ray.origin, position), position: position, normal: normal))
            }
        }
        return hits.sorted { $0.distance < $1.distance }
    }
}

private struct PositionsKey: Hashable {
    var buffers: [ObjectIdentifier]
    var offsets: [Int: Int]
    var vertexCount: Int
}

// Möller–Trumbore; returns the ray parameter, or nil for a miss or a hit behind the origin. Both faces count.
private func intersect(origin: SIMD3<Float>, direction: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>) -> Float? {
    let edge1 = b - a
    let edge2 = c - a
    let p = simd_cross(direction, edge2)
    let determinant = simd_dot(edge1, p)
    guard abs(determinant) > 1e-12 else {
        return nil
    }
    let inverseDeterminant = 1 / determinant
    let s = origin - a
    let u = simd_dot(s, p) * inverseDeterminant
    guard u >= 0, u <= 1 else {
        return nil
    }
    let q = simd_cross(s, edge1)
    let v = simd_dot(direction, q) * inverseDeterminant
    guard v >= 0, u + v <= 1 else {
        return nil
    }
    let t = simd_dot(edge2, q) * inverseDeterminant
    return t >= 0 ? t : nil
}

// Slab test.
private func intersects(origin: SIMD3<Float>, direction: SIMD3<Float>, bounds: BoundingBox) -> Bool {
    var near = -Float.infinity
    var far = Float.infinity
    for axis in 0..<3 {
        if direction[axis] == 0 {
            if origin[axis] < bounds.min[axis] || origin[axis] > bounds.max[axis] {
                return false
            }
            continue
        }
        let t1 = (bounds.min[axis] - origin[axis]) / direction[axis]
        let t2 = (bounds.max[axis] - origin[axis]) / direction[axis]
        near = max(near, min(t1, t2))
        far = min(far, max(t1, t2))
    }
    return near <= far && far >= 0
}

extension MetalMesh {
    // float3 positions read from the vertex buffers; empty if there are none.
    public func positions() -> [SIMD3<Float>] {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == .position }),
              attribute.format == .float3,
              let buffer = vertexBuffers[attribute.bufferIndex]
        else {
            return []
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12
        let base = buffer.contents().advanced(by: (vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset)
        return (0..<vertexCount).map { index in
            let pointer = base.advanced(by: index * stride)
            return SIMD3(pointer.loadUnaligned(fromByteOffset: 0, as: Float.self), pointer.loadUnaligned(fromByteOffset: 4, as: Float.self), pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
        }
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
