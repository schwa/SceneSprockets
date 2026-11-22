import GeometryLite3D
import Metal
import MetalSupport
import simd
import SwiftMesh

extension SceneGraph {
    /// A place where a ray hits a mesh.
    public struct Hit {
        /// The node of the mesh.
        public var node: Node
        /// The index of the submesh that the ray hits.
        public var submeshIndex: Int
        /// -1 for bounding box hits.
        public var triangleIndex: Int
        /// World-space distance from the ray origin.
        public var distance: Float
        /// The world-space position of the hit.
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
        /// For an instanced mesh, the index of the copy that the ray hits; nil for other meshes.
        public var instanceIndex: Int?

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

    /// Options for a hit test, like SceneKit's `SCNHitTestOption`.
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

        /// Creates hit test options. The default options hit every visible mesh triangle.
        public init(categoryBitMask: UInt = .max, backFaceCulling: Bool = false, boundingBoxOnly: Bool = false, firstFoundOnly: Bool = false, maximumDistance: Float = .infinity, rootNode: Node? = nil) {
            self.categoryBitMask = categoryBitMask
            self.backFaceCulling = backFaceCulling
            self.boundingBoxOnly = boundingBoxOnly
            self.firstFoundOnly = firstFoundOnly
            self.maximumDistance = maximumDistance
            self.rootNode = rootNode
        }
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

    /// Returns every place where a world-space ray hits a mesh, nearest first.
    ///
    /// Only triangle and triangle strip submeshes can be hit. The vertex buffers must be CPU-visible. Skinned and morphed
    /// meshes are hit as deformed on the CPU. `options.categoryBitMask` limits the hits to nodes whose
    /// `categoryBitMask` shares a bit with it.
    public func hitTest(_ ray: Ray3D, options: HitTestOptions = HitTestOptions()) -> [Hit] {
        let revision = self.revision
        var hits: [Hit] = []
        let geometry = HitTestGeometryCache.shared
        // Only entries whose world bounds the ray enters (#337).
        let entries = meshEntries(hitBy: ray, maximumDistance: options.maximumDistance).filter { entry in
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
            // Private-storage buffers are read through shared copies (#303).
            let mesh = (deformed?.mesh ?? entry.mesh).cpuReadable()
            let modelMatrix = deformed?.modelMatrix ?? entry.worldTransform
            let submesh = mesh.submeshes[entry.submeshIndex]
            guard submesh.primitiveType == .triangle || submesh.primitiveType == .triangleStrip else {
                continue
            }
            let inverse = modelMatrix.inverse
            let localRay = Ray3D(origin: (inverse * SIMD4(ray.origin, 1)).xyz, direction: (inverse * SIMD4(ray.direction, 0)).xyz)
            let bounds = submesh.bounds ?? (deformed == nil ? entry.meshBounds : nil)
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
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: -1, distance: distance, position: position, normal: simd_normalize((inverse.transpose * SIMD4(boxHit.normal, 0)).xyz), localPosition: localPosition, barycentric: .zero, vertexIndices: .zero, mesh: nil, instanceIndex: entry.instanceIndex))
                continue
            }
            let positions = geometry.positions(of: mesh)
            guard !positions.isEmpty else {
                continue
            }
            // Tests one triangle; returns its local hit distance, for the BVH to skip farther boxes.
            func test(_ vertices: SIMD3<UInt32>, number: Int) -> Float? {
                let (a, b, c) = (vertices.x, vertices.y, vertices.z)
                guard Int(max(a, b, c)) < positions.count,
                      let triangleHit = localRay.intersect(triangle: positions[Int(a)], positions[Int(b)], positions[Int(c)], cullBackFaces: options.backFaceCulling)
                else {
                    return nil
                }
                let localPosition = localRay.point(at: triangleHit.distance)
                let position = (modelMatrix * SIMD4(localPosition, 1)).xyz
                let distance = simd_distance(ray.origin, position)
                guard distance <= options.maximumDistance else {
                    return nil
                }
                let localNormal = simd_cross(positions[Int(b)] - positions[Int(a)], positions[Int(c)] - positions[Int(a)])
                var normal = simd_normalize((inverse.transpose * SIMD4(localNormal, 0)).xyz)
                if simd_dot(normal, ray.direction) > 0 {
                    normal = -normal
                }
                hits.append(Hit(node: entry.node, submeshIndex: entry.submeshIndex, triangleIndex: number, distance: distance, position: position, normal: normal, localPosition: localPosition, barycentric: triangleHit.barycentrics, vertexIndices: vertices, mesh: mesh, instanceIndex: entry.instanceIndex))
                return triangleHit.distance
            }
            if deformed == nil, let triangles = geometry.triangles(of: mesh, submesh: submesh) {
                // Static meshes: only triangles whose boxes the ray enters (#337).
                let hitCount = hits.count
                triangles.bvh.items(hitBy: localRay, nearestOnly: options.firstFoundOnly) { item in
                    guard !options.firstFoundOnly || hits.count == hitCount else {
                        return nil
                    }
                    return test(triangles.vertices[item], number: triangles.numbers[item])
                }
            } else {
                // Deformed meshes get new buffers every pose, so a BVH would be built for one test.
                let restartIndex: UInt32 = submesh.indexType == .uint16 ? 0xFFFF : 0xFFFF_FFFF
                let (vertices, numbers) = assembleTriangles(geometry.indices(of: submesh), isStrip: submesh.primitiveType == .triangleStrip, restartIndex: restartIndex)
                for (vertices, number) in zip(vertices, numbers) where test(vertices, number: number) != nil && options.firstFoundOnly {
                    break
                }
            }
        }
        return hits.sorted { $0.distance < $1.distance }
    }
}

