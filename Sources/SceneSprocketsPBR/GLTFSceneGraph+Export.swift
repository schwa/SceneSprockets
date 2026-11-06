import Foundation
import Metal
import MetalSprocketsPBR
import MetalSupport
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftGLTF
import SwiftMesh

private typealias GLTFMesh = SwiftGLTF.Mesh
private typealias GLTFMaterial = SwiftGLTF.Material

// Saves meshes that are not shapes (generated geometry such as dice) as `meshes/N.glb` in a scene package, so other
// tools can open them too (#158). The glTF holds every vertex attribute, one primitive per submesh, and a glTF
// version of each material (PBR values; Blinn-Phong approximated; core textures referenced from the package's
// textures/ folder). The exact materials stay in scene.json, so reading takes only the geometry back.
// The mesh's extras record the attribute order and buffer layout, so the vertex descriptor comes back unchanged.
public struct GLTFMeshCodec: ArchivableMeshCodec {
    public init() {}

    public func encode(_ mesh: MetalMesh, materials: [any SceneSprockets.Material], name: String?, context: SceneArchiveContext) throws -> String {
        let path = context.newFile(in: "meshes", pathExtension: "glb")
        var builder = GLTFDocumentBuilder()
        let attributeData = mesh.vertexAttributeData()
        var attributes: [GLTFMesh.Primitive.Semantic: Index<Accessor>] = [:]
        var order: [JSONValue] = []
        for attribute in attributeData {
            guard let accessorType = GLTFVertexFormat(attribute.format) else {
                throw SceneArchiveError.unsupportedMesh("vertex format \(attribute.format.rawValue) has no glTF equivalent")
            }
            let semantic = Self.semanticName(attribute.semantic, format: attribute.format, existing: attributes.keys.map(\.rawValue))
            let bounds = attribute.semantic == .position ? Self.bounds(of: attribute) : nil
            attributes[GLTFMesh.Primitive.Semantic(rawValue: semantic)] = builder.addAccessor(bytes: attribute.bytes, count: attribute.count, format: accessorType, target: .ARRAY_BUFFER, min: bounds?.min, max: bounds?.max)
            order.append(.string(semantic))
        }
        var gltfMaterials: [GLTFMaterial] = []
        for material in materials {
            gltfMaterials.append(try builder.material(for: material, context: context, packagePath: path))
        }
        let primitives = try mesh.submeshes.enumerated().map { index, submesh in
            guard let mode = Self.mode(submesh.primitiveType) else {
                throw SceneArchiveError.unsupportedMesh("primitive type \(submesh.primitiveType.rawValue)")
            }
            let indices = submesh.indices
            let indexAccessor = builder.addAccessor(bytes: indices.withUnsafeBytes { Array($0) }, count: indices.count, format: GLTFVertexFormat(componentType: .UNSIGNED_INT, type: .SCALAR), target: .ELEMENT_ARRAY_BUFFER)
            let material = gltfMaterials.isEmpty ? nil : Index<GLTFMaterial>(min(index, gltfMaterials.count - 1))
            return GLTFMesh.Primitive(attributes: attributes, indices: indexAccessor, material: material, mode: mode)
        }
        let layout: JSONValue = .string(mesh.vertexBuffers.count > 1 ? "separateBuffers" : "interleaved")
        let document = Document(
            asset: Asset(generator: "SceneSprockets"),
            scene: Index(0),
            scenes: [Scene(nodes: [Index(0)])],
            nodes: [Node(name: name, mesh: Index(0))],
            meshes: [GLTFMesh(primitives: primitives, name: mesh.label ?? name, extras: .object([Self.orderKey: .array(order), Self.layoutKey: layout]))],
            accessors: builder.accessors,
            bufferViews: builder.bufferViews,
            buffers: [Buffer(byteLength: builder.binary.count)],
            materials: gltfMaterials,
            textures: builder.textures,
            images: builder.images,
            samplers: builder.samplers
        )
        context.addFile(path, data: GLTFWriter.glbData(json: try document.jsonData(), binary: builder.binary))
        return path
    }

