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
                                        let actionName = "\(preset.rawValue) Material"
                                        model.reportingMaterialEditErrors(actionName) {
                                            try model.editMaterials(of: node, at: index, actionName: actionName, [.preset(preset)])
                                        }
                                    }
                                }
                            }
                        }
                        .fixedSize()
                    }
                    switch material {
                    case let blinnPhong as BlinnPhongSceneMaterial:
                        BlinnPhongFieldsView(model: model, index: index, material: blinnPhong)
                    case let pbr as PBRSceneMaterial:
                        PBRFieldsView(model: model, index: index, uniforms: pbr.pbrMaterial.uniforms)
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
}

// Each row is its own view with only the values it shows, so editing one value updates that row, not the whole
// section (#488).
private struct BlinnPhongFieldsView: View {
    @Bindable var model: EditorModel
    let index: Int
    let material: BlinnPhongSceneMaterial

    var body: some View {
        BlinnPhongSourceRow(model: model, index: index, title: "Diffuse", isColor: material.diffuse.isColor, keyPath: \.diffuse)
        BlinnPhongSourceRow(model: model, index: index, title: "Ambient", isColor: material.ambient.isColor, keyPath: \.ambient)
        BlinnPhongSourceRow(model: model, index: index, title: "Specular", isColor: material.specular.isColor, keyPath: \.specular)
        LabeledContent("Shininess") {
            Slider(value: $model[blinnPhong: index, actionName: "Shininess"].shininess, in: 1 ... 256)
        }
        BlinnPhongSourceRow(model: model, index: index, title: "Emission", isColor: material.emission.isColor, keyPath: \.emission)
    }
}

private struct BlinnPhongSourceRow: View {
    @Bindable var model: EditorModel
    let index: Int
    let title: String
    let isColor: Bool
    let keyPath: WritableKeyPath<BlinnPhongSceneMaterial, BlinnPhongSceneMaterial.Source>

    var body: some View {
        if isColor {
            ColorPicker(title, selection: $model[blinnPhong: index, actionName: title][dynamicMember: keyPath].color.linearColor, supportsOpacity: false)
        } else {
            LabeledContent(title, value: "Texture")
        }
    }
}

extension BlinnPhongSceneMaterial.Source {
    var isColor: Bool {
        if case .color = self { true } else { false }
    }
}

// Every PBR value (#208): Base open, the other groups collapsed. Values that are not plain floats, colors or flags
// (base color with alpha, alpha mode, double-sided, attenuation distance) are handled here; the rest come from
// PBRParameters.
private struct PBRFieldsView: View {
    let model: EditorModel
    let index: Int
    let uniforms: PBRMaterialUniforms

    var body: some View {
        ForEach(PBRParameters.Group.allCases) { group in
            if group.isExpandedByDefault {
                PBRGroupView(model: model, index: index, group: group, uniforms: uniforms)
            } else {
                DisclosureGroup(group.rawValue) {
                    PBRGroupView(model: model, index: index, group: group, uniforms: uniforms)
                }
            }
        }
        if uniforms.baseColor.enabled != 0 || uniforms.metallicRoughness.enabled != 0 {
            Text("Texture maps multiply these values.")
                .foregroundStyle(.secondary)
        }
    }
}

private struct PBRGroupView: View {
    @Bindable var model: EditorModel
    let index: Int
    let group: PBRParameters.Group
    let uniforms: PBRMaterialUniforms

    // `actionName` names the undo step.
    private func binding(_ actionName: String) -> Binding<PBRMaterialUniforms> {
        $model[pbrUniforms: index, actionName: actionName]
    }

    var body: some View {
        switch group {
        case .base:
            ColorPicker("Base Color", selection: binding("Base Color").baseColorFactor.linearColor)
        case .alpha:
            Picker("Alpha Mode", selection: binding("Alpha Mode").alphaMode) {
                Text("Opaque").tag(PBRAlphaMode.opaque)
                Text("Mask").tag(PBRAlphaMode.mask)
                Text("Blend").tag(PBRAlphaMode.blend)
            }
            Toggle("Double Sided", isOn: $model[pbrDoubleSided: index])
        case .transmission:
            Toggle("Absorbs Light", isOn: binding("Attenuation Distance").absorbsLight)
                .help("Off: the volume does not absorb (attenuation distance is infinite)")
            if uniforms.attenuationDistance.isFinite {
                PBRScalarRow(model: model, index: index, parameter: Self.attenuationDistance, value: uniforms.attenuationDistance)
            }
        default:
            EmptyView()
        }
        ForEach(PBRParameters.scalars(in: group), id: \.name) { parameter in
            PBRScalarRow(model: model, index: index, parameter: parameter, value: uniforms[keyPath: parameter.keyPath])
        }
        ForEach(PBRParameters.colors(in: group), id: \.name) { parameter in
            ColorPicker(parameter.name, selection: binding(parameter.name)[dynamicMember: parameter.keyPath].linearColor, supportsOpacity: false)
        }
        ForEach(PBRParameters.toggles(in: group), id: \.name) { parameter in
            Toggle(parameter.name, isOn: binding(parameter.name)[dynamicMember: parameter.keyPath].isOn)
        }
    }

    private static let attenuationDistance = PBRParameters.Scalar(name: "Attenuation Distance", keyPath: \.attenuationDistance, range: 0.01 ... 100, group: .transmission)
}

private struct PBRScalarRow: View {
    @Bindable var model: EditorModel
    let index: Int
    let parameter: PBRParameters.Scalar
    let value: Float

    var body: some View {
        LabeledContent(parameter.name) {
            HStack {
                Slider(value: $model[pbrUniforms: index, actionName: parameter.name][dynamicMember: parameter.keyPath], in: parameter.range)
                Text((value * (parameter.isAngle ? 180 / .pi : 1)).formatted(.number.precision(.fractionLength(2))))
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
