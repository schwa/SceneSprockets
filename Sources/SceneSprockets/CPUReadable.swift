import Foundation
import Metal
import SwiftMesh

// Hit testing, bounds, CPU deformation and PBR conversion read vertex and index buffers on the CPU (#303). Buffers in
// private storage are copied into shared buffers with a blit; copies are cached for as long as the original lives.

extension MTLBuffer {
    /// This buffer, or a shared-storage copy of it when it is in private storage.
    ///
    /// The copy is made with a GPU blit and waits for it, so the first read of a private buffer blocks briefly. Later
    /// reads of the same buffer reuse the copy for as long as the original buffer exists. Do not write to the copy:
    /// changes do not reach the original.
    public var cpuReadable: MTLBuffer {
        guard storageMode == .private else {
            return self
        }
        return CPUReadableCache.shared.copy(of: self)
    }
}

extension MetalMesh {
    /// This mesh with every vertex and index buffer in CPU-readable storage.
    ///
    /// Shared and managed buffers are used as they are. Private buffers are replaced by cached shared-storage copies.
    /// Use the result only to read vertex data on the CPU.
    public func cpuReadable() -> MetalMesh {
        var result = self
        result.vertexBuffers = vertexBuffers.mapValues(\.cpuReadable)
        result.submeshes = submeshes.map { submesh in
            var submesh = submesh
            submesh.indexBuffer = submesh.indexBuffer.cpuReadable
            return submesh
        }
        return result
    }
}

private final class CPUReadableCache: @unchecked Sendable {
    static let shared = CPUReadableCache()

    private let lock = NSLock()
    // Weak keys: a copy lives only as long as its original buffer.
    private let copies = NSMapTable<AnyObject, AnyObject>(keyOptions: .weakMemory, valueOptions: .strongMemory)
    private var queues: [ObjectIdentifier: MTLCommandQueue] = [:]

    func copy(of buffer: MTLBuffer) -> MTLBuffer {
        lock.lock()
        defer { lock.unlock() }
        if let copy = copies.object(forKey: buffer) as? MTLBuffer {
            return copy
        }
        let device = buffer.device
        let queue = queues[ObjectIdentifier(device)] ?? device.makeCommandQueue()
        queues[ObjectIdentifier(device)] = queue
        guard let queue,
              let copy = device.makeBuffer(length: buffer.length, options: .storageModeShared),
              let commandBuffer = queue.makeCommandBuffer(),
              let blit = commandBuffer.makeBlitCommandEncoder()
        else {
            fatalError("Cannot copy a private buffer of \(buffer.length) bytes to shared storage")
        }
        copy.label = buffer.label.map { "\($0) (CPU copy)" }
        blit.copy(from: buffer, sourceOffset: 0, to: copy, destinationOffset: 0, size: buffer.length)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        copies.setObject(copy, forKey: buffer)
        return copy
    }
}
