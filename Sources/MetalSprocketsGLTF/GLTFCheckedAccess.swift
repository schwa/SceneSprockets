import Foundation
import SwiftGLTF

// SwiftGLTF trusts accessor and buffer view numbers: a negative offset or count, an overflowing size or a sparse
// range past its view traps instead of throwing. These checks run first, so malformed files throw instead.

public extension Container {
    /// Opens `url` like `init(url:bufferViewDecoders:)`, but throws for a GLB whose header length would make
    /// SwiftGLTF trap.
    init(checkingURL url: URL, bufferViewDecoders: [any BufferViewDecoder] = []) throws {
        if url.pathExtension == "glb" {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let header = try handle.read(upToCount: 12) ?? Data()
            guard header.count == 12 else {
                throw GLTFError.malformedGLB("Truncated GLB header")
            }
            let length = header[8 ..< 12].reversed().reduce(0) { $0 << 8 | Int($1) }
            guard length >= 12 else {
                throw GLTFError.malformedGLB("GLB length \(length) is shorter than its header")
            }
        }
        try self.init(url: url, bufferViewDecoders: bufferViewDecoders)
    }
}

extension Container {
    /// The most bytes one accessor may decode to; larger ones are refused instead of allocated.
    static let maximumAccessorBytes = 1 << 30

    /// `accessor`'s components as floats, after ``checkAccessor(_:)``.
    public func checkedFloatComponents(for accessor: Accessor) throws -> [Float] {
        try checkAccessor(accessor)
        return try floatComponents(for: accessor)
    }

    /// `accessor`'s tightly packed bytes, after ``checkAccessor(_:)``.
    func checkedData(for accessor: Accessor) throws -> Data {
        try checkAccessor(accessor)
        return try data(for: accessor)
    }

    /// The bytes of buffer view `index`, after ``checkBufferView(_:)``.
    func checkedData(for index: Index<BufferView>) throws -> Data {
        let view = try index.resolve(in: document)
        try checkBufferView(view)
        return try data(for: view)
    }

    /// Throws when reading `view` would trap: a negative offset or length, or a range that overflows.
    func checkBufferView(_ view: BufferView) throws {
        guard view.byteOffset >= 0, view.byteLength >= 0, try Self.sum(view.byteOffset, view.byteLength) >= 0 else {
            throw GLTFError.invalidDocument("Buffer view range \(view.byteOffset)+\(view.byteLength) is invalid")
        }
        if let stride = view.byteStride, stride <= 0 {
            throw GLTFError.invalidDocument("Buffer view byteStride \(stride) is invalid")
        }
    }

    /// Throws when reading `accessor` would trap or allocate without bound: counts and offsets must be in range of
    /// their buffer views, sparse ranges included.
    func checkAccessor(_ accessor: Accessor) throws {
        let elementSize = accessor.componentType.byteSize * accessor.type.componentCount
        guard accessor.count >= 1, accessor.byteOffset >= 0 else {
            throw GLTFError.invalidDocument("Accessor count \(accessor.count) or byteOffset \(accessor.byteOffset) is invalid")
        }
        guard try Self.product(accessor.count, elementSize) <= Self.maximumAccessorBytes else {
            throw GLTFError.invalidDocument("Accessor of \(accessor.count) elements is too large")
        }
        if let viewIndex = accessor.bufferView {
            let view = try viewIndex.resolve(in: document)
            try checkBufferView(view)
            let stride = view.byteStride ?? elementSize
            let end = try Self.sum(accessor.byteOffset, Self.product(stride, accessor.count - 1), elementSize)
            guard end <= view.byteLength else {
                throw GLTFError.invalidDocument("Accessor needs \(end) bytes of a \(view.byteLength) byte buffer view")
            }
        }
        if let sparse = accessor.sparse {
            guard (1 ... accessor.count).contains(sparse.count), sparse.indices.byteOffset >= 0, sparse.values.byteOffset >= 0 else {
                throw GLTFError.invalidDocument("Sparse accessor count \(sparse.count) or offsets are invalid")
            }
            let indicesView = try sparse.indices.bufferView.resolve(in: document)
            let valuesView = try sparse.values.bufferView.resolve(in: document)
            try checkBufferView(indicesView)
            try checkBufferView(valuesView)
            let indicesEnd = try Self.sum(sparse.indices.byteOffset, Self.product(sparse.count, sparse.indices.componentType.byteSize))
            let valuesEnd = try Self.sum(sparse.values.byteOffset, Self.product(sparse.count, elementSize))
            guard indicesEnd <= indicesView.byteLength, valuesEnd <= valuesView.byteLength else {
                throw GLTFError.invalidDocument("Sparse accessor data is out of range of its buffer views")
            }
        }
    }

    static func sum(_ values: Int...) throws -> Int {
        try values.reduce(0) { total, value in
            let (result, overflow) = total.addingReportingOverflow(value)
            guard !overflow else {
                throw GLTFError.invalidDocument("Size overflows")
            }
            return result
        }
    }

    static func product(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
        guard !overflow else {
            throw GLTFError.invalidDocument("Size overflows")
        }
        return result
    }
}

extension Accessor.ComponentType {
    var byteSize: Int {
        switch self {
        case .BYTE, .UNSIGNED_BYTE: 1
        case .SHORT, .UNSIGNED_SHORT: 2
        case .UNSIGNED_INT, .FLOAT: 4
        }
    }
}
