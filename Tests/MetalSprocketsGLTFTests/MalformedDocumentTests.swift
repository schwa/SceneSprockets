import Foundation
import SwiftGLTF
@testable import MetalSprocketsGLTF
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
