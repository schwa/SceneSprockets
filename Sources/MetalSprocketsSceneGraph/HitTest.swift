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
            let cameraPosition = cameraMatrix.columns.3.xyz
            let (near, far) = simd_distance_squared(first, cameraPosition) <= simd_distance_squared(second, cameraPosition) ? (first, second) : (second, first)
            self.init(origin: near, direction: far - near)
        }
    }

    public struct Hit {
        public var node: Node
        public var submeshIndex: Int
        // -1 for bounding box hits.
        public var triangleIndex: Int
        // World-space distance from the ray origin.
        public var distance: Float
        public var position: SIMD3<Float>
        // World-space face normal, facing the ray origin.
        public var normal: SIMD3<Float>
        // The hit point in the mesh's own space (after skinning and morphing).
        public var localPosition: SIMD3<Float>
        // Weights of the triangle's three vertices at the hit point; zero for bounding box hits.
        public var barycentric: SIMD3<Float>
        // The triangle's vertex indices; zero for bounding box hits.
        public var vertexIndices: SIMD3<UInt32>
        var mesh: MetalMesh?

        // The interpolated texture coordinate of set `index` at the hit point, like
        // SCNHitTestResult.textureCoordinates(withMappingChannel:). Nil without float2 coordinates or for box hits.
        public func textureCoordinates(index: Int = 0) -> SIMD2<Float>? {
            guard triangleIndex >= 0, let coordinates = mesh?.float2Values(.texcoord(index)) else {
                return nil
            }
            let (a, b, c) = (Int(vertexIndices.x), Int(vertexIndices.y), Int(vertexIndices.z))
            guard max(a, b, c) < coordinates.count else {
                return nil
            }
            return coordinates[a] * barycentric.x + coordinates[b] * barycentric.y + coordinates[c] * barycentric.z
        }
    }

    // Like SCNHitTestOption.
    public struct HitTestOptions {
        // Only nodes whose categoryBitMask shares a bit with this can be hit.
        public var categoryBitMask: UInt = .max
        // Skips triangles facing away from the ray (counter-clockwise is front).
        public var backFaceCulling = false
        // Tests each mesh's bounding box instead of its triangles.
        public var boundingBoxOnly = false
        // Stops at the first hit found, which is not always the nearest.
        public var firstFoundOnly = false
        // Ignores hits farther than this from the ray origin; segment tests set it.
        public var maximumDistance: Float = .infinity
        // Only this node and its descendants can be hit.
        public var rootNode: Node?

        public init(categoryBitMask: UInt = .max, backFaceCulling: Bool = false, boundingBoxOnly: Bool = false, firstFoundOnly: Bool = false, maximumDistance: Float = .infinity, rootNode: Node? = nil) {
            self.categoryBitMask = categoryBitMask
            self.backFaceCulling = backFaceCulling
            self.boundingBoxOnly = boundingBoxOnly
            self.firstFoundOnly = firstFoundOnly
            self.maximumDistance = maximumDistance
            self.rootNode = rootNode
        }
    }

    // Every triangle hit by `ray`, nearest first. Uses CPU-deformed geometry for skinned and morphed meshes.
    // Only triangle and triangle strip submeshes can be hit; vertex buffers must be CPU-visible.
    // Only nodes whose categoryBitMask shares a bit with `categoryBitMask` can be hit.
    public func hitTest(_ ray: Ray, categoryBitMask: UInt = .max) -> [Hit] {
        hitTest(ray, options: HitTestOptions(categoryBitMask: categoryBitMask))
    }

    // Hits between two world points, nearest first, like SCNNode.hitTestWithSegment(from:to:options:).
    public func hitTest(segmentFrom start: SIMD3<Float>, to end: SIMD3<Float>, options: HitTestOptions = HitTestOptions()) -> [Hit] {
        guard simd_distance(start, end) > 0 else {
            return []
        }
        var options = options
        options.maximumDistance = min(options.maximumDistance, simd_distance(start, end))
        return hitTest(Ray(origin: start, direction: end - start), options: options)
    }

    public func hitTest(_ ray: Ray, options: HitTestOptions) -> [Hit] {
        let revision = self.revision
        var hits: [Hit] = []
        var positionsCache: [PositionsKey: [SIMD3<Float>]] = [:]
        let entries = meshEntries().filter { entry in
            guard entry.node.categoryBitMask & options.categoryBitMask != 0 else {
                return false
            }
            guard let rootNode = options.rootNode else {
                return true
            }
            return entry.node === rootNode || rootNode.isAncestor(of: entry.node)
        }
        for entry in entries {
            if options.firstFoundOnly, !hits.isEmpty {
                break
            }
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
            let bounds = submesh.bounds ?? (deformed == nil ? entry.node.meshBounds : nil)
            if let bounds, !intersects(origin: localOrigin, direction: localDirection, bounds: bounds) {
                continue
            }
            if options.boundingBoxOnly {
                guard let bounds, let (t, localNormal) = boxEntry(origin: localOrigin, direction: localDirection, bounds: bounds) else {
                    continue
                }
                let localPosition = localOrigin + localDirection * t
                let position = (modelMatrix * SIMD4(localPosition, 1)).xyz
                let distance = simd_distance(ray.origin, position)
                guard distance <= options.maximumDistance else {
                    continue
                }
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: -1, distance: distance, position: position, normal: simd_normalize((inverse.transpose * SIMD4(localNormal, 0)).xyz), localPosition: localPosition, barycentric: .zero, vertexIndices: .zero, mesh: nil))
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
                      let (t, u, v) = intersect(origin: localOrigin, direction: localDirection, positions[Int(a)], positions[Int(b)], positions[Int(c)], cullsBackFaces: options.backFaceCulling)
                else {
                    continue
                }
                let localPosition = localOrigin + localDirection * t
                let position = (modelMatrix * SIMD4(localPosition, 1)).xyz
                let distance = simd_distance(ray.origin, position)
                guard distance <= options.maximumDistance else {
                    continue
                }
                let localNormal = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
                var normal = simd_normalize((inverse.transpose * SIMD4(localNormal, 0)).xyz)
                if simd_dot(normal, ray.direction) > 0 {
                    normal = -normal
                }
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: triangle, distance: distance, position: position, normal: normal, localPosition: localPosition, barycentric: [1 - u - v, u, v], vertexIndices: [a, b, c], mesh: mesh))
                if options.firstFoundOnly {
                    break
                }
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

