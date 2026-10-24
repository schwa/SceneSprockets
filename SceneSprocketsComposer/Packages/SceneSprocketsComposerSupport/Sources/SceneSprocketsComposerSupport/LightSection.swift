import SceneSprockets
import simd
import SwiftFields
import SwiftUI

// The inspector's Light section (#209): every Light field, through EditorModel.setLight so edits are undoable.
struct LightSection: View {
    var model: EditorModel
    var node: SceneGraph.Node
    var light: Light
    var isLocked: Bool

    var body: some View {
        Section("Light") {
            Picker("Type", selection: binding(\.type)) {
                Text("Directional").tag(Light.LightType.directional)
                Text("Point").tag(Light.LightType.point)
                Text("Spot").tag(Light.LightType.spot)
            }
            ColorPicker("Color", selection: colorBinding, supportsOpacity: false)
            LabeledContent("Intensity") {
                HStack {
                    Slider(value: binding(\.intensity), in: 0 ... 20)
                    Text(light.intensity.formatted(.number.precision(.fractionLength(2))))
                        .monospacedDigit()
                        .frame(minWidth: 44, alignment: .trailing)
                }
            }
            if light.type != .directional {
                Toggle("Limited Range", isOn: Binding(get: { light.range.isFinite }, set: { isLimited in
                    edit { $0.range = isLimited ? 10 : .infinity }
                }))
                .help("Off: the light reaches any distance")
                if light.range.isFinite {
                    TextField("Range", value: binding(\.range), format: .number)
                }
            }
            if light.type == .spot {
                LabeledContent("Inner Cone") {
                    AngleEditor(angle: angleBinding(\.innerConeAngle), limit: .degrees(0) ... .degrees(90))
                }
                LabeledContent("Outer Cone") {
                    AngleEditor(angle: angleBinding(\.outerConeAngle), limit: .degrees(0) ... .degrees(90))
                }
            }
        }
        .disabled(isLocked)
    }

    private func edit(_ change: (inout Light) -> Void) {
        var updated = light
        change(&updated)
        model.setLight(updated, of: node)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<Light, Value>) -> Binding<Value> {
        Binding(get: { light[keyPath: keyPath] }, set: { value in edit { $0[keyPath: keyPath] = value } })
    }

    private func angleBinding(_ keyPath: WritableKeyPath<Light, Float>) -> Binding<Angle> {
        Binding(get: { .radians(Double(light[keyPath: keyPath])) }, set: { angle in
            model.setLight(LightEditing.settingCone(keyPath, to: Float(angle.radians), of: light), of: node)
        })
    }

    // Linear RGB, as the material colors.
    private var colorBinding: Binding<Color> {
        Binding(get: {
            Color(.sRGBLinear, red: Double(light.color.x), green: Double(light.color.y), blue: Double(light.color.z))
        }, set: { newColor in
            let resolved = newColor.resolve(in: EnvironmentValues())
            edit { $0.color = [resolved.linearRed, resolved.linearGreen, resolved.linearBlue] }
        })
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
