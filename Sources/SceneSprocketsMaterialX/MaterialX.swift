import CoreGraphics
import Foundation
import ImageIO
import MaterialX
import Metal
import MetalKit
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import SceneSprocketsPBR
import simd

/// The materials of a MaterialX (`.mtlx`) document, as ``PBRSceneMaterial``s (#528).
///
/// Each `surfacematerial` whose surface shader is a `standard_surface`, `UsdPreviewSurface`, `gltf_pbr` or
/// `open_pbr_surface` becomes one material. Shader inputs may be constant values or image textures, connected directly
/// or through a nodegraph output (a `normalmap` node in front of the normal image is followed). Math nodes on constants
/// (add, multiply, mix, clamp, extract, combine and so on) are folded, and an image multiplied by a constant becomes a
/// textured input with that factor (#609). Nodes that need per-pixel evaluation (noise, texture coordinates, other
/// math on images) are not evaluated: those inputs keep their defaults and are reported in ``warnings``.
public struct MaterialXDocument {
    public struct Material {
        /// The `surfacematerial` element's name.
        public var name: String
        public var material: PBRSceneMaterial
    }

    public var materials: [Material]
    /// What was not converted, such as unsupported shaders or node graphs.
    public var warnings: [String]

    /// Loads `url`, following `xi:include`s. Relative texture paths resolve against the file's folder and any
    /// `fileprefix` attributes.
    public init(url: URL, device: MTLDevice? = nil) throws {
        try self.init(data: Data(contentsOf: url), baseURL: url.deletingLastPathComponent(), device: device)
    }

    public init(data: Data, baseURL: URL, device: MTLDevice? = nil) throws {
        // Parsed by MetalSprocketsMaterialX (#665).
        let root: MaterialXElement
        do {
            root = try MaterialX.MaterialXDocument(data: data, baseURL: baseURL).root
        } catch let error as MaterialX.MaterialXError {
            throw MaterialXError.invalidDocument(error.description)
        }
        var converter = MaterialXConverter(root: root, baseURL: baseURL, device: device ?? _MTLCreateSystemDefaultDevice())
        materials = try converter.convertMaterials()
        warnings = converter.warnings
    }

    /// The material named `name`, if any.
    public subscript(name: String) -> PBRSceneMaterial? {
        materials.first { $0.name == name }?.material
    }
}

public enum MaterialXError: Error, CustomStringConvertible {
    case invalidDocument(String)

    public var description: String {
        switch self {
        case let .invalidDocument(reason): "Invalid MaterialX document: \(reason)"
        }
    }
}

// MARK: - XML

extension MaterialXElement {
    func input(_ name: String) -> Self? {
        children.first { $0.tag == "input" && $0.name == name }
    }
}

// MARK: - Conversion

/// An input's value: a constant, or an image file times a constant factor (one value, or one per channel).
enum MaterialXValue: Equatable {
    case constant([Float])
    case image(URL, factor: [Float] = [1])
}

struct MaterialXConverter {
    var root: MaterialXElement
    var baseURL: URL
    var device: MTLDevice
    var warnings: [String] = []

    mutating func convertMaterials() throws -> [MaterialXDocument.Material] {
        var materials: [MaterialXDocument.Material] = []
        for element in root.children where element.tag == "surfacematerial" {
            let name = element.name ?? "material\(materials.count)"
            guard let shaderName = element.input("surfaceshader")?["nodename"], let shader = root.child(named: shaderName) else {
                warnings.append("\(name): no surfaceshader input")
                continue
            }
            switch shader.tag {
            case "standard_surface":
                materials.append(.init(name: name, material: try standardSurface(shader, material: name)))
            case "UsdPreviewSurface":
                materials.append(.init(name: name, material: try usdPreviewSurface(shader, material: name)))
            case "gltf_pbr":
                materials.append(.init(name: name, material: try gltfPBR(shader, material: name)))
            case "open_pbr_surface":
                materials.append(.init(name: name, material: try openPBRSurface(shader, material: name)))
            default:
                warnings.append("\(name): shader \(shader.tag) is not supported")
            }
        }
        return materials
    }

