import SceneSprockets
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
            Section("Debug") {
                Picker("View", selection: $model.renderSettings.debugMode) {
                    Text("Materials").tag(SceneGraphDebugMode?.none)
                    Divider()
                    ForEach(SceneGraphDebugMode.allCases, id: \.self) { mode in
                        Text(mode.name).tag(SceneGraphDebugMode?.some(mode))
                    }
                }
                .help("Show every mesh as shape, normals, texture coordinates and so on, instead of its material")
                Picker("Channel", selection: $model.renderSettings.materialChannel) {
                    Text("Lit").tag(SceneGraphMaterialChannel?.none)
                    Divider()
                    ForEach(SceneGraphMaterialChannel.allCases, id: \.self) { channel in
                        Text(channel.name).tag(SceneGraphMaterialChannel?.some(channel))
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
