import Foundation
import MetalSprocketsGLTF
import MetalSprocketsGLTFBasisU
import Testing

// #566: malformed KTX2 images (KHR_texture_basisu, EXT_texture_astc) must give an error or a warning, never a crash.
// Each case changes one header or level-index field, or truncates the file. Serialized so a crash's log names its case.

private let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

/// A triangle whose base color texture uses `ktx` through `extensionName`.
private func makeFile(ktx: Data, extensionName: String) throws -> URL {
    let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
    let texCoords: [Float] = [0, 0, 1, 0, 0, 1]
    let buffer = (positions + texCoords).withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["\(extensionName)"], "extensionsRequired": ["\(extensionName)"],
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0, "TEXCOORD_0": 1}, "material": 0}]}],
      "materials": [{"pbrMetallicRoughness": {"baseColorTexture": {"index": 0}}}],
      "textures": [{"extensions": {"\(extensionName)": {"source": 0}}}],
      "images": [{"uri": "data:image/ktx2;base64,\(ktx.base64EncodedString())", "mimeType": "image/ktx2"}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 0, "byteOffset": 36, "componentType": 5126, "count": 3, "type": "VEC2"}
      ],
      "bufferViews": [{"buffer": 0, "byteLength": 60}],
      "buffers": [{"byteLength": 60, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

/// Every one-field change of a KTX2 file's header and first level index entry, and truncations.
private func mutations(of ktx: Data) -> [(label: String, data: Data)] {
    let values: [UInt32] = [0, 1, 2, 3, 7, 16, 255, 0x7FFF, 0xFFFF, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF, UInt32(ktx.count), UInt32(ktx.count + 1)]
    var result: [(String, Data)] = []
    // Fields after the 12-byte identifier: the header, the index, and the first level's offset, length and
    // uncompressed length (64-bit fields change one half at a time).
    for offset in stride(from: 12, to: min(104, ktx.count - 3), by: 4) {
        for value in values {
            var data = ktx
            withUnsafeBytes(of: value.littleEndian) { data.replaceSubrange(offset ..< offset + 4, with: $0) }
            result.append(("offset \(offset) = \(value)", data))
        }
    }
    // Inverted bytes spread over the whole file: descriptors, supercompression data and level data.
    for position in stride(from: 104, to: ktx.count, by: max(ktx.count / 200, 1)) {
        var data = ktx
        data[position] ^= 0xFF
        result.append(("byte \(position) inverted", data))
    }
    for length in [0, 11, 12, 48, 80, 103, 104, ktx.count / 2, ktx.count - 1] where length < ktx.count {
        result.append(("truncated to \(length)", ktx.prefix(length)))
    }
    return result
}

@Suite(.requiresMetal4, .serialized)
struct MalformedKTX2Tests {
    static let decoders = GLTFLoadOptions(textureDecoders: [GLTFBasisUTextureDecoder(), GLTFASTCTextureDecoder()])

    static func sources() throws -> [(name: String, data: Data, extensionName: String)] {
        var result: [(String, Data, String)] = []
        for name in ["astc_6x6_srgb", "astc_8x8_srgb_zstd"] {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "ktx2", subdirectory: "Resources"))
            result.append((name, try Data(contentsOf: url), "EXT_texture_astc"))
        }
        // The smallest Basis Universal file in the Khronos samples, when they are downloaded (just download-sample-assets).
        let basis = repository.appending(path: ".sample-assets/Models/CarConcept/glTF-KTX-BasisU-Draco/Rib_N.ktx2")
        if let data = try? Data(contentsOf: basis) {
            result.append(("Rib_N", data, "KHR_texture_basisu"))
        }
        return result
    }

    @Test func unmodifiedImagesLoad() throws {
        for source in try Self.sources() {
            let asset = try GLTFAsset(url: makeFile(ktx: source.data, extensionName: source.extensionName), options: Self.decoders)
            #expect(asset.warnings.isEmpty, "\(source.name)")
        }
    }

    @Test func malformedImagesDoNotCrash() throws {
        for source in try Self.sources() {
            for (label, data) in mutations(of: source.data) {
                FileHandle.standardError.write(Data("malformed: \(source.name) \(label)\n".utf8))
                let url = try makeFile(ktx: data, extensionName: source.extensionName)
                defer { try? FileManager.default.removeItem(at: url) }
                _ = try? GLTFAsset(url: url, options: Self.decoders)
            }
        }
    }
}