    // MARK: Shaders

    private mutating func standardSurface(_ shader: MaterialXElement, material: String) throws -> PBRSceneMaterial {
        var inputs = Inputs(shader: shader, material: material, converter: self)
        let base = inputs.float("base", default: 1)
        let baseColor = inputs.colorOrImage("base_color", default: [0.8, 0.8, 0.8])
        let metalness = inputs.floatOrImage("metalness", default: 0)
        let roughness = inputs.floatOrImage("specular_roughness", default: 0.2)
        let opacity = inputs.vector("opacity", default: [1, 1, 1])
        let emission = inputs.float("emission", default: 0)
        let emissionColor = inputs.colorOrImage("emission_color", default: [1, 1, 1])
        let normal = inputs.image("normal")
        let pbr = try makeMaterial(
            baseColor: baseColor,
            baseWeight: base,
            opacity: opacity.reduce(0, +) / Float(max(opacity.count, 1)),
            metallic: metalness,
            roughness: roughness,
            normal: normal,
            occlusion: nil,
            emissive: emissionColor,
            emissiveWeight: emission
        )
        var uniforms = pbr.uniforms
        uniforms.ior = inputs.float("specular_IOR", default: 1.5)
        uniforms.specularFactor = inputs.float("specular", default: 1)
        uniforms.specularColorFactor = inputs.color("specular_color", default: [1, 1, 1])
        uniforms.transmissionFactor = inputs.float("transmission", default: 0)
        uniforms.clearcoatFactor = inputs.float("coat", default: 0)
        uniforms.clearcoatRoughnessFactor = inputs.float("coat_roughness", default: 0.1)
        uniforms.sheenColorFactor = inputs.float("sheen", default: 0) * inputs.color("sheen_color", default: [1, 1, 1])
        uniforms.sheenRoughnessFactor = inputs.float("sheen_roughness", default: 0.3)
        pbr.uniforms = uniforms
        warnings += inputs.warnings
        return pbr
    }

    private mutating func usdPreviewSurface(_ shader: MaterialXElement, material: String) throws -> PBRSceneMaterial {
        var inputs = Inputs(shader: shader, material: material, converter: self)
        if inputs.float("useSpecularWorkflow", default: 0) != 0 {
            inputs.warnings.append("\(material): useSpecularWorkflow is not supported; metallic is used")
        }
        let pbr = try makeMaterial(
            baseColor: inputs.colorOrImage("diffuseColor", default: [0.18, 0.18, 0.18]),
            baseWeight: 1,
            opacity: inputs.float("opacity", default: 1),
            metallic: inputs.floatOrImage("metallic", default: 0),
            roughness: inputs.floatOrImage("roughness", default: 0.5),
            normal: inputs.image("normal"),
            occlusion: inputs.image("occlusion"),
            emissive: inputs.colorOrImage("emissiveColor", default: [0, 0, 0]),
            emissiveWeight: 1
        )
        var uniforms = pbr.uniforms
        uniforms.ior = inputs.float("ior", default: 1.5)
        uniforms.clearcoatFactor = inputs.float("clearcoat", default: 0)
        uniforms.clearcoatRoughnessFactor = inputs.float("clearcoatRoughness", default: 0.01)
        pbr.uniforms = uniforms
        warnings += inputs.warnings
        return pbr
    }