extension MetalMesh {
    // float2 values of `semantic` read from the vertex buffers; nil if there is no such float2 attribute.
    // swiftlint:disable:next discouraged_optional_collection - nil means the attribute is absent
    func float2Values(_ semantic: VertexDescriptor.Attribute.Semantic) -> [SIMD2<Float>]? {
        floatValues(semantic, minimumComponents: 2)?.map { SIMD2($0.x, $0.y) }
    }

    /// Positions read from the vertex buffers as floats, whatever their vertex format; empty if there are none.
    public func positions() -> [SIMD3<Float>] {
        float3Values(.position) ?? []
    }

    // float3 values of `semantic` read from the vertex buffers; nil if there is no such float3 attribute.
    // swiftlint:disable:next discouraged_optional_collection - nil means the attribute is absent
    func float3Values(_ semantic: VertexDescriptor.Attribute.Semantic) -> [SIMD3<Float>]? {
        floatValues(semantic, minimumComponents: 3)?.map { SIMD3($0.x, $0.y, $0.z) }
    }

    // The values of `semantic` as floats, whatever their vertex format: float, half, or normalized or plain
    // integers (#405). Missing components are zero. Nil if there is no such attribute, it has fewer than
    // `minimumComponents` components, or its format is not one of these.
    // swiftlint:disable:next discouraged_optional_collection - nil means the attribute is absent or unreadable
    func floatValues(_ semantic: VertexDescriptor.Attribute.Semantic, minimumComponents: Int) -> [SIMD4<Float>]? {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == semantic }),
              let decoding = VertexComponentDecoding(attribute.format),
              decoding.count >= minimumComponents,
              let buffer = vertexBuffers[attribute.bufferIndex]
        else {
            return nil
        }
        let stride = vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? attribute.format.size
        let base = buffer.cpuReadable.contents().advanced(by: (vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset)
        return (0..<vertexCount).map { index in
            decoding.decode(UnsafeRawPointer(base.advanced(by: index * stride)))
        }
    }
}

// How to turn one vertex attribute of a Metal vertex format into floats.
private struct VertexComponentDecoding {
    enum Scalar {
        case float, half
        case uint8(normalized: Bool), int8(normalized: Bool), uint16(normalized: Bool), int16(normalized: Bool)
        case uint32, int32

        var size: Int {
            switch self {
            case .float, .uint32, .int32: 4
            case .half, .uint16, .int16: 2
            case .uint8, .int8: 1
            }
        }
    }

    var scalar: Scalar
    var count: Int

