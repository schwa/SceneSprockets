import Foundation
@testable import MetalSprocketsGLTF
import SwiftGLTF
import Testing

// Malformed documents must give an error or a warning, never a crash. Each test changes one value of a small valid
// file at a time (see MalformedDocuments), loads the result and poses its animations. Serialized so a crash's log
// names its case.
@Suite(.requiresMetal4, .serialized)
struct MalformedDocumentTests {
    static func isExtensionPath(_ path: [JSONPathComponent]) -> Bool {
        path.contains { if case .key("extensions") = $0 { true } else { false } }
    }

    static func topLevelKey(_ path: [JSONPathComponent]) -> String? {
        if case let .key(key)? = path.first {
            key
        } else {
            nil
        }
    }

    @Test func fixtureLoadsCleanly() throws {
        let url = try MalformedFixture.full().write()
        let asset = try GLTFAsset(url: url)
        #expect(asset.warnings.isEmpty)
        #expect(asset.animations.first?.channels.count == 7)
        #expect(asset.cameras.count == 1)
        #expect(asset.variantNames == ["a", "b"])
    }

    // JSON structure, node hierarchy, skins and other cross-object indices.
    @Test func structureAndIndices() throws {
        let count = try MalformedDocuments.run(.full(), hostileStrings: ["x", "TRIANGLES"]) { path in
            !Self.isExtensionPath(path) && !["accessors", "bufferViews", "buffers", "animations"].contains(Self.topLevelKey(path))
        }
        #expect(count > 100)
    }

    // Accessor and buffer view offsets, counts, strides and sparse accessors.
    @Test func accessorsAndBufferViews() throws {
        let count = try MalformedDocuments.run(.full(), hostileStrings: ["MAT4", "SCALAR", "VEC2"]) { path in
            ["accessors", "bufferViews", "buffers"].contains(Self.topLevelKey(path))
        }
        #expect(count > 100)
    }

    // GLB container: header and chunk lengths, chunk types and truncation.
    @Test func glbContainer() throws {
        let glb = try MalformedFixture.full().glb()
        let jsonLength = Int(glb[12]) | Int(glb[13]) << 8 | Int(glb[14]) << 16 | Int(glb[15]) << 24
        let binHeader = 20 + jsonLength
        // Each length and type field, by byte offset.
        let fields = [4, 8, 12, 16, binHeader, binHeader + 4]
        let values: [UInt32] = [0, 1, 3, 4, 8, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF, UInt32(glb.count), UInt32(glb.count + 4)]
        var cases: [(String, Data)] = []
        for field in fields {
            for value in values {
                var data = glb
                withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(field ..< field + 4, with: $0) }
                cases.append(("field \(field) = \(value)", data))
            }
        }
        for length in [0, 3, 11, 12, 19, 20, binHeader, binHeader + 7, binHeader + 8, glb.count - 1] {
            cases.append(("truncated to \(length)", glb.prefix(length)))
        }
        for (label, data) in cases {
            FileHandle.standardError.write(Data("malformed: GLB \(label)\n".utf8))
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).glb")
            try data.write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            MalformedDocuments.exercise(url)
        }
        // The unmodified GLB loads.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).glb")
        try glb.write(to: url)
        #expect(try GLTFAsset(url: url).warnings.isEmpty)
    }

    // A very deep node chain must not overflow the stack of the recursive hierarchy walks.
    @Test func deepHierarchy() throws {
        var fixture = try MalformedFixture.full()
        let depth = 100_000
        var nodes = fixture.json["nodes"] as? [Any] ?? []
        let first = nodes.count
        nodes += (0 ..< depth).map { index in
            index + 1 < depth ? ["children": [first + index + 1]] as [String: Any] : ["mesh": 0] as [String: Any]
        }
        fixture.json["nodes"] = nodes
        fixture.json["scenes"] = [["nodes": [0, first]]]
        MalformedDocuments.exercise(try fixture.write())
    }

    // Each node lists the next one twice, so a walk would visit the last node 2^64 times.
    @Test func exponentialHierarchy() throws {
        var fixture = try MalformedFixture.full()
        var nodes = fixture.json["nodes"] as? [Any] ?? []
        let first = nodes.count
        nodes += (0 ..< 64).map { index in ["children": [first + index + 1, first + index + 1]] as [String: Any] }
        nodes.append(["mesh": 0])
        fixture.json["nodes"] = nodes
        fixture.json["scenes"] = [["nodes": [0, first]]]
        #expect(throws: GLTFError.self) { try GLTFAsset(url: try fixture.write()) }
    }
}
