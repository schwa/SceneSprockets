import Foundation
import MetalSprocketsPBRShaders
import simd

// PBRMaterialUniforms field by field, by name (#163), so archives survive MetalSprocketsPBR layout changes. Missing
// fields keep their defaults; unknown ones are ignored. Fields describing the mesh (hasTangents, hasNormals,
// isPointOrLine) are set when drawing, so they are not saved.
enum PBRUniformsArchive {
    struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }

        init(_ string: String) {
            stringValue = string
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }

    typealias Uniforms = PBRMaterialUniforms

    // Computed: key paths are not Sendable.
    static var floats: [(String, WritableKeyPath<Uniforms, Float>)] {
        [
        ("metallicFactor", \.metallicFactor),
        ("roughnessFactor", \.roughnessFactor),
        ("normalScale", \.normalScale),
        ("occlusionStrength", \.occlusionStrength),
        ("alphaCutoff", \.alphaCutoff),
        ("emissiveStrength", \.emissiveStrength),
        ("transmissionFactor", \.transmissionFactor),
        ("thicknessFactor", \.thicknessFactor),
        ("attenuationDistance", \.attenuationDistance),
        ("ior", \.ior),
        ("specularFactor", \.specularFactor),
        ("iridescenceFactor", \.iridescenceFactor),
        ("iridescenceIor", \.iridescenceIor),
        ("iridescenceThicknessMinimum", \.iridescenceThicknessMinimum),
        ("iridescenceThicknessMaximum", \.iridescenceThicknessMaximum),
        ("anisotropyStrength", \.anisotropyStrength),
        ("anisotropyRotation", \.anisotropyRotation),
        ("sheenRoughnessFactor", \.sheenRoughnessFactor),
        ("clearcoatFactor", \.clearcoatFactor),
        ("clearcoatRoughnessFactor", \.clearcoatRoughnessFactor),
        ("clearcoatNormalScale", \.clearcoatNormalScale),
        ("dispersion", \.dispersion),
        ("diffuseTransmissionFactor", \.diffuseTransmissionFactor),
        ("retroreflectionFactor", \.retroreflectionFactor),
        ("glossinessFactor", \.glossinessFactor),
        ]
    }

    static var vectors3: [(String, WritableKeyPath<Uniforms, SIMD3<Float>>)] {
        [
        ("emissiveFactor", \.emissiveFactor),
        ("attenuationColor", \.attenuationColor),
        ("specularColorFactor", \.specularColorFactor),
        ("sheenColorFactor", \.sheenColorFactor),
        ("diffuseTransmissionColorFactor", \.diffuseTransmissionColorFactor),
        ("multiscatterColorFactor", \.multiscatterColorFactor),
        ]
    }

    static var flags: [(String, WritableKeyPath<Uniforms, Int32>)] {
        [
        ("unlit", \.unlit),
        ("volumeScatter", \.volumeScatter),
        ("specularGlossiness", \.specularGlossiness),
        ]
    }

    static var slots: [(String, WritableKeyPath<Uniforms, PBRTextureSlot>)] {
        [
        ("baseColor", \.baseColor),
        ("metallicRoughness", \.metallicRoughness),
        ("normal", \.normal),
        ("occlusion", \.occlusion),
        ("emissive", \.emissive),
        ("transmission", \.transmission),
        ("thickness", \.thickness),
        ("specular", \.specular),
        ("specularColor", \.specularColor),
        ("iridescence", \.iridescence),
        ("iridescenceThickness", \.iridescenceThickness),
        ("anisotropy", \.anisotropy),
        ("sheenColor", \.sheenColor),
        ("sheenRoughness", \.sheenRoughness),
        ("clearcoat", \.clearcoat),
        ("clearcoatRoughness", \.clearcoatRoughness),
        ("clearcoatNormal", \.clearcoatNormal),
        ("diffuseTransmission", \.diffuseTransmission),
        ("diffuseTransmissionColor", \.diffuseTransmissionColor),
        ("retroreflection", \.retroreflection),
        ]
    }

    enum SlotKeys: String, CodingKey {
        case transform, texCoord, enabled
    }

    static let alphaModes: [(String, PBRAlphaMode)] = [("opaque", .opaque), ("mask", .mask), ("blend", .blend)]

    static func encode(_ uniforms: Uniforms, to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(uniforms.baseColorFactor, forKey: Key("baseColorFactor"))
        for (name, keyPath) in vectors3 {
            try container.encode(uniforms[keyPath: keyPath], forKey: Key(name))
        }
        for (name, keyPath) in floats {
            try container.encode(uniforms[keyPath: keyPath], forKey: Key(name))
        }
        for (name, keyPath) in flags {
            try container.encode(uniforms[keyPath: keyPath] != 0, forKey: Key(name))
        }
        if let alphaMode = alphaModes.first(where: { $0.1 == uniforms.alphaMode })?.0 {
            try container.encode(alphaMode, forKey: Key("alphaMode"))
        }
        for (name, keyPath) in slots {
            let slot = uniforms[keyPath: keyPath]
            // Disabled slots with no transform carry nothing.
            guard slot.enabled != 0 || slot.transform != matrix_identity_float3x3 || slot.texCoord != 0 else {
                continue
            }
            var nested = container.nestedContainer(keyedBy: SlotKeys.self, forKey: Key(name))
            let columns = [slot.transform.columns.0, slot.transform.columns.1, slot.transform.columns.2]
            try nested.encode(columns.flatMap { [$0.x, $0.y, $0.z] }, forKey: .transform)
            try nested.encode(slot.texCoord, forKey: .texCoord)
            try nested.encode(slot.enabled != 0, forKey: .enabled)
        }
    }

    static func decode(from decoder: Decoder) throws -> Uniforms {
        var uniforms = Uniforms.defaults()
        let container = try decoder.container(keyedBy: Key.self)
        if let value = try container.decodeIfPresent(SIMD4<Float>.self, forKey: Key("baseColorFactor")) {
            uniforms.baseColorFactor = value
        }
        for (name, keyPath) in vectors3 {
            if let value = try container.decodeIfPresent(SIMD3<Float>.self, forKey: Key(name)) {
                uniforms[keyPath: keyPath] = value
            }
        }
        for (name, keyPath) in floats {
            if let value = try container.decodeIfPresent(Float.self, forKey: Key(name)) {
                uniforms[keyPath: keyPath] = value
            }
        }
        for (name, keyPath) in flags {
            if let value = try container.decodeIfPresent(Bool.self, forKey: Key(name)) {
                uniforms[keyPath: keyPath] = value ? 1 : 0
            }
        }
        if let name = try container.decodeIfPresent(String.self, forKey: Key("alphaMode")), let mode = alphaModes.first(where: { $0.0 == name })?.1 {
            uniforms.alphaMode = mode
        }
        for (name, keyPath) in slots where container.contains(Key(name)) {
            let nested = try container.nestedContainer(keyedBy: SlotKeys.self, forKey: Key(name))
            var slot = uniforms[keyPath: keyPath]
            let values = try nested.decode([Float].self, forKey: .transform)
            guard values.count == 9 else {
                throw DecodingError.dataCorruptedError(forKey: .transform, in: nested, debugDescription: "Texture transform needs 9 values")
            }
            slot.transform = simd_float3x3(columns: ([values[0], values[1], values[2]], [values[3], values[4], values[5]], [values[6], values[7], values[8]]))
            slot.texCoord = try nested.decode(Int32.self, forKey: .texCoord)
            slot.enabled = try nested.decode(Bool.self, forKey: .enabled) ? 1 : 0
            uniforms[keyPath: keyPath] = slot
        }
        return uniforms
    }
}
