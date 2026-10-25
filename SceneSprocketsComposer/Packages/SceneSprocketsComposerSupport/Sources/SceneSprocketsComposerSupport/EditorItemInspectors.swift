import simd
import SwiftUI

// Inspectors for the Default Camera and Default Lighting rows (#207). These settings moved here from the Render tab.
struct DefaultCameraInspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Form {
            Section("Default Camera") {
                Text("The editor's camera. It overrides any camera node for the preview, and is saved with the document's editor state.")
                    .foregroundStyle(.secondary)
                LabeledContent("Field of View") {
                    HStack {
                        Slider(value: $model.renderSettings.fieldOfView, in: 10 ... 120)
                        Text("\(Int(model.renderSettings.fieldOfView.rounded()))\u{00B0}")
                            .monospacedDigit()
                            .frame(minWidth: 36, alignment: .trailing)
                    }
                }
                TextField("Near Clip", value: $model.renderSettings.nearClip, format: .number)
                TextField("Far Clip", value: $model.renderSettings.farClip, format: .number)
            }
            Section("Position") {
                LabeledContent("Position", value: Self.format(model.camera.matrix.columns.3.xyz))
                LabeledContent("Target", value: Self.format(model.camera.target))
                HStack {
                    Button("Frame All") {
                        model.frameAll()
                    }
                    Button("Frame Selection") {
                        model.frameSelection()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private static func format(_ value: SIMD3<Float>) -> String {
        [value.x, value.y, value.z].map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: ", ")
    }
}

struct DefaultLightingInspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Form {
            Section("Default Lighting") {
                Toggle("Enabled", isOn: $model.renderSettings.usesDefaultLighting)
                    .help("Adds a light at the camera when the scene has none")
                LabeledContent("Status", value: status)
            }
        }
        .formStyle(.grouped)
    }

    private var status: String {
        if !model.renderSettings.usesDefaultLighting {
            "Off"
        } else if model.isDefaultLightingActive {
            "Lighting the scene from the camera"
        } else {
            "Not used: the scene has its own lights"
        }
    }
}

#Preview("Default Camera") {
    DefaultCameraInspectorView(model: EditorModel(sceneGraph: ComposerDocument().sceneGraph))
}

#Preview("Default Lighting") {
    DefaultLightingInspectorView(model: EditorModel(sceneGraph: ComposerDocument().sceneGraph))
}
