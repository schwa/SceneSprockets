import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd
import SwiftUI

// One inspector section per submesh material (#198): kind, presets, colors and the main factors. Textures are kept
// but not edited; channels that use a texture say so instead of showing a color.
struct MaterialSection: View {
    var model: EditorModel
    var node: SceneGraph.Node
    var index: Int
    var count: Int
    var isLocked: Bool

    var body: some View {
        let material = model.materials(of: node)[index]
        Section(count > 1 ? "Material \(index + 1)" : "Material") {
            if let kind = MaterialKind(material) {
                HStack {
                    Picker("Type", selection: Binding(get: { kind }, set: { newKind in
                        replace(with: { try EditorModel.converted(material, to: newKind, device: systemDefaultDevice()) }, actionName: "Material Type")
                    })) {
                        ForEach(MaterialKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    Menu("Presets") {
                        ForEach(MaterialPreset.allCases) { preset in
                            Button(preset.rawValue) {
                                replace(with: { try preset.material(color: EditorModel.baseColor(of: material), device: systemDefaultDevice()) }, actionName: "\(preset.rawValue) Material")
                            }
                        }
                    }
                    .fixedSize()
                }
                switch material {
                case let blinnPhong as BlinnPhongSceneMaterial:
                    blinnPhongFields(blinnPhong)
                case let pbr as PBRSceneMaterial:
                    pbrFields(pbr)
                default:
                    EmptyView()
                }
            } else {
                LabeledContent("Type", value: String(describing: type(of: material)))
                Text("This material type cannot be edited here.")
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(isLocked)
    }

    @ViewBuilder
    private func blinnPhongFields(_ material: BlinnPhongSceneMaterial) -> some View {
        sourceRow("Diffuse", material.diffuse) { material, color in material.diffuse = .color(color) }
        sourceRow("Ambient", material.ambient) { material, color in material.ambient = .color(color) }
        sourceRow("Specular", material.specular) { material, color in material.specular = .color(color) }
        LabeledContent("Shininess") {
            Slider(value: Binding(get: { material.shininess }, set: { value in
                editBlinnPhong("Shininess") { $0.shininess = value }
            }), in: 1 ... 256)
        }
        sourceRow("Emission", material.emission) { material, color in material.emission = .color(color) }
    }

    @ViewBuilder
    private func sourceRow(_ title: String, _ source: BlinnPhongSceneMaterial.Source, set: @escaping (inout BlinnPhongSceneMaterial, SIMD3<Float>) -> Void) -> some View {
        switch source {
        case let .color(color):
            ColorPicker(title, selection: colorBinding(color) { newColor in
                editBlinnPhong(title) { set(&$0, newColor) }
            }, supportsOpacity: false)

        case .texture:
            LabeledContent(title, value: "Texture")
        }
    }

    @ViewBuilder
    private func pbrFields(_ material: PBRSceneMaterial) -> some View {
        let uniforms = material.pbrMaterial.uniforms
        let baseColor = uniforms.baseColorFactor
        ColorPicker("Base Color", selection: colorBinding([baseColor.x, baseColor.y, baseColor.z]) { color in
            editPBR(material, "Base Color") { $0.baseColorFactor = SIMD4(color, $0.baseColorFactor.w) }
        }, supportsOpacity: false)
        LabeledContent("Metallic") {
            Slider(value: Binding(get: { uniforms.metallicFactor }, set: { value in
                editPBR(material, "Metallic") { $0.metallicFactor = value }
            }), in: 0 ... 1)
        }
        LabeledContent("Roughness") {
            Slider(value: Binding(get: { uniforms.roughnessFactor }, set: { value in
                editPBR(material, "Roughness") { $0.roughnessFactor = value }
            }), in: 0 ... 1)
        }
        ColorPicker("Emissive", selection: colorBinding(uniforms.emissiveFactor) { color in
            editPBR(material, "Emissive") { $0.emissiveFactor = color }
        }, supportsOpacity: false)
        if uniforms.baseColor.enabled != 0 || uniforms.metallicRoughness.enabled != 0 {
            Text("Texture maps multiply these values.")
                .foregroundStyle(.secondary)
        }
    }

    private func editBlinnPhong(_ actionName: String, _ change: (inout BlinnPhongSceneMaterial) -> Void) {
        guard var material = model.materials(of: node)[index] as? BlinnPhongSceneMaterial else {
            return
        }
        change(&material)
        model.setMaterial(material, at: index, of: node, actionName: actionName)
    }

    private func editPBR(_ material: PBRSceneMaterial, _ actionName: String, _ change: (inout PBRMaterialUniforms) -> Void) {
        replace(with: { try EditorModel.editedPBR(material, device: systemDefaultDevice(), change) }, actionName: actionName)
    }

    private func replace(with make: () throws -> any SceneSprockets.Material, actionName: String) {
        guard let material = try? make() else {
            return
        }
        model.setMaterial(material, at: index, of: node, actionName: actionName)
    }

    // Linear RGB in the scene, as SceneInspectorView's background color.
    private func colorBinding(_ color: SIMD3<Float>, set: @escaping (SIMD3<Float>) -> Void) -> Binding<Color> {
        Binding(get: {
            Color(.sRGBLinear, red: Double(color.x), green: Double(color.y), blue: Double(color.z))
        }, set: { newColor in
            let resolved = newColor.resolve(in: EnvironmentValues())
            set([resolved.linearRed, resolved.linearGreen, resolved.linearBlue])
        })
    }
}