    // glTF's own model, as MaterialX's gltf_pbr node describes it (#609).
    private mutating func gltfPBR(_ shader: MaterialXElement, material: String) throws -> PBRSceneMaterial {
        var inputs = Inputs(shader: shader, material: material, converter: self)
        let pbr = try makeMaterial(
            baseColor: inputs.colorOrImage("base_color", default: [1, 1, 1]),
            baseWeight: 1,
            opacity: inputs.float("alpha", default: 1),
            metallic: inputs.floatOrImage("metallic", default: 1),
            roughness: inputs.floatOrImage("roughness", default: 1),
            normal: inputs.image("normal"),
            occlusion: inputs.image("occlusion"),
            emissive: inputs.colorOrImage("emissive", default: [0, 0, 0]),
            emissiveWeight: inputs.float("emissive_strength", default: 1)
        )
        var uniforms = pbr.uniforms
        uniforms.ior = inputs.float("ior", default: 1.5)
        uniforms.specularFactor = inputs.float("specular", default: 1)
        uniforms.specularColorFactor = inputs.color("specular_color", default: [1, 1, 1])
        uniforms.transmissionFactor = inputs.float("transmission", default: 0)
        uniforms.clearcoatFactor = inputs.float("clearcoat", default: 0)
        uniforms.clearcoatRoughnessFactor = inputs.float("clearcoat_roughness", default: 0)
        uniforms.sheenColorFactor = inputs.color("sheen_color", default: [0, 0, 0])
        uniforms.sheenRoughnessFactor = inputs.float("sheen_roughness", default: 0)
        pbr.uniforms = uniforms
        warnings += inputs.warnings
        return pbr
    }

    // OpenPBR Surface (#609). Fuzz maps to sheen and coat to clearcoat. Emission luminance is in nits; 1000 nits is
    // taken as an emissive factor of 1, which is a guess at a sensible brightness, not a physical conversion.
    private mutating func openPBRSurface(_ shader: MaterialXElement, material: String) throws -> PBRSceneMaterial {
        var inputs = Inputs(shader: shader, material: material, converter: self)
        let pbr = try makeMaterial(
            baseColor: inputs.colorOrImage("base_color", default: [0.8, 0.8, 0.8]),
            baseWeight: inputs.float("base_weight", default: 1),
            opacity: inputs.float("geometry_opacity", default: 1),
            metallic: inputs.floatOrImage("base_metalness", default: 0),
            roughness: inputs.floatOrImage("specular_roughness", default: 0.3),
            normal: inputs.image("geometry_normal"),
            occlusion: nil,
            emissive: inputs.colorOrImage("emission_color", default: [1, 1, 1]),
            emissiveWeight: inputs.float("emission_luminance", default: 0) / 1_000
        )
        var uniforms = pbr.uniforms
        uniforms.ior = inputs.float("specular_ior", default: 1.5)
        uniforms.specularFactor = inputs.float("specular_weight", default: 1)
        uniforms.specularColorFactor = inputs.color("specular_color", default: [1, 1, 1])
        uniforms.transmissionFactor = inputs.float("transmission_weight", default: 0)
        uniforms.clearcoatFactor = inputs.float("coat_weight", default: 0)
        uniforms.clearcoatRoughnessFactor = inputs.float("coat_roughness", default: 0)
        uniforms.sheenColorFactor = inputs.float("fuzz_weight", default: 0) * inputs.color("fuzz_color", default: [1, 1, 1])
        uniforms.sheenRoughnessFactor = inputs.float("fuzz_roughness", default: 0.5)
        pbr.uniforms = uniforms
        warnings += inputs.warnings
        return pbr
    }

    /// A color (or float) input that is either a constant or an image; an image's factor is white.
    typealias ColorInput = (factor: SIMD3<Float>, image: URL?)
    typealias FloatInput = (factor: Float, image: URL?)

    private func makeMaterial(baseColor: ColorInput, baseWeight: Float, opacity: Float, metallic: FloatInput, roughness: FloatInput, normal: URL?, occlusion: URL?, emissive: ColorInput, emissiveWeight: Float) throws -> PBRSceneMaterial {
        let textures = try PBRSceneMaterial.Textures(
            baseColor: baseColor.image.map { try loadTexture($0, sRGB: true) },
            metallicRoughness: metallicRoughnessTexture(metallic: metallic.image, roughness: roughness.image),
            normal: normal.map { try loadTexture($0, sRGB: false) },
            occlusion: occlusion.map { try loadTexture($0, sRGB: false) },
            emissive: emissive.image.map { try loadTexture($0, sRGB: true) }
        )
        let material = try PBRSceneMaterial(baseColor: baseColor.factor * baseWeight, opacity: opacity, metallic: metallic.factor, roughness: roughness.factor, textures: textures)
        // Textures set emissive to 1; the weight and color still apply.
        material.uniforms.emissiveFactor = emissive.factor * emissiveWeight
        // As the untextured initializer does: opacity below 1 blends.
        if opacity < 1 {
            material.uniforms.alphaMode = .blend
        }
        return material
    }

