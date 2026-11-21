import CMeshoptimizer
import CoreGraphics
import Foundation
import ImageIO
@testable import MetalSprocketsGLTF
import MetalSprocketsGLTFMeshopt
import SceneSprockets
@testable import SceneSprocketsPBR
import simd
import UniformTypeIdentifiers

// swiftlint:disable legacy_objc_type - JSONSerialization works in NSNumber

// Builds malformed variants of a small valid glTF and checks that loading and posing each one never crashes.
// Throwing or warning is fine.

/// A glTF document as parsed JSON plus its one buffer, embedded as a data URI when written.
struct MalformedFixture {
    var json: [String: Any]
    var buffer: Data

    /// Writes the document to a temporary `.gltf` file.
    func write() throws -> URL {
        var json = json
        if var buffers = json["buffers"] as? [Any], var first = buffers.first as? [String: Any], first["uri"] == nil {
            first["uri"] = "data:application/octet-stream;base64,\(buffer.base64EncodedString())"
            buffers[0] = first
            json["buffers"] = buffers
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        return url
    }

    /// The document as GLB bytes, the buffer in the BIN chunk.
    func glb() throws -> Data {
        func padded(_ data: Data, with byte: UInt8) -> Data {
            data + Data(repeating: byte, count: (4 - data.count % 4) % 4)
        }
        func uint32(_ value: Int) -> Data {
            withUnsafeBytes(of: UInt32(value).littleEndian) { Data($0) }
        }
        let jsonChunk = try padded(JSONSerialization.data(withJSONObject: json), with: 0x20)
        let binChunk = padded(buffer, with: 0)
        let length = 12 + 8 + jsonChunk.count + 8 + binChunk.count
        return Data("glTF".utf8) + uint32(2) + uint32(length)
            + uint32(jsonChunk.count) + Data("JSON".utf8) + jsonChunk
            + uint32(binChunk.count) + Data([0x42, 0x49, 0x4E, 0]) + binChunk
    }
}

/// One step into a JSON value: an object key or an array index.
enum JSONPathComponent: CustomStringConvertible {
    case key(String)
    case index(Int)

    var description: String {
        switch self {
        case let .key(key): key
        case let .index(index): "\(index)"
        }
    }
}

enum MalformedDocuments {
    /// Numbers that break index, offset, count and stride arithmetic.
    static let hostileNumbers: [NSNumber] = [
        -1, 0, 1, 2, 3, 7, 255, 65_535, 1_048_576, 2_147_483_648, 1_099_511_627_776,
        NSNumber(value: Int64.max), NSNumber(value: Int64.min), NSNumber(value: Int64.max / 4),
        0.5, -0.5, 1e30, -1e30
    ]

    /// Every variant of `fixture.json` with one change below a path accepted by `include`: each number replaced by
    /// each hostile number, each key removed, each array emptied, each value replaced by null or a string, each
    /// string replaced by `hostileStrings`.
    static func mutations(of json: [String: Any], hostileStrings: [String] = [], include: ([JSONPathComponent]) -> Bool) -> [(label: String, json: [String: Any])] {
        var result: [(String, [String: Any])] = []
        func visit(_ value: Any, path: [JSONPathComponent]) {
            let label = "/" + path.map(\.description).joined(separator: "/")
            let included = include(path)
            func add(_ name: String, _ replacement: Any?) {
                guard included, let root = replacing(json, at: path, with: replacement) as? [String: Any] else {
                    return
                }
                result.append(("\(label) = \(name)", root))
            }
            if !path.isEmpty {
                add("null", NSNull())
                add("removed", nil)
            }
            switch value {
            case let object as [String: Any]:
                add("{}", [String: Any]())
                for (key, child) in object.sorted(by: { $0.key < $1.key }) {
                    visit(child, path: path + [.key(key)])
                }

            case let array as [Any]:
                add("[]", [Any]())
                for (index, child) in array.enumerated() {
                    visit(child, path: path + [.index(index)])
                }

            case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
                add("\"x\"", "x")
                for hostile in hostileNumbers {
                    add("\(hostile)", hostile)
                }

            case is String:
                add("\"\"", "")
                for hostile in hostileStrings {
                    add("\"\(hostile)\"", hostile)
                }

            default:
                break
            }
        }
        visit(json, path: [])
        return result
    }

