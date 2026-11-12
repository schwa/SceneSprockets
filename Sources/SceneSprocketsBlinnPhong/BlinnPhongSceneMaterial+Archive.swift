import Metal
import SceneSprockets

// Saved by SceneArchive. Samplers are saved with their textures (#180); without one, the default linear, repeating
// sampler is used.
extension BlinnPhongSceneMaterial: ArchivableMaterial {
    public static let archiveTypeName = "blinnPhong"

    enum ArchiveKeys: String, CodingKey {
        case ambient, diffuse, specular, shininess, opacity, usesDiffuseTextureAlpha, emission, normalMap, cullMode, renderState
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(ambient, forKey: .ambient)
        try container.encode(diffuse, forKey: .diffuse)
        try container.encode(specular, forKey: .specular)
        try container.encode(shininess, forKey: .shininess)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(usesDiffuseTextureAlpha, forKey: .usesDiffuseTextureAlpha)
        try container.encode(emission, forKey: .emission)
        try container.encodeIfPresent(normalMap, forKey: .normalMap)
        try container.encode(renderState, forKey: .renderState)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        // Before #368 the normal map was a bare texture reference.
        let normalMap: Source? = if let reference = try? container.decodeIfPresent(SceneArchiveContext.TextureReference.self, forKey: .normalMap) {
            .texture(try decoder.sceneArchive.texture(for: reference))
        } else {
            try container.decodeIfPresent(Source.self, forKey: .normalMap)
        }
        self.init(
            ambient: try container.decode(Source.self, forKey: .ambient),
            diffuse: try container.decode(Source.self, forKey: .diffuse),
            specular: try container.decode(Source.self, forKey: .specular),
            shininess: try container.decode(Float.self, forKey: .shininess),
            opacity: try container.decode(Float.self, forKey: .opacity),
            usesDiffuseTextureAlpha: try container.decode(Bool.self, forKey: .usesDiffuseTextureAlpha),
            emission: try container.decode(Source.self, forKey: .emission),
            normalMap: normalMap,
            renderState: try container.decode(MaterialRenderState.self, forKey: .renderState)
        )
        // Before #377 the cull mode was a top-level key, not part of renderState.
        if let cullMode = try container.decodeIfPresent(UInt.self, forKey: .cullMode).flatMap(MTLCullMode.init(rawValue:)) {
            renderState.cullMode = cullMode
        }
    }
}

extension BlinnPhongSceneMaterial.Source: Codable {
    enum ArchiveKeys: String, CodingKey {
        case color, texture, sampler, tint
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        switch self {
        case let .color(color):
            try container.encode(color, forKey: .color)
        case let .texture(texture, sampler, tint):
            try container.encode(try encoder.sceneArchive.encode(texture: texture), forKey: .texture)
            try container.encodeIfPresent(sampler.map(SceneArchiveContext.SamplerReference.init), forKey: .sampler)
            try container.encode(tint, forKey: .tint)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        if let reference = try container.decodeIfPresent(SceneArchiveContext.TextureReference.self, forKey: .texture) {
            let sampler = try container.decodeIfPresent(SceneArchiveContext.SamplerReference.self, forKey: .sampler)?.descriptor
            self = .texture(try decoder.sceneArchive.texture(for: reference), sampler: sampler, tint: try container.decode(SIMD3<Float>.self, forKey: .tint))
        } else {
            self = .color(try container.decode(SIMD3<Float>.self, forKey: .color))
        }
    }
}
