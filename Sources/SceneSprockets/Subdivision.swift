import Metal
import MetalSupport
import simd
import SwiftMesh

extension MetalMesh {
    /// Loop subdivision, like SCNGeometry.subdivisionLevel: each level splits every triangle in four. With `smooth`,
    /// positions move by Loop's rules (vertices with the same position count as one, so texture seams stay closed)
    /// and float3 normals are recomputed; otherwise new vertices sit at edge midpoints. Other float attributes are
    /// interpolated; non-float attributes (such as joint indices) copy an endpoint's value. Nil without float3
    /// positions or with non-triangle submeshes. Runs on the CPU; vertex buffers must be CPU-visible.
    public func subdivided(levels: Int, smooth: Bool = true) -> MetalMesh? {
        guard levels > 0 else {
            return self
        }
        guard submeshes.allSatisfy({ $0.primitiveType == .triangle }), var working = SubdivisionMesh(self) else {
            return nil
        }
        for _ in 0..<levels {
            working.subdivide(smooth: smooth)
        }
        if smooth {
            working.recomputeNormals()
        }
        return working.metalMesh(device: vertexBuffer.device, label: label)
    }
}

private struct SubdivisionMesh {
    struct Attribute {
        var semantic: VertexDescriptor.Attribute.Semantic
        var format: MTLVertexFormat
        // Float components per vertex; 0 for formats copied as bytes.
        var components: Int
        var floats: [Float]
        var bytes: [UInt8]
        var size: Int
    }

    struct Edge: Hashable {
        var low: UInt32
        var high: UInt32

        init(_ a: UInt32, _ b: UInt32) {
            low = min(a, b)
            high = max(a, b)
        }
    }

    var attributes: [Attribute]
    var positionIndex: Int
    var vertexCount: Int
    var submeshes: [(label: String?, indices: [UInt32])]

    init?(_ mesh: MetalMesh) {
        attributes = mesh.vertexAttributeData().map { data in
            let components = switch data.format {
            case .float: 1
            case .float2: 2
            case .float3: 3
            case .float4: 4
            default: 0
            }
            let floats = components == 0 ? [] : data.bytes.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            return Attribute(semantic: data.semantic, format: data.format, components: components, floats: floats, bytes: components == 0 ? data.bytes : [], size: data.format.size)
        }
        guard let positionIndex = attributes.firstIndex(where: { $0.semantic == .position && $0.components == 3 }) else {
            return nil
        }
        self.positionIndex = positionIndex
        vertexCount = mesh.vertexCount
        submeshes = mesh.submeshes.map { ($0.label, $0.indices) }
    }

    func position(_ index: Int) -> SIMD3<Float> {
        let floats = attributes[positionIndex].floats
        return SIMD3(floats[index * 3], floats[index * 3 + 1], floats[index * 3 + 2])
    }

    mutating func setPosition(_ index: Int, _ value: SIMD3<Float>) {
        attributes[positionIndex].floats[index * 3] = value.x
        attributes[positionIndex].floats[index * 3 + 1] = value.y
        attributes[positionIndex].floats[index * 3 + 2] = value.z
    }

    // Vertex index to a shared id for vertices at the same position.
    func weldIDs() -> [Int] {
        var ids: [SIMD3<Float>: Int] = [:]
        return (0..<vertexCount).map { index in
            let position = position(index)
            if let id = ids[position] {
                return id
            }
            ids[position] = ids.count
            return ids.count - 1
        }
    }

