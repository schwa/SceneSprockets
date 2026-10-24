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

    // Every PBR value (#208): Base open, the other groups collapsed. Values that are not plain floats, colors or flags
    // (base color with alpha, alpha mode, double-sided, attenuation distance) are handled here; the rest come from
    // PBRParameters.
    @ViewBuilder
    private func pbrFields(_ material: PBRSceneMaterial) -> some View {
        let uniforms = material.pbrMaterial.uniforms
        ForEach(PBRParameters.Group.allCases) { group in
            if group.isExpandedByDefault {
                pbrGroup(group, material: material, uniforms: uniforms)
            } else {
                DisclosureGroup(group.rawValue) {
                    pbrGroup(group, material: material, uniforms: uniforms)
                }
            }
        }
        if uniforms.baseColor.enabled != 0 || uniforms.metallicRoughness.enabled != 0 {
            Text("Texture maps multiply these values.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func pbrGroup(_ group: PBRParameters.Group, material: PBRSceneMaterial, uniforms: PBRMaterialUniforms) -> some View {
        switch group {
        case .base:
            let baseColor = uniforms.baseColorFactor
            ColorPicker("Base Color", selection: colorBinding(baseColor) { color in
                editPBR(material, "Base Color") { $0.baseColorFactor = color }
            })
        case .alpha:
            Picker("Alpha Mode", selection: Binding(get: { uniforms.alphaMode }, set: { mode in
                editPBR(material, "Alpha Mode") { $0.alphaMode = mode }
            })) {
                Text("Opaque").tag(PBRAlphaMode.opaque)
                Text("Mask").tag(PBRAlphaMode.mask)
                Text("Blend").tag(PBRAlphaMode.blend)
            }
            Toggle("Double Sided", isOn: Binding(get: { material.pbrMaterial.doubleSided }, set: { value in
                replace(with: { try EditorModel.editedPBR(material, device: systemDefaultDevice(), doubleSided: value) }, actionName: "Double Sided")
            }))
        case .transmission:
            Toggle("Absorbs Light", isOn: Binding(get: { uniforms.attenuationDistance.isFinite }, set: { absorbs in
                editPBR(material, "Attenuation Distance") { $0.attenuationDistance = absorbs ? 1 : .infinity }
            }))
            .help("Off: the volume does not absorb (attenuation distance is infinite)")
            if uniforms.attenuationDistance.isFinite {
                scalarRow(PBRParameters.Scalar(name: "Attenuation Distance", keyPath: \.attenuationDistance, range: 0.01 ... 100, group: .transmission), material: material, uniforms: uniforms)
            }
        default:
            EmptyView()
        }
        ForEach(PBRParameters.scalars.filter { $0.group == group }, id: \.name) { parameter in
            scalarRow(parameter, material: material, uniforms: uniforms)
        }
        ForEach(PBRParameters.colors.filter { $0.group == group }, id: \.name) { parameter in
            ColorPicker(parameter.name, selection: colorBinding(uniforms[keyPath: parameter.keyPath]) { color in
                editPBR(material, parameter.name) { $0[keyPath: parameter.keyPath] = color }
            }, supportsOpacity: false)
        }
        ForEach(PBRParameters.toggles.filter { $0.group == group }, id: \.name) { parameter in
            Toggle(parameter.name, isOn: Binding(get: { uniforms[keyPath: parameter.keyPath] != 0 }, set: { value in
                editPBR(material, parameter.name) { $0[keyPath: parameter.keyPath] = value ? 1 : 0 }
            }))
        }
    }

    private func scalarRow(_ parameter: PBRParameters.Scalar, material: PBRSceneMaterial, uniforms: PBRMaterialUniforms) -> some View {
        let scale: Float = parameter.isAngle ? 180 / .pi : 1
        let value = uniforms[keyPath: parameter.keyPath]
        return LabeledContent(parameter.name) {
            HStack {
                Slider(value: Binding(get: { value.clamped(to: parameter.range) }, set: { newValue in
                    editPBR(material, parameter.name) { $0[keyPath: parameter.keyPath] = newValue }
                }), in: parameter.range)
                Text((value * scale).formatted(.number.precision(.fractionLength(2))))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
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

    // With alpha; RGB is linear, alpha is not.
    private func colorBinding(_ color: SIMD4<Float>, set: @escaping (SIMD4<Float>) -> Void) -> Binding<Color> {
        Binding(get: {
            Color(.sRGBLinear, red: Double(color.x), green: Double(color.y), blue: Double(color.z), opacity: Double(color.w))
        }, set: { newColor in
            let resolved = newColor.resolve(in: EnvironmentValues())
            set([resolved.linearRed, resolved.linearGreen, resolved.linearBlue, resolved.opacity])
        })
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
