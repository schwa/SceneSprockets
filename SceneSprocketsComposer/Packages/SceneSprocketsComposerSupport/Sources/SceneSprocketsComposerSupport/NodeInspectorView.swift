import GeometryLite3D
import Interaction3D
import SceneSprockets
import simd
import SwiftFields
import SwiftUI

struct NodeInspectorView: View {
    @Bindable var model: EditorModel

    var body: some View {
        if let node = model.selectedNode {
            Form {
                let isLocked = model.isLocked(node)
                if model.selectedIDs.count > 1 {
                    MultipleSelectionSectionView(model: model)
                }
                Section("Node") {
                    TextField("Name", text: $model.selectedLabel, prompt: Text("Untitled"))
                        .disabled(isLocked)
                    Toggle("Visible", isOn: $model.selectedIsVisible)
                        .help("Hidden nodes and their children are not drawn, do not light the scene and cannot be clicked")
                        .disabled(isLocked)
                    Toggle("Active", isOn: $model.selectedIsActive)
                        .help("Inactive nodes and their children are hidden, and their actions, constraints, particles and physics stop")
                        .disabled(isLocked)
                    Toggle("Locked", isOn: $model.selectedIsLocked)
                        .help("Locked nodes and their children cannot be picked in the viewport, moved or edited")
                    LabeledContent("Kind", value: node.kindName)
                }
                Section("Transform") {
                    if isLocked {
                        Text("Unlock to edit.")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Translation") {
                        vectorFields($model.selectedTRS.translation)
                    }
                    LabeledContent("Rotation") {
                        let rotation = $model.selectedTRS.rotationDegrees
                        HStack {
                            ScrubbableValueField("Pitch", value: rotation[double: 0], suffix: "\u{00B0}", range: -180 ... 180, sensitivity: 0.2)
                            ScrubbableValueField("Yaw", value: rotation[double: 1], suffix: "\u{00B0}", range: -180 ... 180, sensitivity: 0.2)
                            ScrubbableValueField("Roll", value: rotation[double: 2], suffix: "\u{00B0}", range: -180 ... 180, sensitivity: 0.2)
                        }
                    }
                    LabeledContent("Scale") {
                        vectorFields($model.selectedTRS.scale)
                    }
                }
                .disabled(isLocked)
                BoundsSectionView(model: model)
                let materials = model.materials(of: node)
                ForEach(materials.indices, id: \.self) { index in
                    MaterialSectionView(model: model, index: index, count: materials.count, isLocked: isLocked)
                }
                if let light = Binding($model.selectedLight) {
                    LightSectionView(light: light, isLocked: isLocked)
                }
            }
            .formStyle(.grouped)
            .cameraControlStyle(.compact)
        } else if model.editorItem == .defaultCamera {
            DefaultCameraInspectorView(model: model)
        } else if model.editorItem == .defaultLighting {
            DefaultLightingInspectorView(model: model)
        } else {
            SceneInspectorView(model: model)
        }
    }

    private func vectorFields(_ value: Binding<SIMD3<Float>>) -> some View {
        HStack {
            ScrubbableValueField("X", value: value[double: 0], precision: 3)
            ScrubbableValueField("Y", value: value[double: 1], precision: 3)
            ScrubbableValueField("Z", value: value[double: 2], precision: 3)
        }
    }
}

extension SceneGraph.Node {
    var kindName: String {
        switch content {
        case .empty:
            "Empty"

        case .mesh:
            "Mesh"

        case .light:
            "Light"

        case .camera:
            "Camera"
        }
    }
}