    public func decode(path: String, context: SceneArchiveContext) throws -> MetalMesh {
        let container = try Container(url: context.url(forPath: path))
        let document = container.document
        guard let mesh = document.meshes.first, let first = mesh.primitives.first else {
            throw SceneArchiveError.unsupportedMesh("\(path) has no mesh")
        }
        guard case let .object(extras) = mesh.extras, case let .array(orderValues) = extras[Self.orderKey] else {
            throw SceneArchiveError.unsupportedMesh("\(path) was not written by SceneSprockets")
        }
        let order = orderValues.compactMap { value -> String? in
            if case let .string(name) = value { name } else { nil }
        }
        var attributes: [MetalMesh.VertexAttributeData] = []
        for name in order {
            guard let index = first.attributes[GLTFMesh.Primitive.Semantic(rawValue: name)] else {
                throw SceneArchiveError.unsupportedMesh("\(path) has no \(name) attribute")
            }
            let accessor = try index.resolve(in: document)
            guard let format = GLTFVertexFormat(componentType: accessor.componentType, type: accessor.type, normalized: accessor.normalized).metalFormat else {
                throw SceneArchiveError.unsupportedMesh("\(path): \(name) has an unsupported format")
            }
            let bytes = [UInt8](try container.data(for: accessor))
            attributes.append(MetalMesh.VertexAttributeData(semantic: Self.semantic(name), format: format, bytes: bytes, count: accessor.count))
        }
        let submeshes = try mesh.primitives.map { primitive in
            guard let index = primitive.indices else {
                throw SceneArchiveError.unsupportedMesh("\(path): a primitive has no indices")
            }
            let accessor = try index.resolve(in: document)
            let data = try container.data(for: accessor)
            let indices: [UInt32] = switch accessor.componentType {
            case .UNSIGNED_INT: data.withUnsafeBytes { Array($0.bindMemory(to: UInt32.self)) }
            case .UNSIGNED_SHORT: data.withUnsafeBytes { $0.bindMemory(to: UInt16.self).map(UInt32.init) }
            case .UNSIGNED_BYTE: data.map(UInt32.init)
            default: throw SceneArchiveError.unsupportedMesh("\(path): unsupported index type")
            }
            return MetalMesh.SubmeshIndices(indices: indices, primitiveType: Self.primitiveType(primitive.mode))
        }
        var layout = MetalMesh.BufferLayout.interleaved
        if case .string("separateBuffers") = extras[Self.layoutKey] {
            layout = .separateBuffers
        }
        return MetalMesh(device: try context.device, attributes: attributes, submeshes: submeshes, label: mesh.name, bufferLayout: layout)
    }

    static let orderKey = "sceneSprocketsAttributeOrder"
    static let layoutKey = "sceneSprocketsBufferLayout"

    // glTF names where they exist (TANGENT must be four floats); "_"-prefixed application names otherwise.
    static func semanticName(_ semantic: VertexDescriptor.Attribute.Semantic, format: MTLVertexFormat, existing: [String]) -> String {
        let name = switch semantic {
        case .position: "POSITION"
        case .normal: "NORMAL"
        case .tangent: format == .float4 ? "TANGENT" : "_TANGENT3"
        case .bitangent: "_BITANGENT"
        case let .texcoord(set): "TEXCOORD_\(set)"
        case let .color(set): "COLOR_\(set)"
        case let .jointIndices(set): "JOINTS_\(set)"
        case let .jointWeights(set): "WEIGHTS_\(set)"
        case .userDefined: "_USER"
        case .unknown: "_UNKNOWN"
        }
        var unique = name
        var suffix = 1
        while existing.contains(unique) {
            unique = "\(name)_\(suffix)"
            suffix += 1
        }
        return unique
    }

    static func semantic(_ name: String) -> VertexDescriptor.Attribute.Semantic {
        func set(_ prefix: String) -> Int? {
            name.hasPrefix(prefix) ? Int(name.dropFirst(prefix.count)) : nil
        }
        if let set = set("TEXCOORD_") {
            return .texcoord(set)
        }
        if let set = set("COLOR_") {
            return .color(set)
        }
        if let set = set("JOINTS_") {
            return .jointIndices(set)
        }
        if let set = set("WEIGHTS_") {
            return .jointWeights(set)
        }
        return switch name.split(separator: "_", omittingEmptySubsequences: true).first.map(String.init) ?? name {
        case "POSITION": .position
        case "NORMAL": .normal
        case "TANGENT", "TANGENT3": .tangent
        case "BITANGENT": .bitangent
        case "USER": .userDefined
        default: .unknown
        }
    }

