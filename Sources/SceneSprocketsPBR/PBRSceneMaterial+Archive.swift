import Foundation
import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import SceneSprockets

// Saved by SceneArchive. The uniforms are stored as their raw bytes (a plain C struct), checked against the size
// when read, so an archive only loads with the same MetalSprocketsPBR layout. Samplers and animatable texture
// transforms are not saved; textures load with the placeholder's linear, repeating sampler.
extension PBRSceneMaterial: ArchivableMaterial {
    public static let archiveTypeName = "pbr"

    enum ArchiveKeys: String, CodingKey {
        case name, uniforms, uniformsSize, doubleSided, textures, blendMode, depthTest, depthWrite, colorWriteMask, fillMode
    }

    public func encode(to encoder: Encoder) throws {
        let context = try encoder.sceneArchive
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encodeIfPresent(pbrMaterial.name, forKey: .name)
        let uniforms = withUnsafeBytes(of: pbrMaterial.uniforms) { Data($0) }
        try container.encode(uniforms, forKey: .uniforms)
        try container.encode(uniforms.count, forKey: .uniformsSize)
        try container.encode(pbrMaterial.doubleSided, forKey: .doubleSided)
        // One entry per PBRMaterialTextureIndex; nil for the placeholder.
        let textures = try pbrMaterial.textureBindings.map { binding in
            Self.isPlaceholder(binding.texture) ? nil : try context.encode(texture: binding.texture)
        }
        try container.encode(textures, forKey: .textures)
        let state = pbrMaterial.renderState
        try container.encodeIfPresent(state.blendMode.map(Self.name), forKey: .blendMode)
        try container.encode(state.depthTest, forKey: .depthTest)
        try container.encode(Self.name(state.depthWrite), forKey: .depthWrite)
        try container.encode(state.colorWriteMask.rawValue, forKey: .colorWriteMask)
        try container.encode(state.fillMode == .lines ? "lines" : "fill", forKey: .fillMode)
        if !pbrMaterial.textureTransforms.isEmpty {
            context.warn("PBR material \(pbrMaterial.name ?? ""): animatable texture transforms not saved")
        }
    }

    public init(from decoder: Decoder) throws {
        let context = try decoder.sceneArchive
        let device = try context.device
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        let bytes = try container.decode(Data.self, forKey: .uniforms)
        guard bytes.count == MemoryLayout<PBRMaterialUniforms>.size, try container.decode(Int.self, forKey: .uniformsSize) == bytes.count else {
            throw DecodingError.dataCorruptedError(forKey: .uniforms, in: container, debugDescription: "PBR uniforms are \(bytes.count) bytes; this MetalSprocketsPBR expects \(MemoryLayout<PBRMaterialUniforms>.size)")
        }
        var uniforms = PBRMaterialUniforms.defaults()
        withUnsafeMutableBytes(of: &uniforms) { destination in
            bytes.withUnsafeBytes { destination.copyMemory(from: $0) }
        }
        let placeholder = try PBRMaterial.placeholderBinding(device: device)
        let references = try container.decode([SceneArchiveContext.TextureReference?].self, forKey: .textures)
        var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
        for (index, reference) in references.enumerated() where index < bindings.count {
            if let reference {
                bindings[index] = .init(texture: try context.texture(for: reference), sampler: placeholder.sampler)
            }
        }
        let material = try PBRMaterial(name: try container.decodeIfPresent(String.self, forKey: .name), uniforms: uniforms, doubleSided: try container.decode(Bool.self, forKey: .doubleSided), textureBindings: bindings, device: device)
        material.renderState = PBRRenderState(
            blendMode: try container.decodeIfPresent(String.self, forKey: .blendMode).flatMap(Self.blendMode),
            depthTest: try container.decode(Bool.self, forKey: .depthTest),
            depthWrite: Self.depthWrite(try container.decode(String.self, forKey: .depthWrite)),
            colorWriteMask: PBRRenderState.ColorWriteMask(rawValue: try container.decode(UInt8.self, forKey: .colorWriteMask)),
            fillMode: try container.decode(String.self, forKey: .fillMode) == "lines" ? .lines : .fill
        )
        self.init(material)
    }

    private static func isPlaceholder(_ texture: MTLTexture) -> Bool {
        texture.width == 1 && texture.height == 1 && texture.label == "PBR Placeholder"
    }

    private static func name(_ mode: PBRRenderState.BlendMode) -> String {
        switch mode {
        case .opaque: "opaque"
        case .alpha: "alpha"
        case .premultiplied: "premultiplied"
        case .additive: "additive"
        }
    }

    private static func blendMode(_ name: String) -> PBRRenderState.BlendMode? {
        ["opaque": .opaque, "alpha": .alpha, "premultiplied": .premultiplied, "additive": .additive][name]
    }

    private static func name(_ depthWrite: PBRRenderState.DepthWrite) -> String {
        switch depthWrite {
        case .automatic: "automatic"
        case .enabled: "enabled"
        case .disabled: "disabled"
        }
    }

    private static func depthWrite(_ name: String) -> PBRRenderState.DepthWrite {
        switch name {
        case "enabled": .enabled
        case "disabled": .disabled
        default: .automatic
        }
    }
}

// The shared studio is stored by name; other environments as their equirectangular source (level 0, half floats).
extension PBREnvironment: ArchivableEnvironmentMap {
    public static let archiveTypeName = "pbrEnvironment"

    enum ArchiveKeys: String, CodingKey {
        case studio, source
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        if self === PBREnvironment.studio {
            try container.encode(true, forKey: .studio)
        } else {
            try container.encode(try encoder.sceneArchive.encode(texture: source), forKey: .source)
        }
    }

    public static func decodeEnvironmentMap(from decoder: Decoder) throws -> any EnvironmentMap {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        if try container.decodeIfPresent(Bool.self, forKey: .studio) == true {
            return PBREnvironment.studio
        }
        let context = try decoder.sceneArchive
        let reference = try container.decode(SceneArchiveContext.TextureReference.self, forKey: .source)
        guard reference.pixelFormat == MTLPixelFormat.rgba16Float.rawValue else {
            throw DecodingError.dataCorruptedError(forKey: .source, in: container, debugDescription: "Environment source must be rgba16Float")
        }
        let data = try context.data(for: reference)
        let rgba = data.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        return try PBREnvironment(source: .equirectangularPixels(width: reference.width, height: reference.height, rgba: rgba), device: try context.device)
    }
}