    init?(_ format: MTLVertexFormat) {
        switch format {
        case .float: (scalar, count) = (.float, 1)
        case .float2: (scalar, count) = (.float, 2)
        case .float3: (scalar, count) = (.float, 3)
        case .float4: (scalar, count) = (.float, 4)
        case .half: (scalar, count) = (.half, 1)
        case .half2: (scalar, count) = (.half, 2)
        case .half3: (scalar, count) = (.half, 3)
        case .half4: (scalar, count) = (.half, 4)
        case .ucharNormalized, .uchar: (scalar, count) = (.uint8(normalized: format == .ucharNormalized), 1)
        case .uchar2Normalized, .uchar2: (scalar, count) = (.uint8(normalized: format == .uchar2Normalized), 2)
        case .uchar3Normalized, .uchar3: (scalar, count) = (.uint8(normalized: format == .uchar3Normalized), 3)
        case .uchar4Normalized, .uchar4: (scalar, count) = (.uint8(normalized: format == .uchar4Normalized), 4)
        case .charNormalized, .char: (scalar, count) = (.int8(normalized: format == .charNormalized), 1)
        case .char2Normalized, .char2: (scalar, count) = (.int8(normalized: format == .char2Normalized), 2)
        case .char3Normalized, .char3: (scalar, count) = (.int8(normalized: format == .char3Normalized), 3)
        case .char4Normalized, .char4: (scalar, count) = (.int8(normalized: format == .char4Normalized), 4)
        case .ushortNormalized, .ushort: (scalar, count) = (.uint16(normalized: format == .ushortNormalized), 1)
        case .ushort2Normalized, .ushort2: (scalar, count) = (.uint16(normalized: format == .ushort2Normalized), 2)
        case .ushort3Normalized, .ushort3: (scalar, count) = (.uint16(normalized: format == .ushort3Normalized), 3)
        case .ushort4Normalized, .ushort4: (scalar, count) = (.uint16(normalized: format == .ushort4Normalized), 4)
        case .shortNormalized, .short: (scalar, count) = (.int16(normalized: format == .shortNormalized), 1)
        case .short2Normalized, .short2: (scalar, count) = (.int16(normalized: format == .short2Normalized), 2)
        case .short3Normalized, .short3: (scalar, count) = (.int16(normalized: format == .short3Normalized), 3)
        case .short4Normalized, .short4: (scalar, count) = (.int16(normalized: format == .short4Normalized), 4)
        case .uint: (scalar, count) = (.uint32, 1)
        case .uint2: (scalar, count) = (.uint32, 2)
        case .uint3: (scalar, count) = (.uint32, 3)
        case .uint4: (scalar, count) = (.uint32, 4)
        case .int: (scalar, count) = (.int32, 1)
        case .int2: (scalar, count) = (.int32, 2)
        case .int3: (scalar, count) = (.int32, 3)
        case .int4: (scalar, count) = (.int32, 4)
        default: return nil
        }
    }

    func decode(_ pointer: UnsafeRawPointer) -> SIMD4<Float> {
        var result = SIMD4<Float>.zero
        for component in 0..<count {
            let offset = component * scalar.size
            result[component] = switch scalar {
            case .float: pointer.loadUnaligned(fromByteOffset: offset, as: Float.self)
            case .half: Float(pointer.loadUnaligned(fromByteOffset: offset, as: Float16.self))
            case let .uint8(normalized): Float(pointer.loadUnaligned(fromByteOffset: offset, as: UInt8.self)) / (normalized ? 255 : 1)
            case let .uint16(normalized): Float(pointer.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) / (normalized ? 65_535 : 1)
            case let .int8(normalized): Self.signed(Float(pointer.loadUnaligned(fromByteOffset: offset, as: Int8.self)), maximum: 127, normalized: normalized)
            case let .int16(normalized): Self.signed(Float(pointer.loadUnaligned(fromByteOffset: offset, as: Int16.self)), maximum: 32_767, normalized: normalized)
            case .uint32: Float(pointer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
            case .int32: Float(pointer.loadUnaligned(fromByteOffset: offset, as: Int32.self))
            }
        }
        return result
    }

    // Signed normalized values clamp -128 and -32768 to -1, as Metal does.
    private static func signed(_ value: Float, maximum: Float, normalized: Bool) -> Float {
        guard normalized else {
            return value
        }
        return max(value / maximum, -1)
    }
}
