import SwiftUI

struct RenderSettingsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Form {
            Section("Show") {
                Toggle("Grid", isOn: $model.renderSettings.showsGrid)
                Toggle("Axes", isOn: $model.renderSettings.showsAxes)
                Toggle("Selection Outline", isOn: $model.renderSettings.outlinesSelection)
                Toggle("Statistics", isOn: $model.renderSettings.showsStatistics)
                    .help("Meshes, triangles and lights")
                Toggle("Lights and Cameras", isOn: $model.renderSettings.showsLightsAndCameras)
                    .help("Draw and click shapes for lights and cameras")
                Toggle("Frame Timing", isOn: $model.renderSettings.showsFrameTiming)
                    .help("Frame rate and CPU and GPU timings")
            }
            Section("Lighting") {
                Toggle("Default Lighting", isOn: $model.renderSettings.usesDefaultLighting)
                    .help("Adds a light at the camera when the scene has none")
                Toggle("Shadows", isOn: $model.renderSettings.showsShadows)
            }
            cameraSection
            Section("Debug") {
                Toggle("Framebuffer Only", isOn: $model.renderSettings.isFramebufferOnly)
                    .help("Turn off to keep the drawable readable, for example in a GPU capture")
            }
        }
        .formStyle(.grouped)
    }

    private var cameraSection: some View {
        Section("Camera") {
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
    }
}
