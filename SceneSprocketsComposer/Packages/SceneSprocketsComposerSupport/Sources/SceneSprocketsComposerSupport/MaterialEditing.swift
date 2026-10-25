import Metal
import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd

// Material editing for the inspector (#198). Edits replace a mesh node's material at one submesh index, so they undo
// cleanly and never change materials shared with other nodes.
enum MaterialKind: String, CaseIterable, Identifiable {
    case blinnPhong = "Blinn-Phong"
    case pbr = "PBR"

    var id: Self { self }

    init?(_ material: any SceneSprockets.Material) {
        switch material {
        case is BlinnPhongSceneMaterial: self = .blinnPhong
        case is PBRSceneMaterial: self = .pbr
        default: return nil
        }
    }
}

enum MaterialPreset: String, CaseIterable, Identifiable {
    case plastic = "Plastic"
    case metal = "Metal"
    case rubber = "Rubber"
    case glass = "Glass"

    var id: Self { self }

    // Keeps the current color where it makes sense.
    func material(color: SIMD3<Float>, device: MTLDevice) throws -> PBRSceneMaterial {
        var uniforms = PBRMaterialUniforms.defaults(baseColor: SIMD4(color, 1))
        switch self {
        case .plastic:
            uniforms.metallicFactor = 0
            uniforms.roughnessFactor = 0.35
        case .metal:
            uniforms.metallicFactor = 1
            uniforms.roughnessFactor = 0.25
        case .rubber:
            uniforms.metallicFactor = 0
            uniforms.roughnessFactor = 0.9
        case .glass:
            uniforms.baseColorFactor = [1, 1, 1, 1]
            uniforms.metallicFactor = 0
            uniforms.roughnessFactor = 0.05
            uniforms.transmissionFactor = 1
        }
        return PBRSceneMaterial(try PBRMaterial(uniforms: uniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device))
    }
}

extension EditorModel {
    // One per submesh; empty for nodes without a mesh. Observed, so views refresh after edits.
    func materials(of node: SceneGraph.Node) -> [any SceneSprockets.Material] {
        observe(.content)
        guard case let .mesh(_, materials, _, _) = node.content else {
            return []
        }
        return materials
    }

    func setMaterial(_ material: any SceneSprockets.Material, at index: Int, of node: SceneGraph.Node, actionName: String = "Material") {
        guard case let .mesh(mesh, materials, castsShadow, receivesShadow) = node.content, materials.indices.contains(index) else {
            return
        }
        var updated = materials
        updated[index] = material
        let previous = node.content
        let content = SceneGraph.Node.Content.mesh(mesh, materials: updated, castsShadow: castsShadow, receivesShadow: receivesShadow)
        perform(actionName, affecting: .content, { _ in node.content = content }, revert: { _ in node.content = previous })
    }

    // The material's main color, for conversions and presets.
    static func baseColor(of material: any SceneSprockets.Material) -> SIMD3<Float> {
        switch material {
        case let material as BlinnPhongSceneMaterial:
            if case let .color(color) = material.diffuse {
                return color
            }
            return [0.8, 0.8, 0.8]
        case let material as PBRSceneMaterial:
            let color = material.pbrMaterial.uniforms.baseColorFactor
            return [color.x, color.y, color.z]
        default:
            return [0.8, 0.8, 0.8]
        }
    }

    // The same color as the other kind. Textures are not carried over.
    static func converted(_ material: any SceneSprockets.Material, to kind: MaterialKind, device: MTLDevice) throws -> any SceneSprockets.Material {
        let color = baseColor(of: material)
        switch kind {
        case .blinnPhong:
            return BlinnPhongSceneMaterial(ambient: .color(color * 0.1), diffuse: .color(color), specular: .color(0.5), shininess: 32)
        case .pbr:
            return try PBRSceneMaterial(device: device, baseColor: SIMD4(color, 1), metallic: 0, roughness: 0.5)
        }
    }

    // A copy with changed uniforms that keeps the textures and render state, so the original stays untouched.
    static func editedPBR(_ material: PBRSceneMaterial, device: MTLDevice, doubleSided: Bool? = nil, _ change: (inout PBRMaterialUniforms) -> Void = { _ in }) throws -> PBRSceneMaterial {
        let original = material.pbrMaterial
        var uniforms = original.uniforms
        change(&uniforms)
        let copy = try PBRMaterial(name: original.name, uniforms: uniforms, doubleSided: doubleSided ?? original.doubleSided, textureBindings: original.textureBindings, device: device)
        copy.textureTransforms = original.textureTransforms
        copy.renderState = original.renderState
        return PBRSceneMaterial(copy)
    }
}
