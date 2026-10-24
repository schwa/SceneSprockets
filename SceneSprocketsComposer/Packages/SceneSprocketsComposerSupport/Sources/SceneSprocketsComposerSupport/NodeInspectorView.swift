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
                Section("Node") {
                    TextField("Name", text: Binding(get: { node.label ?? "" }, set: { model.setLabel($0.isEmpty ? nil : $0, of: node) }), prompt: Text("Untitled"))
                    LabeledContent("Kind", value: node.kindName)
                }
                Section("Transform") {
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
                if let light = light(node), light.wrappedValue.type == .spot {
                    Section("Spot Cone") {
                        LabeledContent("Inner") {
                            AngleEditor(angle: angle(light, \.innerConeAngle), limit: .degrees(0) ... .degrees(90))
                        }
                        LabeledContent("Outer") {
                            AngleEditor(angle: angle(light, \.outerConeAngle), limit: .degrees(0) ... .degrees(90))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .cameraControlStyle(.compact)
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
