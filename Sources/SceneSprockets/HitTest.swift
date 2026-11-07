import GeometryLite3D
import Metal
import MetalSupport
import simd
import SwiftMesh

extension SceneGraph {
    public struct Hit {
        public var node: Node
        public var submeshIndex: Int
        /// -1 for bounding box hits.
        public var triangleIndex: Int
        /// World-space distance from the ray origin.
        public var distance: Float
        public var position: SIMD3<Float>
        /// World-space face normal, facing the ray origin.
        public var normal: SIMD3<Float>
        /// The hit point in the mesh's own space (after skinning and morphing).
        public var localPosition: SIMD3<Float>
        /// Weights of the triangle's three vertices at the hit point; zero for bounding box hits.
        public var barycentric: SIMD3<Float>
        /// The triangle's vertex indices; zero for bounding box hits.
        public var vertexIndices: SIMD3<UInt32>
        var mesh: MetalMesh?

        /// The interpolated texture coordinate of set `index` at the hit point, like
        /// SCNHitTestResult.textureCoordinates(withMappingChannel:). Nil without float2 coordinates or for box hits.
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

    /// Like SCNHitTestOption.
    public struct HitTestOptions {
        /// Only nodes whose categoryBitMask shares a bit with this can be hit.
        public var categoryBitMask: UInt = .max
        /// Skips triangles facing away from the ray (counter-clockwise is front).
        public var backFaceCulling = false
        /// Tests each mesh's bounding box instead of its triangles.
        public var boundingBoxOnly = false
        /// Stops at the first hit found, which is not always the nearest.
        public var firstFoundOnly = false
        /// Ignores hits farther than this from the ray origin; segment tests set it.
        public var maximumDistance: Float = .infinity
        /// Only this node and its descendants can be hit.
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

    /// Every triangle hit by `ray`, nearest first. Uses CPU-deformed geometry for skinned and morphed meshes.
    /// Only triangle and triangle strip submeshes can be hit; vertex buffers must be CPU-visible.
    /// Only nodes whose categoryBitMask shares a bit with `categoryBitMask` can be hit.
    public func hitTest(_ ray: Ray3D, categoryBitMask: UInt = .max) -> [Hit] {
        hitTest(ray, options: HitTestOptions(categoryBitMask: categoryBitMask))
    }

    /// Hits between two world points, nearest first, like SCNNode.hitTestWithSegment(from:to:options:).
    public func hitTest(segmentFrom start: SIMD3<Float>, to end: SIMD3<Float>, options: HitTestOptions = HitTestOptions()) -> [Hit] {
        guard simd_distance(start, end) > 0 else {
            return []
        }
        var options = options
        options.maximumDistance = min(options.maximumDistance, simd_distance(start, end))
        return hitTest(Ray3D(origin: start, direction: end - start), options: options)
    }

    public func hitTest(_ ray: Ray3D, options: HitTestOptions) -> [Hit] {
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
            let localRay = Ray3D(origin: (inverse * SIMD4(ray.origin, 1)).xyz, direction: (inverse * SIMD4(ray.direction, 0)).xyz)
            let bounds = submesh.bounds ?? (deformed == nil ? entry.node.meshBounds : nil)
            let boxHit = bounds.flatMap { localRay.intersect(box: $0) }
            if bounds != nil, boxHit == nil {
                continue
            }
            if options.boundingBoxOnly {
                guard let boxHit else {
                    continue
                }
                let localPosition = localRay.point(at: boxHit.distance)
                let position = (modelMatrix * SIMD4(localPosition, 1)).xyz
                let distance = simd_distance(ray.origin, position)
                guard distance <= options.maximumDistance else {
                    continue
                }
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: -1, distance: distance, position: position, normal: simd_normalize((inverse.transpose * SIMD4(boxHit.normal, 0)).xyz), localPosition: localPosition, barycentric: .zero, vertexIndices: .zero, mesh: nil))
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
                      let triangleHit = localRay.intersect(triangle: positions[Int(a)], positions[Int(b)], positions[Int(c)], cullBackFaces: options.backFaceCulling)
                else {
                    continue
                }
                let localPosition = localRay.point(at: triangleHit.distance)
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
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: triangle, distance: distance, position: position, normal: normal, localPosition: localPosition, barycentric: triangleHit.barycentrics, vertexIndices: [a, b, c], mesh: mesh))
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

extension MetalMesh {
    // float2 values of `semantic` read from the vertex buffers; nil if there is no such float2 attribute.
    // swiftlint:disable:next discouraged_optional_collection - nil means the attribute is absent
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

    /// float3 positions read from the vertex buffers; empty if there are none.
    public func positions() -> [SIMD3<Float>] {
        float3Values(.position) ?? []
    }

    // float3 values of `semantic` read from the vertex buffers; nil if there is no such float3 attribute.
    // swiftlint:disable:next discouraged_optional_collection - nil means the attribute is absent
    func float3Values(_ semantic: VertexDescriptor.Attribute.Semantic) -> [SIMD3<Float>]? {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == semantic }),
              attribute.format == .float3,
              let buffer = vertexBuffers[attribute.bufferIndex]
        else {
            return nil
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12
        let base = buffer.contents().advanced(by: (vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset)
        return (0..<vertexCount).map { index in
            let pointer = base.advanced(by: index * stride)
            return SIMD3(pointer.loadUnaligned(fromByteOffset: 0, as: Float.self), pointer.loadUnaligned(fromByteOffset: 4, as: Float.self), pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
        }
    }
}