// Möller–Trumbore; returns the ray parameter and the barycentric u (weight of b) and v (weight of c), or nil for a miss
// or a hit behind the origin. Both faces count unless `cullsBackFaces`; counter-clockwise is front.
private func intersect(origin: SIMD3<Float>, direction: SIMD3<Float>, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, cullsBackFaces: Bool) -> (t: Float, u: Float, v: Float)? {
    let edge1 = b - a
    let edge2 = c - a
    let p = simd_cross(direction, edge2)
    let determinant = simd_dot(edge1, p)
    // Positive when the ray meets the front face.
    guard cullsBackFaces ? determinant > 1e-12 : abs(determinant) > 1e-12 else {
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
    return t >= 0 ? (t, u, v) : nil
}

// Where the ray enters the box (or 0 when it starts inside), with the outward normal of the face it enters through.
private func boxEntry(origin: SIMD3<Float>, direction: SIMD3<Float>, bounds: BoundingBox) -> (t: Float, normal: SIMD3<Float>)? {
    var near = -Float.infinity
    var far = Float.infinity
    var normal = SIMD3<Float>.zero
    for axis in 0..<3 {
        if direction[axis] == 0 {
            if origin[axis] < bounds.min[axis] || origin[axis] > bounds.max[axis] {
                return nil
            }
            continue
        }
        let t1 = (bounds.min[axis] - origin[axis]) / direction[axis]
        let t2 = (bounds.max[axis] - origin[axis]) / direction[axis]
        if min(t1, t2) > near {
            near = min(t1, t2)
            normal = .zero
            normal[axis] = direction[axis] > 0 ? -1 : 1
        }
        far = min(far, max(t1, t2))
    }
    guard near <= far, far >= 0 else {
        return nil
    }
    return near >= 0 ? (near, normal) : (0, -simd_normalize(direction))
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
    // float2 values of `semantic` read from the vertex buffers; nil if there is no such float2 attribute.
    func float2Values(_ semantic: VertexDescriptor.Attribute.Semantic) -> [SIMD2<Float>]? {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == semantic }),
              attribute.format == .float2,
              let buffer = vertexBuffers[attribute.bufferIndex]
        else {
            return nil
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 8
        let base = buffer.contents().advanced(by: (vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset)
        return (0..<vertexCount).map { index in
            let pointer = base.advanced(by: index * stride)
            return SIMD2(pointer.loadUnaligned(fromByteOffset: 0, as: Float.self), pointer.loadUnaligned(fromByteOffset: 4, as: Float.self))
        }
    }

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

