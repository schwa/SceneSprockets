import SceneSprockets
import SwiftUI

struct RenderSettingsView: View {
    @Bindable var model: EditorModel

    var body: some View {
        Form {
            Section("Show") {
                Toggle("Grid", isOn: $model.renderSettings.showsGrid)
                Toggle("Axes", isOn: $model.renderSettings.showsAxes)
                if model.renderSettings.showsAxes {
                    LabeledContent("Axis Lines") {
                        HStack {
                            Toggle("X", isOn: $model.renderSettings.showsXAxis)
                            Toggle("Y", isOn: $model.renderSettings.showsYAxis)
                            Toggle("Z", isOn: $model.renderSettings.showsZAxis)
                        }
                        .toggleStyle(.button)
                    }
                }
                Toggle("Selection Outline", isOn: $model.renderSettings.outlinesSelection)
                Toggle("Statistics", isOn: $model.renderSettings.showsStatistics)
                    .help("Meshes, triangles and lights")
                Toggle("Lights and Cameras", isOn: $model.renderSettings.showsLightsAndCameras)
                    .help("Draw and click shapes for lights and cameras")
                Picker("Bounding Boxes", selection: $model.renderSettings.boundingBoxes) {
                    ForEach(BoundingBoxes.Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .help("Draw world-space bounding boxes for the selection, or for every mesh")
                Toggle("Frame Timing", isOn: $model.renderSettings.showsFrameTiming)
                    .help("Frame rate and CPU and GPU timings")
            }
            // Default lighting and the camera are in the Default Lighting and Default Camera rows (#207).
            Section("Lighting") {
                Toggle("Shadows", isOn: $model.renderSettings.showsShadows)
            }
            Section("Performance") {
                FrameRatePickerView(cap: $model.renderSettings.maximumFramesPerSecond, display: model.display)
            }
            Section("Debug") {
                Picker("View", selection: $model.renderSettings.debugMode) {
                    Text("Materials").tag(DebugMode?.none)
                    Divider()
                    ForEach(DebugMode.allCases, id: \.self) { mode in
                        Text(mode.name).tag(DebugMode?.some(mode))
                    }
                }
                .help("Show every mesh as shape, normals, texture coordinates and so on, instead of its material")
                Picker("Channel", selection: $model.renderSettings.materialChannel) {
                    Text("Lit").tag(MaterialChannel?.none)
                    Divider()
                    ForEach(MaterialChannel.allCases, id: \.self) { channel in
                        Text(channel.name).tag(MaterialChannel?.some(channel))
                    }
                }
                .disabled(model.renderSettings.debugMode != nil)
                .help("Show one material value, such as base color or roughness, instead of lighting")
                Toggle("Framebuffer Only", isOn: $model.renderSettings.isFramebufferOnly)
                    .help("Turn off to keep the drawable readable, for example in a GPU capture")
            }
        }
        .formStyle(.grouped)
    }
}

// Display Maximum follows the display (it changes with the monitor and Low Power Mode); the others are fixed caps.
struct FrameRatePickerView: View {
    @Binding var cap: Int?
    var display: DisplayFrameRate

    var body: some View {
        Picker("Maximum Frame Rate", selection: $cap) {
            Text("Display Maximum (\(display.maximumFramesPerSecond) fps)").tag(Int?.none)
            Divider()
            ForEach(display.choices.reversed(), id: \.self) { rate in
                Text("\(rate) fps").tag(Int?.some(rate))
            }
            // A saved cap the current display cannot reach.
            if let cap, !display.choices.contains(cap) {
                Text("\(cap) fps (above this display)").tag(Int?.some(cap))
            }
        }
        .help("The preview draws at most this often. The system can draw more slowly, for example in Low Power Mode.")
        if display.isLowPowerModeEnabled {
            Text("Low Power Mode is on, so the system may limit the frame rate.")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var cap: Int?
    Form {
        FrameRatePickerView(cap: $cap, display: DisplayFrameRate())
    }
    .formStyle(.grouped)
}
