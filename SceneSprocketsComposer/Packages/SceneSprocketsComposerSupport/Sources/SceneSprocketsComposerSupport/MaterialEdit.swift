import Metal
import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd

// One change to a material, as a value (#239). The inspector, multiple selection and the assistant describe edits
// with these; MaterialEdit.applying turns a list into a new material.
@MainActor
enum MaterialEdit {
    // Converts with the same color; no change when it is already that kind.
    case kind(MaterialKind)
    // Replaces with a PBR preset in the current base color.
    case preset(MaterialPreset)
    // Blinn-Phong diffuse or PBR base color (alpha kept). A textured diffuse is left alone.
    case baseColor(SIMD3<Float>)
    // PBR only.
    case uniforms((inout PBRMaterialUniforms) -> Void)
    // PBR only.
    case doubleSided(Bool)
    // Blinn-Phong only.
    case blinnPhong((inout BlinnPhongSceneMaterial) -> Void)

    // A material being edited. PBR uniform changes pile up and the material is rebuilt once, at the end.
    @MainActor
    private enum Draft {
        case blinnPhong(BlinnPhongSceneMaterial)
        case pbr(PBRSceneMaterial, uniforms: PBRMaterialUniforms, doubleSided: Bool)
        case other

        init(_ material: any SceneSprockets.Material) {
            switch material {
            case let material as BlinnPhongSceneMaterial:
                self = .blinnPhong(material)
            case let material as PBRSceneMaterial:
                self = .pbr(material, uniforms: material.pbrMaterial.uniforms, doubleSided: material.pbrMaterial.doubleSided)
            default:
                self = .other
            }
        }

        var baseColor: SIMD3<Float> {
            switch self {
            case let .blinnPhong(material):
                EditorModel.baseColor(of: material)
            case let .pbr(_, uniforms, _):
                [uniforms.baseColorFactor.x, uniforms.baseColorFactor.y, uniforms.baseColorFactor.z]
            case .other:
                [0.8, 0.8, 0.8]
            }
        }
    }

    // The edited material, or nil when no edit applied. The original is never changed; textures and render state
    // are kept by PBR edits.
    static func applying(_ edits: [MaterialEdit], to material: any SceneSprockets.Material, device: MTLDevice) throws -> (any SceneSprockets.Material)? {
        var draft = Draft(material)
        var changed = false
        for edit in edits {
            switch (edit, draft) {
            case (.kind(.pbr), .blinnPhong), (.kind(.blinnPhong), .pbr):
                guard case let .kind(kind) = edit else {
                    continue
                }
                draft = Draft(try EditorModel.converted(color: draft.baseColor, to: kind, device: device))
            case let (.preset(preset), _):
                draft = Draft(try preset.material(color: draft.baseColor, device: device))
            case let (.baseColor(color), .blinnPhong(material)):
                guard case .color = material.diffuse else {
                    continue
                }
                var edited = material
                edited.diffuse = .color(color)
                draft = .blinnPhong(edited)
            case let (.baseColor(color), .pbr(base, uniforms, doubleSided)):
                var edited = uniforms
                edited.baseColorFactor = SIMD4(color, uniforms.baseColorFactor.w)
                draft = .pbr(base, uniforms: edited, doubleSided: doubleSided)
            case let (.uniforms(change), .pbr(base, uniforms, doubleSided)):
                var edited = uniforms
                change(&edited)
                draft = .pbr(base, uniforms: edited, doubleSided: doubleSided)
            case let (.doubleSided(doubleSided), .pbr(base, uniforms, _)):
                draft = .pbr(base, uniforms: uniforms, doubleSided: doubleSided)
            case let (.blinnPhong(change), .blinnPhong(material)):
                var edited = material
                change(&edited)
                draft = .blinnPhong(edited)
            default:
                continue
            }
            changed = true
        }
        return changed ? try Self.material(of: draft, device: device) : nil
    }

    private static func material(of draft: Draft, device: MTLDevice) throws -> (any SceneSprockets.Material)? {
        switch draft {
        case let .blinnPhong(material):
            return material
        case let .pbr(base, uniforms, doubleSided):
            return try EditorModel.editedPBR(base, device: device, doubleSided: doubleSided) { $0 = uniforms }
        case .other:
            return nil
        }
    }
}
