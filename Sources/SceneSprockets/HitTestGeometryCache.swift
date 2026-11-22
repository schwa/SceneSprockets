import Foundation
import GeometryLite3D
import Metal
import SceneSprocketsBVH
import simd
import SwiftMesh

// Positions and indices read from mesh buffers for hit testing, kept while the buffers live, so repeated hit tests
// (hover every frame) do not read static meshes again (#402). Keyed weakly by buffer: a deformed mesh gets new
// buffers, so it gets new entries. A buffer whose contents change in place keeps its old values.
final class HitTestGeometryCache: @unchecked Sendable {
    static let shared = HitTestGeometryCache()

    private struct PositionsKey: Hashable {
        var offset: Int
        var stride: Int
        var vertexCount: Int
    }

    private struct IndicesKey: Hashable {
        var offset: Int
        var count: Int
        var isUInt16: Bool
    }

    private struct TrianglesKey: Hashable {
        var positions: PositionsKey
        var indexBuffer: ObjectIdentifier
        var indices: IndicesKey
        var isStrip: Bool
    }

    // A submesh's triangles (vertex indices and their triangle numbers) and a BVH over them.
    struct Triangles {
        var vertices: [SIMD3<UInt32>]
        var numbers: [Int]
        var bvh: BVH
    }

    private final class Entries {
        var positions: [PositionsKey: [SIMD3<Float>]] = [:]
        var indices: [IndicesKey: [UInt32]] = [:]
        var triangles: [TrianglesKey: Triangles] = [:]
    }

    private let lock = NSLock()
    private let entries = NSMapTable<AnyObject, Entries>(keyOptions: .weakMemory, valueOptions: .strongMemory)

    // Buffers with entries.
    var count: Int {
        lock.withLock { entries.keyEnumerator().allObjects.count }
    }

    var isEmpty: Bool {
        lock.withLock { entries.keyEnumerator().nextObject() == nil }
    }

    private func entries(for buffer: MTLBuffer) -> Entries {
        if let existing = entries.object(forKey: buffer) {
            return existing
        }
        let made = Entries()
        entries.setObject(made, forKey: buffer)
        return made
    }

    // The mesh's positions as floats; empty if it has none. Reads CPU-visible buffers; see `MetalMesh.cpuReadable()`.
    func positions(of mesh: MetalMesh) -> [SIMD3<Float>] {
        guard let attribute = mesh.vertexDescriptor.attributes.first(where: { $0.semantic == .position }), let buffer = mesh.vertexBuffers[attribute.bufferIndex] else {
            return []
        }
        let key = PositionsKey(offset: (mesh.vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset, stride: mesh.vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12, vertexCount: mesh.vertexCount)
        if let cached = lock.withLock({ entries(for: buffer).positions[key] }) {
            return cached
        }
        let positions = mesh.positions()
        lock.withLock { entries(for: buffer).positions[key] = positions }
        return positions
    }

    // The submesh's triangles with a BVH over them, kept with the position buffer. Nil without float3 positions.
    func triangles(of mesh: MetalMesh, submesh: MetalMesh.Submesh) -> Triangles? {
        guard let attribute = mesh.vertexDescriptor.attributes.first(where: { $0.semantic == .position }), attribute.format == .float3, let buffer = mesh.vertexBuffers[attribute.bufferIndex] else {
            return nil
        }
        let positionsKey = PositionsKey(offset: (mesh.vertexBufferOffsets[attribute.bufferIndex] ?? 0) + attribute.offset, stride: mesh.vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12, vertexCount: mesh.vertexCount)
        let key = TrianglesKey(positions: positionsKey, indexBuffer: ObjectIdentifier(submesh.indexBuffer), indices: IndicesKey(offset: submesh.indexBufferOffset, count: submesh.indexCount, isUInt16: submesh.indexType == .uint16), isStrip: submesh.primitiveType == .triangleStrip)
        if let cached = lock.withLock({ entries(for: buffer).triangles[key] }) {
            return cached
        }
        let positions = positions(of: mesh)
        let (vertices, numbers) = assembleTriangles(indices(of: submesh), isStrip: key.isStrip, restartIndex: submesh.indexType == .uint16 ? 0xFFFF : 0xFFFF_FFFF)
        let bounds = vertices.map { triangle -> BoundingBox3D in
            guard Int(triangle.max()) < positions.count else {
                // Out-of-range indices are never hit.
                return BoundingBox3D(min: .init(repeating: .infinity), max: .init(repeating: -.infinity))
            }
            let (a, b, c) = (positions[Int(triangle.x)], positions[Int(triangle.y)], positions[Int(triangle.z)])
            return BoundingBox3D(min: simd_min(a, simd_min(b, c)), max: simd_max(a, simd_max(b, c)))
        }
        let triangles = Triangles(vertices: vertices, numbers: numbers, bvh: BVH(itemBounds: bounds))
        lock.withLock { entries(for: buffer).triangles[key] = triangles }
        return triangles
    }

    func indices(of submesh: MetalMesh.Submesh) -> [UInt32] {
        let key = IndicesKey(offset: submesh.indexBufferOffset, count: submesh.indexCount, isUInt16: submesh.indexType == .uint16)
        if let cached = lock.withLock({ entries(for: submesh.indexBuffer).indices[key] }) {
            return cached
        }
        let indices = submesh.indices
        lock.withLock { entries(for: submesh.indexBuffer).indices[key] = indices }
        return indices
    }
}

// Each triangle's vertex indices, and its triangle number (its position in the list, or in the strip, counting
// restart indices). Strips break at the primitive restart index, and each piece keeps its own winding (#404); odd strip
// triangles swap their first two vertices to keep the strip's winding (#403).
func assembleTriangles(_ indices: [UInt32], isStrip: Bool, restartIndex: UInt32) -> (vertices: [SIMD3<UInt32>], numbers: [Int]) {
    var vertices: [SIMD3<UInt32>] = []
    var numbers: [Int] = []
    guard isStrip else {
        let count = indices.count / 3
        vertices.reserveCapacity(count)
        for triangle in 0 ..< count {
            vertices.append([indices[triangle * 3], indices[triangle * 3 + 1], indices[triangle * 3 + 2]])
        }
        return (vertices, Array(0 ..< count))
    }
    var stripStart = 0
    for triangle in 0 ..< max(indices.count - 2, 0) {
        if indices[triangle] == restartIndex {
            stripStart = triangle + 1
        }
        guard indices[triangle] != restartIndex, indices[triangle + 1] != restartIndex, indices[triangle + 2] != restartIndex else {
            continue
        }
        vertices.append((triangle - stripStart).isMultiple(of: 2)
            ? [indices[triangle], indices[triangle + 1], indices[triangle + 2]]
            : [indices[triangle + 1], indices[triangle], indices[triangle + 2]])
        numbers.append(triangle)
    }
    return (vertices, numbers)
}