    static func bounds(of attribute: MetalMesh.VertexAttributeData) -> (min: [Double], max: [Double])? {
        // Packed as three floats; SIMD3<Float> itself takes 16 bytes.
        let positions: [SIMD3<Float>] = attribute.bytes.withUnsafeBytes { bytes in
            (0 ..< attribute.count).map { index in
                SIMD3((0 ..< 3).map { bytes.loadUnaligned(fromByteOffset: index * 12 + $0 * 4, as: Float.self) })
            }
        }
        guard let first = positions.first else {
            return nil
        }
        let (minimum, maximum) = positions.reduce((first, first)) { (simd_min($0.0, $1), simd_max($0.1, $1)) }
        return ([minimum.x, minimum.y, minimum.z].map(Double.init), [maximum.x, maximum.y, maximum.z].map(Double.init))
    }

    fileprivate static func mode(_ type: MTLPrimitiveType) -> GLTFMesh.Primitive.Mode? {
        switch type {
        case .point: .POINTS
        case .line: .LINES
        case .lineStrip: .LINE_STRIP
        case .triangle: .TRIANGLES
        case .triangleStrip: .TRIANGLE_STRIP
        @unknown default: nil
        }
    }

    fileprivate static func primitiveType(_ mode: GLTFMesh.Primitive.Mode) -> MTLPrimitiveType {
        switch mode {
        case .POINTS: .point
        case .LINES, .LINE_LOOP: .line
        case .LINE_STRIP: .lineStrip
        case .TRIANGLE_STRIP: .triangleStrip
        case .TRIANGLES, .TRIANGLE_FAN: .triangle
        }
    }
}

// An accessor's component type, element type and normalization, and the Metal vertex format that matches it.
struct GLTFVertexFormat: Hashable {
    var componentType: Accessor.ComponentType
    var type: Accessor.AttributeType
    var normalized = false

    static let table: [(MTLVertexFormat, Self)] = [
        (.float, .init(componentType: .FLOAT, type: .SCALAR)),
        (.float2, .init(componentType: .FLOAT, type: .VEC2)),
        (.float3, .init(componentType: .FLOAT, type: .VEC3)),
        (.float4, .init(componentType: .FLOAT, type: .VEC4)),
        (.uchar4, .init(componentType: .UNSIGNED_BYTE, type: .VEC4)),
        (.uchar4Normalized, .init(componentType: .UNSIGNED_BYTE, type: .VEC4, normalized: true)),
        (.ushort2, .init(componentType: .UNSIGNED_SHORT, type: .VEC2)),
        (.ushort4, .init(componentType: .UNSIGNED_SHORT, type: .VEC4)),
        (.ushort2Normalized, .init(componentType: .UNSIGNED_SHORT, type: .VEC2, normalized: true)),
        (.ushort4Normalized, .init(componentType: .UNSIGNED_SHORT, type: .VEC4, normalized: true)),
        (.short2, .init(componentType: .SHORT, type: .VEC2)),
        (.short4, .init(componentType: .SHORT, type: .VEC4)),
        (.char4, .init(componentType: .BYTE, type: .VEC4)),
        (.uint, .init(componentType: .UNSIGNED_INT, type: .SCALAR))
    ]

    init(componentType: Accessor.ComponentType, type: Accessor.AttributeType, normalized: Bool = false) {
        self.componentType = componentType
        self.type = type
        self.normalized = normalized
    }

    init?(_ format: MTLVertexFormat) {
        guard let match = Self.table.first(where: { $0.0 == format }) else {
            return nil
        }
        self = match.1
    }

    var metalFormat: MTLVertexFormat? {
        Self.table.first { $0.1 == self }?.0
    }
}

// Collects a glTF document's binary buffer, views, accessors, textures and materials.
struct GLTFDocumentBuilder {
    var binary = Data()
    var bufferViews: [BufferView] = []
    var accessors: [Accessor] = []
    var images: [Image] = []
    var textures: [Texture] = []
    var samplers: [Sampler] = []
    private var imageIndices: [String: Int] = [:]

    // swiftlint:disable:next discouraged_optional_collection - nil omits min and max from the accessor
    mutating func addAccessor(bytes: [UInt8], count: Int, format: GLTFVertexFormat, target: BufferView.Target, min: [Double]? = nil, max: [Double]? = nil) -> Index<Accessor> {
        while !binary.count.isMultiple(of: 4) {
            binary.append(0)
        }
        bufferViews.append(BufferView(buffer: Index(0), byteOffset: binary.count, byteLength: bytes.count, target: target))
        binary.append(contentsOf: bytes)
        accessors.append(Accessor(bufferView: Index(bufferViews.count - 1), componentType: format.componentType, normalized: format.normalized, count: count, type: format.type, max: max, min: min))
        return Index(accessors.count - 1)
    }