    /// `json` with the value at `path` replaced, or removed when `replacement` is nil.
    static func replacing(_ json: Any, at path: [JSONPathComponent], with replacement: Any?) -> Any? {
        guard let first = path.first else {
            return replacement
        }
        let rest = Array(path.dropFirst())
        switch (first, json) {
        case let (.key(key), object as [String: Any]):
            var object = object
            object[key] = object[key].flatMap { replacing($0, at: rest, with: replacement) }
            return object

        case let (.index(index), array as [Any]):
            var array = array
            if let value = replacing(array[index], at: rest, with: replacement) {
                array[index] = value
            } else {
                array.remove(at: index)
            }
            return array

        default:
            return json
        }
    }

    /// Loads `url` and poses every animation at hostile times, blended and alone, and builds every scene and variant.
    /// With `importsScene`, also imports it into a scene graph and plays its clips there.
    static func exercise(_ url: URL, importsScene: Bool = true) {
        guard let asset = try? GLTFAsset(url: url, options: GLTFLoadOptions(bufferViewDecoders: [GLTFMeshoptDecoder()])) else {
            return
        }
        let times: [Float] = [-1, 0, 0.25, 0.5, 1, 1e9, .nan, .infinity, -.infinity]
        for animation in asset.animations.indices {
            for time in times {
                let pose = asset.pose(animation: animation, time: time)
                _ = asset.lights(pose: pose)
                _ = asset.cameras(pose: pose)
                _ = asset.bounds(for: pose)
            }
        }
        for animation in [-1, 0, 1, 99] {
            let layers = [
                GLTFAnimationLayer(animation: animation, time: 0.5, weight: 0.5),
                GLTFAnimationLayer(animation: 0, time: 0.25, weight: 0.5),
                GLTFAnimationLayer(animation: animation, time: 0.75, weight: 1, mode: .additive)
            ]
            for node in [-1, 0, 1, 99] {
                let pose = asset.pose(layers: layers, rootMotionNode: node)
                _ = asset.lights(pose: pose)
                _ = asset.cameras(pose: pose)
                _ = asset.rootTranslation(layers: layers, node: node)
            }
        }
        for scene in -1 ... asset.sceneCount {
            _ = try? asset.scene(scene)
        }
        for variant in [nil, -1, 0, 1, 99] {
            _ = try? asset.variant(variant)
            _ = try? asset.materialOverrides(variant: variant)
        }
        for node in [-1, 0, 1, 99] {
            _ = asset.restMorphWeights(node: node)
        }
        _ = try? asset.environment()

        guard importsScene, let imported = try? asset.importScene() else {
            return
        }
        for clip in imported.animations {
            for time in times {
                clip.apply(at: time, looping: true)
                clip.apply(at: time)
            }
        }
        let mixer = SceneGraph.AnimationMixer(clips: imported.animations)
        for clip in [-1, 0, 1, 99] {
            mixer.apply([.init(clip: clip, time: 0.5, weight: 0.5), .init(clip: 0, time: 0.25, weight: 0.5), .init(clip: clip, time: 0.75, mode: .additive)], rootMotionNode: imported.nodes.compactMap(\.self).first)
        }
        for variant in [nil, -1, 0, 1, 99] {
            try? imported.selectVariant(variant)
        }
        _ = imported.sceneGraph.meshEntries()
    }

