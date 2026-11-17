import Foundation
import Metal
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

    private final class Entries {
        var positions: [PositionsKey: [SIMD3<Float>]] = [:]
        var indices: [IndicesKey: [UInt32]] = [:]
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

    // The mesh's float3 positions; empty if it has none. Reads CPU-visible buffers; see `MetalMesh.cpuReadable()`.
    func positions(of mesh: MetalMesh) -> [SIMD3<Float>] {
        guard let attribute = mesh.vertexDescriptor.attributes.first(where: { $0.semantic == .position }), attribute.format == .float3, let buffer = mesh.vertexBuffers[attribute.bufferIndex] else {
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