    // MARK: Textures

    private func loadTexture(_ url: URL, sRGB: Bool) throws -> MTLTexture {
        try MTKTextureLoader(device: device).newTexture(URL: url, options: [
            .SRGB: sRGB,
            .generateMipmaps: true,
            .allocateMipmaps: true,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ])
    }

    /// glTF's packing: roughness in green, metalness in blue. A missing image is white, so its factor applies alone.
    private func metallicRoughnessTexture(metallic: URL?, roughness: URL?) throws -> MTLTexture? {
        guard metallic != nil || roughness != nil else {
            return nil
        }
        let images = try [metallic, roughness].map { url in
            try url.map { url -> CGImage in
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw MaterialXError.invalidDocument("Cannot read image \(url.path)")
                }
                return image
            }
        }
        let width = images.compactMap { $0?.width }.max() ?? 1
        let height = images.compactMap { $0?.height }.max() ?? 1
        // Each image drawn into a full-size gray channel (data, not color: no color management).
        func channel(_ image: CGImage?) -> [UInt8] {
            var pixels = [UInt8](repeating: 255, count: width * height)
            guard let image else {
                return pixels
            }
            pixels.withUnsafeMutableBytes { bytes in
                let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
                context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            return pixels
        }
        let metal = channel(images[0])
        let rough = channel(images[1])
        var packed = [UInt8](repeating: 255, count: width * height * 4)
        for index in 0 ..< width * height {
            packed[index * 4 + 1] = rough[index]
            packed[index * 4 + 2] = metal[index]
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create metallic-roughness texture")
        }
        texture.label = "MaterialX Metallic Roughness"
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: packed, bytesPerRow: width * 4)
        return texture
    }

    // MARK: Inputs

    /// Resolves an input element: its value, or the image a connection leads to. Nil, with a reason, for a
    /// connection to anything else.
    func resolve(_ input: MaterialXElement, scope: MaterialXElement?, fileprefix: String) -> Result<MaterialXValue, MaterialXResolveFailure> {
        if let value = input["value"] {
            if input["type"] == "filename" {
                return .success(.image(fileURL(value, prefix: fileprefix)))
            }
            if input["type"] == "boolean" {
                return .success(.constant([value == "true" ? 1 : 0]))
            }
            let numbers = value.split { $0 == "," || $0 == " " }.compactMap { Float($0) }
            return numbers.isEmpty ? .failure(.init(reason: "value \"\(value)\" is not a number")) : .success(.constant(numbers))
        }
        if let graphName = input["nodegraph"] {
            guard let graph = root.child(named: graphName), graph.tag == "nodegraph" else {
                return .failure(.init(reason: "no nodegraph \(graphName)"))
            }
            let outputName = input["output"]
            guard let output = graph.children.first(where: { $0.tag == "output" && (outputName == nil || $0.name == outputName) }) else {
                return .failure(.init(reason: "nodegraph \(graphName) has no output \(outputName ?? "")"))
            }
            return resolve(output, scope: graph, fileprefix: graph["fileprefix"] ?? fileprefix)
        }
        if let interfaceName = input["interfacename"] {
            // An input of the enclosing nodegraph.
            guard let scope, let graphInput = scope.input(interfaceName) else {
                return .failure(.init(reason: "no nodegraph input \(interfaceName)"))
            }
            return resolve(graphInput, scope: nil, fileprefix: fileprefix)
        }
        if let nodeName = input["nodename"] {
            guard let node = (scope ?? root).child(named: nodeName) else {
                return .failure(.init(reason: "no node \(nodeName)"))
            }
            return evaluate(node, scope: scope, fileprefix: node["fileprefix"] ?? fileprefix)
        }
        return .failure(.init(reason: "no value or connection"))
    }

    // Nil defaults mean the input is required, and a nil result means the sizes do not match.
    // swiftlint:disable discouraged_optional_collection

    // A node's value: images and normal maps pass their file through; math nodes whose inputs are constants are
    // folded, and multiplying an image by a constant scales its factor (#609). Anything needing per-pixel evaluation
    // (noise, texture coordinates, math on images other than a constant multiply) fails.
    private func evaluate(_ node: MaterialXElement, scope: MaterialXElement?, fileprefix: String) -> Result<MaterialXValue, MaterialXResolveFailure> {
        let nodeName = node.name ?? node.tag
        func value(_ name: String, default fallback: [Float]? = nil) -> Result<MaterialXValue, MaterialXResolveFailure> {
            guard let input = node.input(name) else {
                return fallback.map { .success(.constant($0)) } ?? .failure(.init(reason: "\(node.tag) \(nodeName) has no \(name) input"))
            }
            return resolve(input, scope: scope, fileprefix: fileprefix)
        }
        func constants(_ names: [(String, [Float]?)]) -> Result<[[Float]], MaterialXResolveFailure> {
            var result: [[Float]] = []
            for (name, fallback) in names {
                switch value(name, default: fallback) {
                case let .success(.constant(numbers)):
                    result.append(numbers)
                case .success(.image):
                    return .failure(.init(reason: "\(node.tag) \(nodeName) on an image is not evaluated"))
                case let .failure(failure):
                    return .failure(failure)
                }
            }
            return .success(result)
        }
        func fold(_ names: [(String, [Float]?)], _ body: ([[Float]]) -> [Float]?) -> Result<MaterialXValue, MaterialXResolveFailure> {
            constants(names).flatMap { values in
                body(values).map { .success(.constant($0)) } ?? .failure(.init(reason: "\(node.tag) \(nodeName) has mismatched input sizes"))
            }
        }
        let binary: [String: (Float, Float) -> Float] = [
            "add": (+), "subtract": (-), "multiply": (*), "divide": { $1 == 0 ? 0 : $0 / $1 },
            "min": { Swift.min($0, $1) }, "max": { Swift.max($0, $1) }, "power": { pow($0, $1) }
        ]
        switch node.tag {
        case "image", "tiledimage":
            guard let file = node.input("file") else {
                return .failure(.init(reason: "image \(nodeName) has no file"))
            }
            return resolve(file, scope: scope, fileprefix: fileprefix)
        case "normalmap":
            return value("in")
        case "constant", "convert", "dot":
            return value(node.tag == "constant" ? "value" : "in")
        case "multiply":
            // An image times a constant keeps the image and scales its factor.
            switch (value("in1"), value("in2")) {
            case let (.success(.image(url, factor)), .success(.constant(numbers))), let (.success(.constant(numbers)), .success(.image(url, factor))):
                return Self.broadcast(factor, numbers, *).map { .success(.image(url, factor: $0)) } ?? .failure(.init(reason: "multiply \(nodeName) has mismatched input sizes"))
            default:
                return fold([("in1", nil), ("in2", nil)]) { Self.broadcast($0[0], $0[1], *) }
            }
        case let tag where binary[tag] != nil:
            let operation = binary[tag, default: (+)]
            return fold([("in1", nil), ("in2", nil)]) { Self.broadcast($0[0], $0[1], operation) }
        case "mix":
            return fold([("fg", nil), ("bg", nil), ("mix", [0])]) { values in
                Self.broadcast(values[0], values[1], -).flatMap { difference in
                    Self.broadcast(difference, values[2], *).flatMap { Self.broadcast(values[1], $0, +) }
                }
            }
        case "clamp":
            return fold([("in", nil), ("low", [0]), ("high", [1])]) { values in
                Self.broadcast(values[0], values[1]) { Swift.max($0, $1) }.flatMap { Self.broadcast($0, values[2]) { Swift.min($0, $1) } }
            }
        case "invert":
            return fold([("in", nil), ("amount", [1])]) { Self.broadcast($0[1], $0[0], -) }
        case "extract":
            return fold([("in", nil), ("index", [0])]) { values in
                let index = Int(values[1].first ?? 0)
                return values[0].indices.contains(index) ? [values[0][index]] : nil
            }
        case "combine2", "combine3", "combine4":
            let count = ["combine2": 2, "combine3": 3, "combine4": 4][node.tag, default: 2]
            return fold((1...count).map { ("in\($0)", nil) }) { $0.flatMap(\.self) }
        default:
            return .failure(.init(reason: "\(node.tag) nodes are not evaluated"))
        }
    }

    // Applies `operation` per channel; a single value applies to every channel of the other. Nil for other mismatches.
    private static func broadcast(_ lhs: [Float], _ rhs: [Float], _ operation: (Float, Float) -> Float) -> [Float]? {
        switch (lhs.count, rhs.count) {
        case let (left, right) where left == right: zip(lhs, rhs).map(operation)
        case (1, _): rhs.map { operation(lhs[0], $0) }
        case (_, 1): lhs.map { operation($0, rhs[0]) }
        default: nil
        }
    }

    // swiftlint:enable discouraged_optional_collection

    private func fileURL(_ path: String, prefix: String) -> URL {
        let full = prefix + path
        if full.hasPrefix("/") {
            return URL(fileURLWithPath: full)
        }
        return baseURL.appending(path: full)
    }
}

