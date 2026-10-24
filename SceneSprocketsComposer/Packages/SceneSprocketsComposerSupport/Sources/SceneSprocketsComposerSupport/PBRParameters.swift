import MetalSprocketsPBR
import simd

// Every editable PBRMaterialUniforms value (#208), as data so the inspector and tests share one list. Ranges follow
// the glTF extension specs, capped where the spec is open-ended. Internal values (hasTangents, hasNormals,
// isPointOrLine, texture slots) are left out. Main actor: key paths are not Sendable.
@MainActor
enum PBRParameters {
    enum Group: String, CaseIterable, Identifiable {
        case base = "Base"
        case alpha = "Alpha"
        case maps = "Maps"
        case transmission = "Transmission and Volume"
        case diffuseTransmission = "Diffuse Transmission"
        case specular = "Specular"
        case clearcoat = "Clearcoat"
        case sheen = "Sheen"
        case iridescence = "Iridescence"
        case anisotropy = "Anisotropy"
        case other = "Other"

        var id: Self { self }

        // Shown open; the rest start collapsed.
        var isExpandedByDefault: Bool {
            self == .base
        }
    }

    struct Scalar {
        var name: String
        var keyPath: WritableKeyPath<PBRMaterialUniforms, Float>
        var range: ClosedRange<Float>
        var group: Group
        // Shown and edited in degrees, stored in radians.
        var isAngle = false
    }

    struct Color {
        var name: String
        var keyPath: WritableKeyPath<PBRMaterialUniforms, SIMD3<Float>>
        var group: Group
    }

    struct Toggle {
        var name: String
        var keyPath: WritableKeyPath<PBRMaterialUniforms, Int32>
        var group: Group
    }

    static let scalars: [Scalar] = [
        Scalar(name: "Metallic", keyPath: \.metallicFactor, range: 0 ... 1, group: .base),
        Scalar(name: "Roughness", keyPath: \.roughnessFactor, range: 0 ... 1, group: .base),
        Scalar(name: "Emissive Strength", keyPath: \.emissiveStrength, range: 0 ... 100, group: .base),
        Scalar(name: "Alpha Cutoff", keyPath: \.alphaCutoff, range: 0 ... 1, group: .alpha),
        Scalar(name: "Normal Scale", keyPath: \.normalScale, range: 0 ... 2, group: .maps),
        Scalar(name: "Occlusion Strength", keyPath: \.occlusionStrength, range: 0 ... 1, group: .maps),
        Scalar(name: "Transmission", keyPath: \.transmissionFactor, range: 0 ... 1, group: .transmission),
        Scalar(name: "Thickness", keyPath: \.thicknessFactor, range: 0 ... 10, group: .transmission),
        Scalar(name: "IOR", keyPath: \.ior, range: 1 ... 3, group: .transmission),
        Scalar(name: "Dispersion", keyPath: \.dispersion, range: 0 ... 1, group: .transmission),
        Scalar(name: "Diffuse Transmission", keyPath: \.diffuseTransmissionFactor, range: 0 ... 1, group: .diffuseTransmission),
        Scalar(name: "Specular", keyPath: \.specularFactor, range: 0 ... 1, group: .specular),
        Scalar(name: "Clearcoat", keyPath: \.clearcoatFactor, range: 0 ... 1, group: .clearcoat),
        Scalar(name: "Clearcoat Roughness", keyPath: \.clearcoatRoughnessFactor, range: 0 ... 1, group: .clearcoat),
        Scalar(name: "Clearcoat Normal Scale", keyPath: \.clearcoatNormalScale, range: 0 ... 2, group: .clearcoat),
        Scalar(name: "Sheen Roughness", keyPath: \.sheenRoughnessFactor, range: 0 ... 1, group: .sheen),
        Scalar(name: "Iridescence", keyPath: \.iridescenceFactor, range: 0 ... 1, group: .iridescence),
        Scalar(name: "Iridescence IOR", keyPath: \.iridescenceIor, range: 1 ... 3, group: .iridescence),
        Scalar(name: "Thickness Minimum (nm)", keyPath: \.iridescenceThicknessMinimum, range: 0 ... 1_000, group: .iridescence),
        Scalar(name: "Thickness Maximum (nm)", keyPath: \.iridescenceThicknessMaximum, range: 0 ... 1_000, group: .iridescence),
        Scalar(name: "Anisotropy", keyPath: \.anisotropyStrength, range: 0 ... 1, group: .anisotropy),
        Scalar(name: "Anisotropy Rotation", keyPath: \.anisotropyRotation, range: -.pi ... .pi, group: .anisotropy, isAngle: true),
        Scalar(name: "Retroreflection", keyPath: \.retroreflectionFactor, range: 0 ... 1, group: .other),
        Scalar(name: "Glossiness", keyPath: \.glossinessFactor, range: 0 ... 1, group: .other),
    ]

    static let colors: [Color] = [
        Color(name: "Emissive", keyPath: \.emissiveFactor, group: .base),
        Color(name: "Attenuation Color", keyPath: \.attenuationColor, group: .transmission),
        Color(name: "Multiscatter Color", keyPath: \.multiscatterColorFactor, group: .transmission),
        Color(name: "Diffuse Transmission Color", keyPath: \.diffuseTransmissionColorFactor, group: .diffuseTransmission),
        Color(name: "Specular Color", keyPath: \.specularColorFactor, group: .specular),
        Color(name: "Sheen Color", keyPath: \.sheenColorFactor, group: .sheen),
    ]

    static let toggles: [Toggle] = [
        Toggle(name: "Unlit", keyPath: \.unlit, group: .base),
        Toggle(name: "Volume Scattering", keyPath: \.volumeScatter, group: .transmission),
        Toggle(name: "Specular-Glossiness", keyPath: \.specularGlossiness, group: .other),
    ]
}
