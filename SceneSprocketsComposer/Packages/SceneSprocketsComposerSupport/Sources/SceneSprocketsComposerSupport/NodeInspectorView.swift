import GeometryLite3D
import Interaction3D
import SceneSprockets
import simd
import SwiftFields
import SwiftUI

struct NodeInspectorView: View {
    var model: EditorModel

    var body: some View {
        if let node = model.selectedNode {
            Form {
                let isLocked = model.isLocked(node)
                Section("Node") {
                    TextField("Name", text: Binding(get: { node.label ?? "" }, set: { model.setLabel($0.isEmpty ? nil : $0, of: node) }), prompt: Text("Untitled"))
                        .disabled(isLocked)
                    Toggle("Visible", isOn: Binding(get: { model.isVisible(node) }, set: { model.setVisible($0, node) }))
                        .help("Hidden nodes and their children are not drawn, do not light the scene and cannot be clicked")
                        .disabled(isLocked)
                    Toggle("Active", isOn: Binding(get: { model.isActive(node) }, set: { model.setActive($0, node) }))
                        .help("Inactive nodes and their children are hidden, and their actions, constraints, particles and physics stop")
                        .disabled(isLocked)
                    Toggle("Locked", isOn: Binding(get: { model.lockedNodes.contains(node.id) }, set: { model.setLocked($0, node) }))
                        .help("Locked nodes and their children cannot be picked in the viewport, moved or edited")
                    LabeledContent("Kind", value: node.kindName)
                }
                Section("Transform") {
                    if isLocked {
                        Text("Unlock to edit.")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Translation") {
                        vectorFields(trs(node, \.translation))
                    }
                    LabeledContent("Rotation") {
                        let rotation = eulerDegrees(trs(node, \.rotation))
                        HStack {
                            ScrubbableValueField("Pitch", value: component(rotation, 0), suffix: "\u{00B0}", range: -180 ... 180, sensitivity: 0.2)
                            ScrubbableValueField("Yaw", value: component(rotation, 1), suffix: "\u{00B0}", range: -180 ... 180, sensitivity: 0.2)
                            ScrubbableValueField("Roll", value: component(rotation, 2), suffix: "\u{00B0}", range: -180 ... 180, sensitivity: 0.2)
                        }
                    }
                    LabeledContent("Scale") {
                        vectorFields(trs(node, \.scale))
                    }
                }
                .disabled(isLocked)
                let materialCount = model.materials(of: node).count
                ForEach(0..<materialCount, id: \.self) { index in
                    MaterialSection(model: model, node: node, index: index, count: materialCount, isLocked: isLocked)
                }
                if let light = light(node), light.wrappedValue.type == .spot {
                    Section("Spot Cone") {
                        LabeledContent("Inner") {
                            AngleEditor(angle: angle(light, \.innerConeAngle), limit: .degrees(0) ... .degrees(90))
                        }
                        LabeledContent("Outer") {
                            AngleEditor(angle: angle(light, \.outerConeAngle), limit: .degrees(0) ... .degrees(90))
                        }
                    }
                    .disabled(isLocked)
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
            ScrubbableValueField("X", value: component(value, 0), precision: 3)
            ScrubbableValueField("Y", value: component(value, 1), precision: 3)
            ScrubbableValueField("Z", value: component(value, 2), precision: 3)
        }
    }

    private func component(_ value: Binding<SIMD3<Float>>, _ index: Int) -> Binding<Double> {
        Binding(get: { Double(value.wrappedValue[index]) }, set: { value.wrappedValue[index] = Float($0) })
    }

    // Pitch, yaw, roll in degrees, converted as CameraPose does.
    private func eulerDegrees(_ rotation: Binding<simd_quatf>) -> Binding<SIMD3<Float>> {
        Binding(get: { CameraPose(matrix: simd_float4x4(rotation.wrappedValue)).rotationDegrees }, set: { degrees in
            rotation.wrappedValue = simd_quatf(CameraPose(position: .zero, rotationDegrees: degrees).matrix)
        })
    }

    private func trs<Value>(_ node: SceneGraph.Node, _ keyPath: WritableKeyPath<Transform3D, Value>) -> Binding<Value> {
        Binding(get: { model.localTRS(of: node)[keyPath: keyPath] }, set: { newValue in
            let previous = node.localTransform
            var trs = previous.trs
            trs[keyPath: keyPath] = newValue
            model.setTransform(.trs(trs), of: node, undoTo: previous)
        })
    }

    private func light(_ node: SceneGraph.Node) -> Binding<Light>? {
        _ = model.localTRS(of: node)
        guard case .light(let light) = node.content else {
            return nil
        }
        return Binding(get: { light }, set: { model.setLight($0, of: node) })
    }

    private func angle(_ light: Binding<Light>, _ keyPath: WritableKeyPath<Light, Float>) -> Binding<Angle> {
        Binding(get: { .radians(Double(light.wrappedValue[keyPath: keyPath])) }, set: { light.wrappedValue[keyPath: keyPath] = Float($0.radians) })
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
