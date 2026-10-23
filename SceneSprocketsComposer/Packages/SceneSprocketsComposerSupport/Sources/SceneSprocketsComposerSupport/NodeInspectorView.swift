import SceneSprockets
import SwiftUI

struct NodeInspectorView: View {
    var model: EditorModel

    var body: some View {
        if let node = model.selectedNode {
            Form {
                Section("Node") {
                    LabeledContent("Name", value: node.displayName)
                    LabeledContent("Kind", value: node.kindName)
                }
                Section("Transform") {
                    let trs = model.localTRS(of: node)
                    LabeledContent("Translation", value: format(trs.translation))
                    LabeledContent("Rotation", value: "\(format(trs.rotation.axis)) @ \((trs.rotation.angle * 180 / .pi).formatted(.number.precision(.fractionLength(1))))°")
                    LabeledContent("Scale", value: format(trs.scale))
                }
            }
            .formStyle(.grouped)
        } else {
            SceneInspectorView(model: model)
        }
    }

    private func format(_ value: SIMD3<Float>) -> String {
        [value.x, value.y, value.z].map { $0.formatted(.number.precision(.fractionLength(2))) }.joined(separator: ", ")
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
