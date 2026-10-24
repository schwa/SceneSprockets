import Foundation
import Metal
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import SceneSprockets

// Saved by SceneArchive. The uniforms are stored field by field (see PBRUniformsArchive); archives from before that
// stored raw bytes, which still read when the layout matches. Animatable texture transforms are stored by their
// slot's name. Samplers are saved next to their textures (#180); older archives load with the placeholder's sampler.
extension PBRSceneMaterial: ArchivableMaterial {
    public static let archiveTypeName = "pbr"

    enum ArchiveKeys: String, CodingKey {
        case name, uniforms, uniformsSize, parameters, textureTransforms, doubleSided, textures, samplers, blendMode, depthTest, depthWrite, colorWriteMask, fillMode
    }

    public func encode(to encoder: Encoder) throws {
        let context = try encoder.sceneArchive
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encodeIfPresent(pbrMaterial.name, forKey: .name)
        try PBRUniformsArchive.encode(pbrMaterial.uniforms, to: container.superEncoder(forKey: .parameters))
        try container.encode(pbrMaterial.doubleSided, forKey: .doubleSided)
        // One entry per PBRMaterialTextureIndex; nil for the placeholder.
        let textures = try pbrMaterial.textureBindings.map { binding in
            Self.isPlaceholder(binding.texture) ? nil : try context.encode(texture: binding.texture)
        }
        try container.encode(textures, forKey: .textures)
        let samplers = pbrMaterial.textureBindings.map { binding in
            Self.isPlaceholder(binding.texture) ? nil : SceneArchiveContext.SamplerReference(binding.samplerDescriptor)
        }
        try container.encode(samplers, forKey: .samplers)
        let state = pbrMaterial.renderState
        try container.encodeIfPresent(state.blendMode.map(Self.name), forKey: .blendMode)
        try container.encode(state.depthTest, forKey: .depthTest)
        try container.encode(Self.name(state.depthWrite), forKey: .depthWrite)
        try container.encode(state.colorWriteMask.rawValue, forKey: .colorWriteMask)
        try container.encode(state.fillMode == .lines ? "lines" : "fill", forKey: .fillMode)
        try encodeTextureTransforms(into: &container, context: context)
    }

    public init(from decoder: Decoder) throws {
        let context = try decoder.sceneArchive
        let device = try context.device
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        let uniforms: PBRMaterialUniforms
        if container.contains(.parameters) {
            uniforms = try PBRUniformsArchive.decode(from: container.superDecoder(forKey: .parameters))
        } else {
            uniforms = try Self.decodeRawUniforms(container)
        }
        let placeholder = try PBRMaterial.placeholderBinding(device: device)
        let references = try container.decode([SceneArchiveContext.TextureReference?].self, forKey: .textures)
        var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
        let samplers = try container.decodeIfPresent([SceneArchiveContext.SamplerReference?].self, forKey: .samplers) ?? []
        for (index, reference) in references.enumerated() where index < bindings.count {
            if let reference {
                let sampler = (index < samplers.count ? samplers[index] : nil)?.descriptor ?? placeholder.samplerDescriptor
                bindings[index] = try .init(texture: try context.texture(for: reference), samplerDescriptor: sampler, device: device)
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
        material.textureTransforms = try Self.decodeTextureTransforms(container, context: context)
        self.init(material)
    }

    enum TransformKeys: String, CodingKey {
        case slot, offset, rotation, scale
    }

    private func encodeTextureTransforms(into container: inout KeyedEncodingContainer<ArchiveKeys>, context: SceneArchiveContext) throws {
        guard !pbrMaterial.textureTransforms.isEmpty else {
            return
        }
        var transforms = container.nestedContainer(keyedBy: PBRUniformsArchive.Key.self, forKey: .textureTransforms)
        for (name, transform) in pbrMaterial.textureTransforms.sorted(by: { $0.key < $1.key }) {
            guard let slot = PBRUniformsArchive.slots.first(where: { $0.1 == transform.slot })?.0 else {
                context.warn("PBR material \(pbrMaterial.name ?? ""): texture transform \"\(name)\" has an unknown slot; skipped")
                continue
            }
            var item = transforms.nestedContainer(keyedBy: TransformKeys.self, forKey: PBRUniformsArchive.Key(name))
            try item.encode(slot, forKey: .slot)
            try item.encode(transform.offset, forKey: .offset)
            try item.encode(transform.rotation, forKey: .rotation)
            try item.encode(transform.scale, forKey: .scale)
        }
    }

    private static func decodeTextureTransforms(_ container: KeyedDecodingContainer<ArchiveKeys>, context: SceneArchiveContext) throws -> [String: PBRMaterial.TextureTransform] {
        guard container.contains(.textureTransforms) else {
            return [:]
        }
        let transforms = try container.nestedContainer(keyedBy: PBRUniformsArchive.Key.self, forKey: .textureTransforms)
        var result: [String: PBRMaterial.TextureTransform] = [:]
        for key in transforms.allKeys {
            let item = try transforms.nestedContainer(keyedBy: TransformKeys.self, forKey: key)
            let slotName = try item.decode(String.self, forKey: .slot)
            guard let slot = PBRUniformsArchive.slots.first(where: { $0.0 == slotName })?.1 else {
                context.warn("PBR texture transform \"\(key.stringValue)\": unknown slot \"\(slotName)\"; skipped")
                continue
            }
            result[key.stringValue] = PBRMaterial.TextureTransform(slot: slot, offset: try item.decode(SIMD2<Float>.self, forKey: .offset), rotation: try item.decode(Float.self, forKey: .rotation), scale: try item.decode(SIMD2<Float>.self, forKey: .scale))
        }
        return result
    }

    // Archives from before #163.
    private static func decodeRawUniforms(_ container: KeyedDecodingContainer<ArchiveKeys>) throws -> PBRMaterialUniforms {
        let bytes = try container.decode(Data.self, forKey: .uniforms)
        guard bytes.count == MemoryLayout<PBRMaterialUniforms>.size, try container.decode(Int.self, forKey: .uniformsSize) == bytes.count else {
            throw DecodingError.dataCorruptedError(forKey: .uniforms, in: container, debugDescription: "PBR uniforms are \(bytes.count) bytes; this MetalSprocketsPBR expects \(MemoryLayout<PBRMaterialUniforms>.size)")
        }
        var uniforms = PBRMaterialUniforms.defaults()
        withUnsafeMutableBytes(of: &uniforms) { destination in
            bytes.withUnsafeBytes { destination.copyMemory(from: $0) }
        }
        return uniforms
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
