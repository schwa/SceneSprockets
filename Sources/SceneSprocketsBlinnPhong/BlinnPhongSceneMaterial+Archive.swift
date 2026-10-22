import Metal
import SceneSprockets

// Saved by SceneArchive. Samplers are not saved: textures load with the default linear, repeating sampler.
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
        if let normalMap {
            try container.encode(try encoder.sceneArchive.encode(texture: normalMap), forKey: .normalMap)
        }
        try container.encode(cullMode.rawValue, forKey: .cullMode)
        try container.encode(renderState, forKey: .renderState)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        let normalMap = try container.decodeIfPresent(SceneArchiveContext.TextureReference.self, forKey: .normalMap).map { try decoder.sceneArchive.texture(for: $0) }
        self.init(
            ambient: try container.decode(Source.self, forKey: .ambient),
            diffuse: try container.decode(Source.self, forKey: .diffuse),
            specular: try container.decode(Source.self, forKey: .specular),
            shininess: try container.decode(Float.self, forKey: .shininess),
            opacity: try container.decode(Float.self, forKey: .opacity),
            usesDiffuseTextureAlpha: try container.decode(Bool.self, forKey: .usesDiffuseTextureAlpha),
            emission: try container.decode(Source.self, forKey: .emission),
            normalMap: normalMap,
            cullMode: MTLCullMode(rawValue: try container.decode(UInt.self, forKey: .cullMode)) ?? .none,
            renderState: try container.decode(MaterialRenderState.self, forKey: .renderState)
        )
    }
}

extension BlinnPhongSceneMaterial.Source: Codable {
    enum ArchiveKeys: String, CodingKey {
        case color, texture, tint
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        switch self {
        case let .color(color):
            try container.encode(color, forKey: .color)
        case let .texture(texture, _, tint):
            try container.encode(try encoder.sceneArchive.encode(texture: texture), forKey: .texture)
            try container.encode(tint, forKey: .tint)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        if let reference = try container.decodeIfPresent(SceneArchiveContext.TextureReference.self, forKey: .texture) {
            self = .texture(try decoder.sceneArchive.texture(for: reference), tint: try container.decode(SIMD3<Float>.self, forKey: .tint))
        } else {
            self = .color(try container.decode(SIMD3<Float>.self, forKey: .color))
        }
    }
}
