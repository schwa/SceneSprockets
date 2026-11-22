import CoreGraphics
import Foundation
import ImageIO
import Metal
import MetalKit
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import simd

/// The materials of a MaterialX (`.mtlx`) document, as ``PBRSceneMaterial``s (#528).
///
/// Each `surfacematerial` whose surface shader is a `standard_surface` or `UsdPreviewSurface` becomes one material.
/// Shader inputs may be constant values or image textures, connected directly or through a nodegraph output (a
/// `normalmap` node in front of the normal image is followed). Other node graphs (math, procedural patterns) are not
/// evaluated: those inputs keep their defaults and are reported in ``warnings``.
public struct MaterialXDocument {
    public struct Material {
        /// The `surfacematerial` element's name.
        public var name: String
        public var material: PBRSceneMaterial
    }

    public var materials: [Material]
    /// What was not converted, such as unsupported shaders or node graphs.
    public var warnings: [String]

    /// Loads `url`. Relative texture paths resolve against the file's folder and any `fileprefix` attributes.
    public init(url: URL, device: MTLDevice? = nil) throws {
        try self.init(data: Data(contentsOf: url), baseURL: url.deletingLastPathComponent(), device: device)
    }

    public init(data: Data, baseURL: URL, device: MTLDevice? = nil) throws {
        let root = try MaterialXElement.parse(data)
        guard root.tag == "materialx" else {
            throw MaterialXError.invalidDocument("The root element is <\(root.tag)>, not <materialx>")
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

struct MaterialXElement {
    var tag: String
    var attributes: [String: String]
    var children: [Self]

    subscript(attribute: String) -> String? { attributes[attribute] }

    var name: String? { attributes["name"] }

    func child(named name: String) -> Self? {
        children.first { $0.name == name }
    }

    func input(_ name: String) -> Self? {
        children.first { $0.tag == "input" && $0.name == name }
    }

    static func parse(_ data: Data) throws -> Self {
        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else {
            throw MaterialXError.invalidDocument(parser.parserError.map { "\($0)" } ?? "empty document")
        }
        return root
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var stack: [MaterialXElement] = []
        var root: MaterialXElement?

        func parser(_: XMLParser, didStartElement elementName: String, namespaceURI _: String?, qualifiedName _: String?, attributes: [String: String] = [:]) {
            stack.append(MaterialXElement(tag: elementName, attributes: attributes, children: []))
        }

        func parser(_: XMLParser, didEndElement _: String, namespaceURI _: String?, qualifiedName _: String?) {
            guard let element = stack.popLast() else {
                return
            }
            if stack.isEmpty {
                root = element
            } else {
                stack[stack.count - 1].children.append(element)
            }
        }
    }
}

// MARK: - Conversion

/// An input's value: a constant, or an image file.
enum MaterialXValue: Equatable {
    case constant([Float])
    case image(URL)
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
        if let nodeName = input["nodename"] {
            guard let node = (scope ?? root).child(named: nodeName) else {
                return .failure(.init(reason: "no node \(nodeName)"))
            }
            switch node.tag {
            case "image", "tiledimage":
                guard let file = node.input("file") else {
                    return .failure(.init(reason: "image \(nodeName) has no file"))
                }
                return resolve(file, scope: scope, fileprefix: node["fileprefix"] ?? fileprefix)
            case "normalmap":
                guard let inner = node.input("in") else {
                    return .failure(.init(reason: "normalmap \(nodeName) has no input"))
                }
                return resolve(inner, scope: scope, fileprefix: fileprefix)
            default:
                return .failure(.init(reason: "\(node.tag) nodes are not evaluated"))
            }
        }
        return .failure(.init(reason: "no value or connection"))
    }

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
        case let .image(url): return ([1, 1, 1], url)
        case nil: return (fallback, nil)
        }
    }

    mutating func floatOrImage(_ name: String, default fallback: Float) -> MaterialXConverter.FloatInput {
        switch value(name) {
        case let .constant(numbers): return (numbers.first ?? fallback, nil)
        case let .image(url): return (1, url)
        case nil: return (fallback, nil)
        }
    }

    mutating func image(_ name: String) -> URL? {
        switch value(name) {
        case let .image(url): return url
        case .constant: return nil
        case nil: return nil
        }
    }
}
