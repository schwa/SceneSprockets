import SceneSprockets
import simd
import SwiftFields
import SwiftUI

// The inspector's Light section (#209): every Light field. `light` writes through EditorModel.setLight, so edits are
// undoable.
struct LightSectionView: View {
    @Binding var light: Light
    var isLocked: Bool

    var body: some View {
        Section("Light") {
            Picker("Type", selection: $light.type) {
                Text("Directional").tag(Light.LightType.directional)
                Text("Point").tag(Light.LightType.point)
                Text("Spot").tag(Light.LightType.spot)
            }
            ColorPicker("Color", selection: $light.color.linearColor, supportsOpacity: false)
            LabeledContent("Intensity") {
                HStack {
                    Slider(value: $light.intensity, in: 0 ... 20)
                    Text(light.intensity.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            if light.type != .directional {
                Toggle("Limited Range", isOn: $light.isRangeLimited)
                    .help("Off: the light reaches any distance")
                if light.range.isFinite {
                    TextField("Range", value: $light.range, format: .number)
                }
            }
            if light.type == .spot {
                LabeledContent("Inner Cone") {
                    AngleEditor(angle: $light.innerCone, limit: .degrees(0) ... .degrees(90))
                }
                LabeledContent("Outer Cone") {
                    AngleEditor(angle: $light.outerCone, limit: .degrees(0) ... .degrees(90))
                }
            }
        }
        .disabled(isLocked)
    }
}

enum LightEditing {
    // Sets one cone angle and keeps inner at or below outer by moving the other one along.
    static func settingCone(_ keyPath: WritableKeyPath<Light, Float>, to angle: Float, of light: Light) -> Light {
        var light = light
        light[keyPath: keyPath] = max(angle, 0)
        if keyPath == \Light.innerConeAngle, light.innerConeAngle > light.outerConeAngle {
            light.outerConeAngle = light.innerConeAngle
        } else if keyPath == \Light.outerConeAngle, light.outerConeAngle < light.innerConeAngle {
            light.innerConeAngle = light.outerConeAngle
        }
        return light
    }
}

#Preview("Spot") {
    @Previewable @State var light = Light(type: .spot, color: [1, 0.9, 0.8], intensity: 4)
    Form {
        LightSectionView(light: $light, isLocked: false)
    }
    .formStyle(.grouped)
}

#Preview("Locked") {
    @Previewable @State var light = Light(type: .point, color: [1, 1, 1], intensity: 1)
    Form {
        LightSectionView(light: $light, isLocked: true)
    }
    .formStyle(.grouped)
}