    /// Writes and exercises every mutation, logging each label first so a crash names its case.
    static func run(_ fixture: MalformedFixture, hostileStrings: [String] = [], include: ([JSONPathComponent]) -> Bool) throws -> Int {
        let mutations = mutations(of: fixture.json, hostileStrings: hostileStrings, include: include)
        for (label, json) in mutations {
            FileHandle.standardError.write(Data("malformed: \(label)\n".utf8))
            let url = try MalformedFixture(json: json, buffer: fixture.buffer).write()
            defer { try? FileManager.default.removeItem(at: url) }
            exercise(url)
        }
        return mutations.count
    }
}

extension MalformedFixture {
    /// A square PNG of one opaque color.
    static func png(size: Int = 4, gray: UInt8 = 128) throws -> Data {
        let pixels = [UInt8](repeating: gray, count: size * size * 4)
        guard let provider = CGDataProvider(data: Data(pixels) as CFData), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw CocoaError(.coderInvalidValue)
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.coderInvalidValue)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.coderInvalidValue)
        }
        return data as Data
    }

    /// A triangle using extensions: meshopt-compressed positions and indices, an image-based light, punctual lights of
    /// every type, instancing with all three attributes, and textured material extensions.
    static func extensions() throws -> Self {
        var buffer = Data()
        func append(_ data: Data) -> (offset: Int, length: Int) {
            let offset = buffer.count
            buffer.append(data)
            while !buffer.count.isMultiple(of: 4) {
                buffer.append(0)
            }
            return (offset, data.count)
        }
        func bytes<T>(_ values: [T]) -> Data {
            values.withUnsafeBytes { Data($0) }
        }
        let positions: [Float] = [-1, -1, 0, 1, -1, 0, 0, 1, 0]
        var encodedPositions = [UInt8](repeating: 0, count: meshopt_encodeVertexBufferBound(3, 12))
        encodedPositions.removeLast(encodedPositions.count - positions.withUnsafeBytes { meshopt_encodeVertexBuffer(&encodedPositions, encodedPositions.count, $0.baseAddress, 3, 12) })
        let indices: [UInt32] = [0, 1, 2]
        var encodedIndices = [UInt8](repeating: 0, count: meshopt_encodeIndexBufferBound(3, 3))
        encodedIndices.removeLast(encodedIndices.count - meshopt_encodeIndexBuffer(&encodedIndices, encodedIndices.count, indices, 3))
        let compressedPositions = append(Data(encodedPositions))
        let compressedIndices = append(Data(encodedIndices))
        let instances = append(bytes([Float](arrayLiteral: 0, 0, 0, 2, 0, 0)))
        let rotations = append(bytes([Float](arrayLiteral: 0, 0, 0, 1, 0, 0.7071, 0, 0.7071)))
        let scales = append(bytes([Float](arrayLiteral: 1, 1, 1, 2, 2, 2)))
        let face = try png().base64EncodedString()
        let texture = #"{"index": 0, "extensions": {"KHR_texture_transform": {"offset": [0.5, 0], "rotation": 1, "scale": [2, 2], "texCoord": 0}}}"#
        let json = """
        {
          "asset": {"version": "2.0"},
          "extensionsUsed": ["EXT_meshopt_compression", "EXT_lights_image_based", "KHR_lights_punctual", "EXT_mesh_gpu_instancing", "KHR_texture_transform",
            "KHR_materials_clearcoat", "KHR_materials_sheen", "KHR_materials_iridescence", "KHR_materials_anisotropy", "KHR_materials_transmission",
            "KHR_materials_volume", "KHR_materials_specular", "KHR_materials_ior", "KHR_materials_emissive_strength", "KHR_materials_dispersion",
            "KHR_materials_diffuse_transmission", "KHR_materials_pbrSpecularGlossiness", "KHR_materials_unlit"],
          "extensionsRequired": ["EXT_meshopt_compression"],
          "extensions": {
            "EXT_lights_image_based": {"lights": [{"rotation": [0, 0, 0, 1], "intensity": 1, "irradianceCoefficients": [\(Array(repeating: "[0, 0, 0]", count: 9).joined(separator: ", "))],
              "specularImageSize": 4, "specularImages": [[1, 1, 1, 1, 1, 1], [1, 1, 1, 1, 1, 1]]}]},
            "KHR_lights_punctual": {"lights": [{"type": "directional", "intensity": 1}, {"type": "point", "range": 5}, {"type": "spot", "spot": {"innerConeAngle": 0.2, "outerConeAngle": 0.4}}]}
          },
          "scene": 0,
          "scenes": [{"nodes": [0, 1, 2], "extensions": {"EXT_lights_image_based": {"light": 0}}}],
          "nodes": [
            {"mesh": 0, "extensions": {"EXT_mesh_gpu_instancing": {"attributes": {"TRANSLATION": 2, "ROTATION": 3, "SCALE": 4, "_ID": 2}}}},
            {"extensions": {"KHR_lights_punctual": {"light": 0}}, "children": [3]},
            {"extensions": {"KHR_lights_punctual": {"light": 1}}},
            {"extensions": {"KHR_lights_punctual": {"light": 2}}}
          ],
          "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "indices": 1, "material": 0}, {"attributes": {"POSITION": 0}, "material": 1}]}],
          "materials": [
            {"pbrMetallicRoughness": {"baseColorTexture": \(texture)}, "extensions": {
              "KHR_materials_clearcoat": {"clearcoatFactor": 1, "clearcoatTexture": \(texture), "clearcoatNormalTexture": {"index": 0}},
              "KHR_materials_sheen": {"sheenColorFactor": [1, 1, 1], "sheenRoughnessTexture": {"index": 0}},
              "KHR_materials_iridescence": {"iridescenceFactor": 1, "iridescenceThicknessTexture": {"index": 0}, "iridescenceThicknessMinimum": 100, "iridescenceThicknessMaximum": 400},
              "KHR_materials_anisotropy": {"anisotropyStrength": 0.5, "anisotropyRotation": 1, "anisotropyTexture": {"index": 0}},
              "KHR_materials_transmission": {"transmissionFactor": 0.5, "transmissionTexture": {"index": 0}},
              "KHR_materials_volume": {"thicknessFactor": 1, "attenuationDistance": 2, "attenuationColor": [1, 0.5, 0.5]},
              "KHR_materials_specular": {"specularFactor": 0.5, "specularColorTexture": {"index": 0}},
              "KHR_materials_ior": {"ior": 1.5},
              "KHR_materials_emissive_strength": {"emissiveStrength": 4},
              "KHR_materials_dispersion": {"dispersion": 0.1},
              "KHR_materials_diffuse_transmission": {"diffuseTransmissionFactor": 0.5, "diffuseTransmissionColorTexture": {"index": 0}}
            }},
            {"extensions": {"KHR_materials_pbrSpecularGlossiness": {"diffuseFactor": [1, 1, 1, 1], "specularGlossinessTexture": {"index": 0}}, "KHR_materials_unlit": {}}}
          ],
          "textures": [{"source": 0}],
          "images": [{"uri": "data:image/png;base64,\(face)"}, {"uri": "data:image/png;base64,\(face)"}],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
            {"bufferView": 1, "componentType": 5125, "count": 3, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 4, "componentType": 5126, "count": 2, "type": "VEC3"}
          ],
          "bufferViews": [
            {"buffer": 1, "byteLength": 36, "byteStride": 12, "extensions": {"EXT_meshopt_compression": {"buffer": 0, "byteOffset": \(compressedPositions.offset), "byteLength": \(compressedPositions.length), "byteStride": 12, "count": 3, "mode": "ATTRIBUTES"}}},
            {"buffer": 1, "byteLength": 12, "extensions": {"EXT_meshopt_compression": {"buffer": 0, "byteOffset": \(compressedIndices.offset), "byteLength": \(compressedIndices.length), "byteStride": 4, "count": 3, "mode": "TRIANGLES"}}},
            {"buffer": 0, "byteOffset": \(instances.offset), "byteLength": 24},
            {"buffer": 0, "byteOffset": \(rotations.offset), "byteLength": 32},
            {"buffer": 0, "byteOffset": \(scales.offset), "byteLength": 24}
          ],
          "buffers": [{"byteLength": \(buffer.count)}, {"byteLength": 48, "extensions": {"EXT_meshopt_compression": {"fallback": true}}}]
        }
        """
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return Self(json: object, buffer: buffer)
    }

    /// A skinned, morphed, animated, instanced triangle with a camera, a spot light and a material variant: most of
    /// what the loader reads, in one small file.
    static func full() throws -> Self {
        var buffer = Data()
        func append<T>(_ values: [T]) {
            values.withUnsafeBytes { buffer.append(contentsOf: $0) }
            while !buffer.count.isMultiple(of: 4) {
                buffer.append(0)
            }
        }
        let identity = (0 ..< 16).map { Float($0.isMultiple(of: 5) ? 1 : 0) }
        append([Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 0, 1, 0)) // 0: positions, 36
        append([UInt16](arrayLiteral: 0, 1, 2)) // 36: indices, 6
        append([UInt8](arrayLiteral: 0, 1, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0)) // 44: joints, 12
        append([Float](arrayLiteral: 1, 0, 0, 0, 1, 0, 0, 0, 0.5, 0.5, 0, 0)) // 56: weights, 48
        append(identity + identity) // 104: inverse bind matrices, 128
        append([Float](arrayLiteral: 0, 1)) // 232: times, 8
        append([Float](arrayLiteral: 0, 0, 0, 1, 2, 3)) // 240: translations, 24
        append([Float](arrayLiteral: 0, 0, 0, 1, 0, 0.7071, 0, 0.7071)) // 264: rotations, 32
        append([Float](arrayLiteral: 0, 0, 0, 0, 0, 0, 0, 0, 0)) // 296: morph deltas, 36
        append([Float](arrayLiteral: 0, 1)) // 332: scalar values, 8
        append([UInt16](arrayLiteral: 2)) // 340: sparse indices, 2
        append([Float](arrayLiteral: 0, 0.5, 0)) // 344: sparse values, 12
        append([Float](arrayLiteral: 0, 0, 0, 2, 0, 0)) // 356: instance translations, 24
        append([Float](arrayLiteral: 1, 0, 0, 0.5, 0.5, 0.5)) // 380: color keyframes, 24
        let views: [(Int, Int)] = [(0, 36), (36, 6), (44, 12), (56, 48), (104, 128), (232, 8), (240, 24), (264, 32), (296, 36), (332, 8), (340, 2), (344, 12), (356, 24), (380, 24)]
        let viewsJSON = views.enumerated()
            .map { index, view in "{\"buffer\": 0, \"byteOffset\": \(view.0), \"byteLength\": \(view.1)\(index == 0 ? ", \"byteStride\": 12" : "")}" }
            .joined(separator: ", ")
        let json = """
        {
          "asset": {"version": "2.0"},
          "extensionsUsed": ["KHR_lights_punctual", "KHR_materials_variants", "KHR_node_visibility", "KHR_animation_pointer", "EXT_mesh_gpu_instancing"],
          "extensions": {
            "KHR_lights_punctual": {"lights": [{"type": "spot", "color": [1, 1, 1], "intensity": 2, "range": 10, "spot": {"innerConeAngle": 0.1, "outerConeAngle": 0.5}}]},
            "KHR_materials_variants": {"variants": [{"name": "a"}, {"name": "b"}]}
          },
          "scene": 0,
          "scenes": [{"nodes": [0]}, {"nodes": [3]}],
          "nodes": [
            {"children": [1, 2, 3], "translation": [1, 2, 3], "rotation": [0, 0, 0, 1], "scale": [1, 1, 1]},
            {"mesh": 0, "skin": 0, "weights": [0.5]},
            {"camera": 0, "matrix": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 5, 1], "extensions": {"KHR_lights_punctual": {"light": 0}}},
            {"mesh": 0, "extensions": {"EXT_mesh_gpu_instancing": {"attributes": {"TRANSLATION": 10}}, "KHR_node_visibility": {"visible": false}}}
          ],
          "meshes": [{
            "primitives": [{
              "attributes": {"POSITION": 0, "JOINTS_0": 2, "WEIGHTS_0": 3},
              "indices": 1, "material": 0, "mode": 4,
              "targets": [{"POSITION": 8}],
              "extensions": {"KHR_materials_variants": {"mappings": [{"material": 1, "variants": [1]}]}}
            }],
            "weights": [0]
          }],
          "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0.5}}, {"emissiveFactor": [1, 0, 0]}],
          "skins": [{"joints": [0, 1], "inverseBindMatrices": 4, "skeleton": 0}],
          "cameras": [{"type": "perspective", "perspective": {"yfov": 1, "znear": 0.1, "zfar": 100, "aspectRatio": 1}}],
          "animations": [{
            "samplers": [
              {"input": 5, "output": 6, "interpolation": "LINEAR"},
              {"input": 5, "output": 7, "interpolation": "LINEAR"},
              {"input": 5, "output": 9, "interpolation": "STEP"},
              {"input": 5, "output": 9, "interpolation": "LINEAR"},
              {"input": 5, "output": 13, "interpolation": "LINEAR"}
            ],
            "channels": [
              {"sampler": 0, "target": {"node": 0, "path": "translation"}},
              {"sampler": 1, "target": {"node": 1, "path": "rotation"}},
              {"sampler": 2, "target": {"node": 1, "path": "weights"}},
              {"sampler": 3, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/materials/0/pbrMetallicRoughness/metallicFactor"}}}},
              {"sampler": 4, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/extensions/KHR_lights_punctual/lights/0/color"}}}},
              {"sampler": 2, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/nodes/3/extensions/KHR_node_visibility/visible"}}}},
              {"sampler": 3, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/cameras/0/perspective/yfov"}}}}
            ]
          }],
          "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "SCALAR"},
            {"bufferView": 2, "componentType": 5121, "count": 3, "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": 3, "type": "VEC4"},
            {"bufferView": 4, "componentType": 5126, "count": 2, "type": "MAT4"},
            {"bufferView": 5, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
            {"bufferView": 6, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"bufferView": 7, "componentType": 5126, "count": 2, "type": "VEC4"},
            {"bufferView": 8, "componentType": 5126, "count": 3, "type": "VEC3",
             "sparse": {"count": 1, "indices": {"bufferView": 10, "componentType": 5123}, "values": {"bufferView": 11}}},
            {"bufferView": 9, "componentType": 5126, "count": 2, "type": "SCALAR"},
            {"bufferView": 12, "componentType": 5126, "count": 2, "type": "VEC3"},
            {"componentType": 5126, "count": 2, "type": "VEC3"},
            {"bufferView": 0, "byteOffset": 4, "componentType": 5126, "count": 2, "type": "VEC2"},
            {"bufferView": 13, "componentType": 5126, "count": 2, "type": "VEC3"}
          ],
          "bufferViews": [\(viewsJSON)],
          "buffers": [{"byteLength": \(buffer.count)}]
        }
        """
        guard let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return Self(json: object, buffer: buffer)
    }
}

// swiftlint:enable legacy_objc_type
