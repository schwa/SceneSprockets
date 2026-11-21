import Foundation
@testable import MetalSprocketsGLTF
import MetalSprocketsGLTFMeshopt
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

    // Animation samplers, channels and KHR_animation_pointer targets, through loading and posing.
    @Test func animations() throws {
        let pointers = [
            "/", "//", "/nodes", "/nodes/-1/translation", "/nodes/99/rotation", "/nodes/9223372036854775807/scale", "/nodes/0/weights",
            "/nodes/2/translation", "/nodes/3/extensions/KHR_node_visibility/visible", "/nodes/-1/extensions/KHR_node_visibility/visible",
            "/materials/-1/pbrMetallicRoughness/baseColorFactor", "/materials/99/emissiveFactor", "/materials/0/emissiveFactor",
            "/materials/0/pbrMetallicRoughness/baseColorTexture/extensions/KHR_texture_transform/offset",
            "/materials/0/pbrMetallicRoughness/baseColorTexture/extensions/KHR_texture_transform/rotation",
            "/extensions/KHR_lights_punctual/lights/-1/color", "/extensions/KHR_lights_punctual/lights/99/intensity",
            "/extensions/KHR_lights_punctual/lights/0/spot/innerConeAngle", "/cameras/-1/perspective/yfov", "/cameras/99/perspective/znear",
            "/cameras/0/orthographic/xmag", "/cameras/0/perspective/aspectRatio", "STEP", "CUBICSPLINE", "weights", "rotation"
        ]
        let count = try MalformedDocuments.run(.full(), hostileStrings: pointers) { path in
            Self.topLevelKey(path) == "animations"
        }
        #expect(count > 100)
    }

    // Every sampler output reused for every channel and interpolation: mismatched value sizes, CUBICSPLINE counts.
    @Test func samplerShapes() throws {
        let fixture = try MalformedFixture.full()
        var cases: [[String: Any]] = []
        for output in 0 ..< 14 {
            for input in [5, 9, 1, 6, 11, 12] {
                for interpolation in ["LINEAR", "STEP", "CUBICSPLINE"] {
                    var json = fixture.json
                    var animations = json["animations"] as? [[String: Any]] ?? []
                    let samplers = (animations[0]["samplers"] as? [Any] ?? []).map { _ in ["input": input, "output": output, "interpolation": interpolation] }
                    animations[0]["samplers"] = samplers
                    json["animations"] = animations
                    cases.append(json)
                }
            }
        }
        for (index, json) in cases.enumerated() {
            FileHandle.standardError.write(Data("malformed: sampler case \(index)\n".utf8))
            let url = try MalformedFixture(json: json, buffer: fixture.buffer).write()
            defer { try? FileManager.default.removeItem(at: url) }
            MalformedDocuments.exercise(url)
        }
    }

    @Test func extensionsFixtureLoadsCleanly() throws {
        let url = try MalformedFixture.extensions().write()
        let asset = try GLTFAsset(url: url, options: GLTFLoadOptions(bufferViewDecoders: [GLTFMeshoptDecoder()]))
        #expect(asset.warnings.isEmpty)
        #expect(asset.imageBasedLight != nil)
        #expect(asset.lights.count == 3)
        #expect(asset.opaqueInstances.count + asset.blendedInstances.count == 4)
    }

    // meshopt, image-based lights, punctual lights, instancing and material extensions.
    @Test func extensionData() throws {
        let count = try MalformedDocuments.run(.extensions(), hostileStrings: ["NONE", "OCTAHEDRAL", "QUATERNION", "EXPONENTIAL", "COLOR", "INDICES", "TRIANGLES", "ATTRIBUTES", "spot", "point"]) { path in
            Self.isExtensionPath(path) || ["extensionsUsed", "extensionsRequired", "images"].contains(Self.topLevelKey(path))
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
        // Scene graphs recurse over the hierarchy (#603).
        MalformedDocuments.exercise(try fixture.write(), importsScene: false)
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
