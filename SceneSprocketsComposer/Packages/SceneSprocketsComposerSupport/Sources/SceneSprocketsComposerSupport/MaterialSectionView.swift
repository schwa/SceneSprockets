import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd
import SwiftUI

// One inspector section per submesh material of the selected node (#198): kind, presets, colors and the main
// factors. Textures are kept but not edited; channels that use a texture say so instead of showing a color.
struct MaterialSectionView: View {
    @Bindable var model: EditorModel
    var index: Int
    var count: Int
    var isLocked: Bool

    var body: some View {
        if let material = model[material: index] {
            Section(count > 1 ? "Material \(index + 1)" : "Material") {
                if MaterialKind(material) != nil {
                    HStack {
                        Picker("Type", selection: $model[materialKind: index]) {
                            ForEach(MaterialKind.allCases) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        Menu("Presets") {
                            ForEach(MaterialPreset.allCases) { preset in
                                Button(preset.rawValue) {
                                    if let node = model.selectedNode {
                                        try? model.editMaterials(of: node, at: index, actionName: "\(preset.rawValue) Material", [.preset(preset)])
                                    }
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
    }

    @ViewBuilder
    private func blinnPhongFields(_ material: BlinnPhongSceneMaterial) -> some View {
        sourceRow("Diffuse", material.diffuse, \.diffuse)
        sourceRow("Ambient", material.ambient, \.ambient)
        sourceRow("Specular", material.specular, \.specular)
        LabeledContent("Shininess") {
            Slider(value: $model[blinnPhong: index, actionName: "Shininess"].shininess, in: 1 ... 256)
        }
        sourceRow("Emission", material.emission, \.emission)
    }

    @ViewBuilder
    private func sourceRow(_ title: String, _ source: BlinnPhongSceneMaterial.Source, _ keyPath: WritableKeyPath<BlinnPhongSceneMaterial, BlinnPhongSceneMaterial.Source>) -> some View {
        switch source {
        case .color:
            ColorPicker(title, selection: $model[blinnPhong: index, actionName: title][dynamicMember: keyPath].color.linearColor, supportsOpacity: false)

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
                pbrGroup(group, uniforms: uniforms)
            } else {
                DisclosureGroup(group.rawValue) {
                    pbrGroup(group, uniforms: uniforms)
                }
            }
        }
        if uniforms.baseColor.enabled != 0 || uniforms.metallicRoughness.enabled != 0 {
            Text("Texture maps multiply these values.")
                .foregroundStyle(.secondary)
        }
    }

    // `actionName` names the undo step.
    private func uniforms(_ actionName: String) -> Binding<PBRMaterialUniforms> {
        $model[pbrUniforms: index, actionName: actionName]
    }

    @ViewBuilder
    private func pbrGroup(_ group: PBRParameters.Group, uniforms: PBRMaterialUniforms) -> some View {
        switch group {
        case .base:
            ColorPicker("Base Color", selection: self.uniforms("Base Color").baseColorFactor.linearColor)
        case .alpha:
            Picker("Alpha Mode", selection: self.uniforms("Alpha Mode").alphaMode) {
                Text("Opaque").tag(PBRAlphaMode.opaque)
                Text("Mask").tag(PBRAlphaMode.mask)
                Text("Blend").tag(PBRAlphaMode.blend)
            }
            Toggle("Double Sided", isOn: $model[pbrDoubleSided: index])
        case .transmission:
            Toggle("Absorbs Light", isOn: self.uniforms("Attenuation Distance").absorbsLight)
                .help("Off: the volume does not absorb (attenuation distance is infinite)")
            if uniforms.attenuationDistance.isFinite {
                scalarRow(PBRParameters.Scalar(name: "Attenuation Distance", keyPath: \.attenuationDistance, range: 0.01 ... 100, group: .transmission), uniforms: uniforms)
            }
        default:
            EmptyView()
        }
        ForEach(PBRParameters.scalars.filter { $0.group == group }, id: \.name) { parameter in
            scalarRow(parameter, uniforms: uniforms)
        }
        ForEach(PBRParameters.colors.filter { $0.group == group }, id: \.name) { parameter in
            ColorPicker(parameter.name, selection: self.uniforms(parameter.name)[dynamicMember: parameter.keyPath].linearColor, supportsOpacity: false)
        }
        ForEach(PBRParameters.toggles.filter { $0.group == group }, id: \.name) { parameter in
            Toggle(parameter.name, isOn: self.uniforms(parameter.name)[dynamicMember: parameter.keyPath].isOn)
        }
    }

    @ViewBuilder
    private func scalarRow(_ parameter: PBRParameters.Scalar, uniforms: PBRMaterialUniforms) -> some View {
        let scale: Float = parameter.isAngle ? 180 / .pi : 1
        LabeledContent(parameter.name) {
            HStack {
                Slider(value: self.uniforms(parameter.name)[dynamicMember: parameter.keyPath], in: parameter.range)
                Text((uniforms[keyPath: parameter.keyPath] * scale).formatted(.number.precision(.fractionLength(2))))
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
    }
}

#Preview {
    let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
    model.addShape(.box(), label: "Box")
    return Form {
        MaterialSectionView(model: model, index: 0, count: 1, isLocked: false)
    }
    .formStyle(.grouped)
}