struct MaterialXResolveFailure: Error {
    var reason: String
}

/// A shader's inputs, read with defaults; anything unusable becomes a warning.
private struct Inputs {
    var shader: MaterialXElement
    var material: String
    var converter: MaterialXConverter
    var warnings: [String] = []

    private mutating func value(_ name: String) -> MaterialXValue? {
        guard let input = shader.input(name) else {
            return nil
        }
        switch converter.resolve(input, scope: nil, fileprefix: converter.root["fileprefix"] ?? "") {
        case let .success(value):
            return value
        case let .failure(failure):
            warnings.append("\(material): \(name) uses its default: \(failure.reason)")
            return nil
        }
    }

    mutating func float(_ name: String, default fallback: Float) -> Float {
        switch value(name) {
        case let .constant(numbers): return numbers.first ?? fallback
        case .image:
            warnings.append("\(material): \(name) image is not supported; the default is used")
            return fallback
        case nil: return fallback
        }
    }

    mutating func vector(_ name: String, default fallback: [Float]) -> [Float] {
        switch value(name) {
        case let .constant(numbers): return numbers
        case .image:
            warnings.append("\(material): \(name) image is not supported; the default is used")
            return fallback
        case nil: return fallback
        }
    }

    mutating func color(_ name: String, default fallback: SIMD3<Float>) -> SIMD3<Float> {
        let numbers = vector(name, default: [fallback.x, fallback.y, fallback.z])
        return numbers.count >= 3 ? SIMD3(numbers[0], numbers[1], numbers[2]) : SIMD3(repeating: numbers.first ?? 1)
    }

    mutating func colorOrImage(_ name: String, default fallback: SIMD3<Float>) -> MaterialXConverter.ColorInput {
        switch value(name) {
        case let .constant(numbers):
            return (numbers.count >= 3 ? SIMD3(numbers[0], numbers[1], numbers[2]) : SIMD3(repeating: numbers.first ?? 1), nil)
        case let .image(url, factor): return (factor.count >= 3 ? SIMD3(factor[0], factor[1], factor[2]) : SIMD3(repeating: factor.first ?? 1), url)
        case nil: return (fallback, nil)
        }
    }

    mutating func floatOrImage(_ name: String, default fallback: Float) -> MaterialXConverter.FloatInput {
        switch value(name) {
        case let .constant(numbers): return (numbers.first ?? fallback, nil)
        case let .image(url, factor): return (factor.first ?? 1, url)
        case nil: return (fallback, nil)
        }
    }

    mutating func image(_ name: String) -> URL? {
        switch value(name) {
        case let .image(url, _): return url
        case .constant: return nil
        case nil: return nil
        }
    }
}
