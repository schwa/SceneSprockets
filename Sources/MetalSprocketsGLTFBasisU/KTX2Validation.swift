import Foundation

/// A KTX2 file whose header or level index the loader refuses.
public struct KTX2ValidationError: Error, CustomStringConvertible {
    public var description: String
}

// BasisUniversalMetal trusts a KTX2 file's header: a huge size or an out-of-range level makes texture creation trap.
// These checks run first, so malformed images are skipped with a warning instead.
// https://registry.khronos.org/KTX/specs/2.0/ktxspec.v2.html
enum KTX2Validation {
    /// The largest 2D texture side on Apple GPUs.
    static let maximumSize = 16_384

    static func validate(_ data: Data) throws {
        let bytes = [UInt8](data)
        func uint32(_ offset: Int) -> Int {
            (0 ..< 4).reduce(0) { $0 | Int(bytes[offset + $1]) << (8 * $1) }
        }
        func uint64(_ offset: Int) -> UInt64 {
            (0 ..< 8).reduce(0) { $0 | UInt64(bytes[offset + $1]) << (8 * UInt64($1)) }
        }
        let identifier: [UInt8] = [0xAB, 0x4B, 0x54, 0x58, 0x20, 0x32, 0x30, 0xBB, 0x0D, 0x0A, 0x1A, 0x0A]
        guard bytes.count >= 80, Array(bytes.prefix(12)) == identifier else {
            throw KTX2ValidationError(description: "not a KTX2 file")
        }
        let width = uint32(20), height = uint32(24), depth = uint32(28)
        let layers = uint32(32), faces = uint32(36), levels = max(uint32(40), 1)
        guard (1 ... maximumSize).contains(width), (1 ... maximumSize).contains(height), depth == 0, layers == 0, faces == 1 else {
            throw KTX2ValidationError(description: "only single 2D images up to \(maximumSize) pixels are supported (\(width) x \(height) x \(depth), \(layers) layers, \(faces) faces)")
        }
        let maximumLevels = Int.bitWidth - max(width, height).leadingZeroBitCount
        guard levels <= maximumLevels else {
            throw KTX2ValidationError(description: "\(levels) mip levels for a \(width) x \(height) image")
        }
        guard bytes.count >= 80 + levels * 24 else {
            throw KTX2ValidationError(description: "truncated level index")
        }
        let fileSize = UInt64(bytes.count)
        func checkRange(offset: UInt64, length: UInt64, _ name: String) throws {
            guard offset <= fileSize, length <= fileSize - offset else {
                throw KTX2ValidationError(description: "\(name) is outside the file")
            }
        }
        try checkRange(offset: UInt64(uint32(48)), length: UInt64(uint32(52)), "data format descriptor")
        try checkRange(offset: UInt64(uint32(56)), length: UInt64(uint32(60)), "key/value data")
        try checkRange(offset: uint64(64), length: uint64(72), "supercompression data")
        // 0 none, 1 BasisLZ, 2 Zstandard, 3 ZLIB.
        let supercompression = uint32(44)
        guard (0 ... 3).contains(supercompression) else {
            throw KTX2ValidationError(description: "unknown supercompression scheme \(supercompression)")
        }
        for level in 0 ..< levels {
            let entry = 80 + level * 24
            if supercompression == 0, uint64(entry + 16) != uint64(entry + 8) {
                throw KTX2ValidationError(description: "level \(level) is not supercompressed, but its sizes differ")
            }
            try checkRange(offset: uint64(entry), length: uint64(entry + 8), "level \(level)")
            // At most 16 bytes per pixel (RGBA32Float), with block formats rounded up to whole blocks.
            let levelPixels = UInt64(max(width >> level, 1) + 12) * UInt64(max(height >> level, 1) + 12)
            guard uint64(entry + 16) <= levelPixels * 16 else {
                throw KTX2ValidationError(description: "level \(level) claims \(uint64(entry + 16)) uncompressed bytes")
            }
        }
    }
}