    mutating func subdivide(smooth: Bool) {
        let weld = weldIDs()
        let triangles = submeshes.flatMap { submesh in
            stride(from: 0, to: submesh.indices.count - 2, by: 3).map { (submesh.indices[$0], submesh.indices[$0 + 1], submesh.indices[$0 + 2]) }
        }
        // Welded topology: each edge's opposite vertices, and each vertex's neighbors.
        var opposite: [Edge: [UInt32]] = [:]
        var neighbors: [Int: Set<Int>] = [:]
        var weldPosition: [Int: SIMD3<Float>] = [:]
        for (a, b, c) in triangles {
            let (wa, wb, wc) = (UInt32(weld[Int(a)]), UInt32(weld[Int(b)]), UInt32(weld[Int(c)]))
            opposite[Edge(wa, wb), default: []].append(wc)
            opposite[Edge(wb, wc), default: []].append(wa)
            opposite[Edge(wc, wa), default: []].append(wb)
            for (from, to) in [(wa, wb), (wb, wc), (wc, wa)] {
                neighbors[Int(from), default: []].insert(Int(to))
                neighbors[Int(to), default: []].insert(Int(from))
            }
            weldPosition[Int(wa)] = position(Int(a))
            weldPosition[Int(wb)] = position(Int(b))
            weldPosition[Int(wc)] = position(Int(c))
        }
        var boundaryNeighbors: [Int: [Int]] = [:]
        for (edge, faces) in opposite where faces.count == 1 {
            boundaryNeighbors[Int(edge.low), default: []].append(Int(edge.high))
            boundaryNeighbors[Int(edge.high), default: []].append(Int(edge.low))
        }
        func welded(_ id: Int) -> SIMD3<Float> {
            guard let position = weldPosition[id] else {
                fatalError("Subdivision: welded vertex \(id) has no position")
            }
            return position
        }
        func oddPosition(_ edge: Edge) -> SIMD3<Float> {
            let a = welded(Int(edge.low))
            let b = welded(Int(edge.high))
            guard smooth, let faces = opposite[edge], faces.count == 2 else {
                return (a + b) / 2
            }
            return (a + b) * 3 / 8 + (welded(Int(faces[0])) + welded(Int(faces[1]))) / 8
        }
        func evenPosition(_ id: Int) -> SIMD3<Float> {
            let position = welded(id)
            if let boundary = boundaryNeighbors[id] {
                guard boundary.count == 2 else {
                    return position
                }
                return position * 3 / 4 + (welded(boundary[0]) + welded(boundary[1])) / 8
            }
            let around = neighbors[id] ?? []
            let count = Float(around.count)
            guard count > 0 else {
                return position
            }
            let beta: Float = around.count == 3 ? 3 / 16 : 3 / (8 * count)
            return position * (1 - count * beta) + around.reduce(.zero) { $0 + welded($1) } * beta
        }

        // One new vertex per (unwelded) edge, so seams keep their own attributes.
        var edgeVertices: [Edge: UInt32] = [:]
        var newPositions: [SIMD3<Float>] = []
        func midpoint(_ a: UInt32, _ b: UInt32) -> UInt32 {
            let edge = Edge(a, b)
            if let index = edgeVertices[edge] {
                return index
            }
            let index = UInt32(vertexCount + edgeVertices.count)
            edgeVertices[edge] = index
            for attributeIndex in attributes.indices {
                let size = attributes[attributeIndex].components
                if size > 0 {
                    for component in 0..<size {
                        let value = (attributes[attributeIndex].floats[Int(a) * size + component] + attributes[attributeIndex].floats[Int(b) * size + component]) / 2
                        attributes[attributeIndex].floats.append(value)
                    }
                } else {
                    let bytes = attributes[attributeIndex].size
                    attributes[attributeIndex].bytes += attributes[attributeIndex].bytes[(Int(a) * bytes)..<(Int(a) * bytes + bytes)]
                }
            }
            newPositions.append(oddPosition(Edge(UInt32(weld[Int(a)]), UInt32(weld[Int(b)]))))
            return index
        }
        let oldCount = vertexCount
        submeshes = submeshes.map { submesh in
            var indices: [UInt32] = []
            indices.reserveCapacity(submesh.indices.count * 4)
            for start in stride(from: 0, to: submesh.indices.count - 2, by: 3) {
                let (a, b, c) = (submesh.indices[start], submesh.indices[start + 1], submesh.indices[start + 2])
                let ab = midpoint(a, b)
                let bc = midpoint(b, c)
                let ca = midpoint(c, a)
                indices += [a, ab, ca, b, bc, ab, c, ca, bc, ab, bc, ca]
            }
            return (submesh.label, indices)
        }
        if smooth {
            for index in 0..<oldCount {
                setPosition(index, evenPosition(weld[index]))
            }
        }
        for (offset, position) in newPositions.enumerated() {
            setPosition(oldCount + offset, position)
        }
        vertexCount = oldCount + newPositions.count
    }

    // Area-weighted face normals, shared by vertices at the same position.
    mutating func recomputeNormals() {
        guard let normalIndex = attributes.firstIndex(where: { $0.semantic == .normal && $0.components == 3 }) else {
            return
        }
        let weld = weldIDs()
        var sums: [Int: SIMD3<Float>] = [:]
        for submesh in submeshes {
            for start in stride(from: 0, to: submesh.indices.count - 2, by: 3) {
                let (a, b, c) = (Int(submesh.indices[start]), Int(submesh.indices[start + 1]), Int(submesh.indices[start + 2]))
                let normal = simd_cross(position(b) - position(a), position(c) - position(a))
                for index in [a, b, c] {
                    sums[weld[index], default: .zero] += normal
                }
            }
        }
        for index in 0..<vertexCount {
            let sum = sums[weld[index]] ?? .zero
            let normal = simd_length(sum) > 0 ? simd_normalize(sum) : SIMD3<Float>(0, 1, 0)
            attributes[normalIndex].floats[index * 3] = normal.x
            attributes[normalIndex].floats[index * 3 + 1] = normal.y
            attributes[normalIndex].floats[index * 3 + 2] = normal.z
        }
    }

    func metalMesh(device: MTLDevice, label: String?) -> MetalMesh {
        let data = attributes.map { attribute in
            let bytes = attribute.components == 0 ? attribute.bytes : attribute.floats.withUnsafeBytes { Array($0) }
            return MetalMesh.VertexAttributeData(semantic: attribute.semantic, format: attribute.format, bytes: bytes, count: vertexCount)
        }
        return MetalMesh(device: device, attributes: data, submeshes: submeshes.map { MetalMesh.SubmeshIndices(label: $0.label, indices: $0.indices) }, label: label)
    }
}