    // A glTF material for `material`: PBR values as they are, Blinn-Phong mapped to the nearest PBR values.
    fileprivate mutating func material(for material: any SceneSprockets.Material, context: SceneArchiveContext, packagePath: String) throws -> GLTFMaterial {
        switch material {
        case let pbr as PBRSceneMaterial:
            let uniforms = pbr.pbrMaterial.uniforms
            func info(_ slot: PBRTextureSlot, _ index: PBRMaterialTextureIndex, scale: Float? = nil, strength: Float? = nil) throws -> TextureInfo? {
                guard slot.enabled != 0, let texture = try self.texture(pbr.pbrMaterial.textureBindings[Int(index.rawValue)].texture, context: context, packagePath: packagePath) else {
                    return nil
                }
                return TextureInfo(index: texture, texCoord: Int(slot.texCoord), scale: scale, strength: strength)
            }
            let alphaMode: GLTFMaterial.AlphaMode = switch uniforms.alphaMode {
            case .mask: .MASK
            case .blend: .BLEND
            default: .OPAQUE
            }
            return GLTFMaterial(
                name: pbr.pbrMaterial.name,
                pbrMetallicRoughness: .init(
                    baseColorFactor: uniforms.baseColorFactor,
                    baseColorTexture: try info(uniforms.baseColor, kPBRTextureBaseColor),
                    metallicFactor: uniforms.metallicFactor,
                    roughnessFactor: uniforms.roughnessFactor,
                    metallicRoughnessTexture: try info(uniforms.metallicRoughness, kPBRTextureMetallicRoughness)
                ),
                normalTexture: try info(uniforms.normal, kPBRTextureNormal, scale: uniforms.normalScale),
                occlusionTexture: try info(uniforms.occlusion, kPBRTextureOcclusion, strength: uniforms.occlusionStrength),
                emissiveTexture: try info(uniforms.emissive, kPBRTextureEmissive),
                emissiveFactor: uniforms.emissiveFactor,
                alphaMode: alphaMode,
                alphaCutoff: alphaMode == .MASK ? uniforms.alphaCutoff : nil,
                doubleSided: pbr.pbrMaterial.doubleSided
            )
        case let blinnPhong as BlinnPhongSceneMaterial:
            var baseColor = SIMD4<Float>(0.8, 0.8, 0.8, blinnPhong.opacity)
            var baseColorTexture: TextureInfo?
            switch blinnPhong.diffuse {
            case let .color(color):
                baseColor = SIMD4(color, blinnPhong.opacity)
            case let .texture(texture, _, tint):
                baseColor = SIMD4(tint, blinnPhong.opacity)
                baseColorTexture = try self.texture(texture, context: context, packagePath: packagePath).map { TextureInfo(index: $0) }
            }
            var emissive: SIMD3<Float>?
            if case let .color(color) = blinnPhong.emission, color != .zero {
                emissive = color
            }
            // Phong exponent to roughness, as in common Blinn-Phong to PBR conversions.
            let roughness = sqrt(2 / (blinnPhong.shininess + 2))
            return GLTFMaterial(
                pbrMetallicRoughness: .init(baseColorFactor: baseColor, baseColorTexture: baseColorTexture, metallicFactor: 0, roughnessFactor: roughness),
                emissiveFactor: emissive,
                alphaMode: blinnPhong.opacity < 1 ? .BLEND : .OPAQUE
            )
        default:
            return GLTFMaterial(name: String(describing: type(of: material)))
        }
    }

    // A glTF texture for `texture`, pointing at the package's PNG of it. Nil for textures not saved as PNG.
    private mutating func texture(_ texture: MTLTexture, context: SceneArchiveContext, packagePath: String) throws -> Index<Texture>? {
        let file = try context.encode(texture: texture).file
        guard file.hasSuffix(".png") else {
            return nil
        }
        if let index = imageIndices[file] {
            return Index(index)
        }
        // Relative to the glTF file, which sits one folder down in the package.
        let depth = packagePath.split(separator: "/").count - 1
        images.append(Image(uri: URI(String(repeating: "../", count: depth) + file), mimeType: "image/png"))
        if samplers.isEmpty {
            samplers.append(Sampler())
        }
        textures.append(Texture(source: Index(images.count - 1), sampler: Index(0)))
        imageIndices[file] = textures.count - 1
        return Index(textures.count - 1)
    }
}
