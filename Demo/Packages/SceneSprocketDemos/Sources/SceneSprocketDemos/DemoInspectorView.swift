import SceneSprocket
import SwiftUI

// The demo's controls, its scene outline and the selected node.
struct DemoInspectorView: View {
    @Bindable var scene: DemoScene

    var body: some View {
        Form {
            if !scene.parameters.isEmpty {
                Section("Controls") {
                    ForEach(scene.parameters) { parameter in
                        DemoParameterView(parameter: parameter, value: $scene[value: parameter.name])
                    }
                }
            }
            Section("Scene") {
                // Reading the revision refreshes the outline when the demo changes the hierarchy or visibility.
                let _ = scene.outlineRevision
                SceneNodeRow(node: scene.sceneGraph.root, scene: scene, selectedNodeID: $scene.selectedNodeID)
            }
            if let node = selectedNode {
                NodeInspectorView(node: node)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedNode: SceneGraph.Node? {
        guard let selectedNodeID = scene.selectedNodeID else {
            return nil
        }
        return scene.sceneGraph.nodesWithWorldTransforms(includeHidden: true).first { $0.node.id == selectedNodeID }?.node
    }
}

struct DemoParameterView: View {
    let parameter: DemoParameter
    @Binding var value: Float

    var body: some View {
        switch parameter.kind {
        case .slider(let range):
            LabeledContent(parameter.name) {
                Slider(value: $value, in: range)
            }
        case .toggle:
            Toggle(parameter.name, isOn: $value.isOn)
        case .choice(let options):
            Picker(parameter.name, selection: $value.choiceIndex) {
                ForEach(options.indices, id: \.self) { index in
                    Text(options[index]).tag(index)
                }
            }
        }
    }
}

// Writable views onto a parameter value, so bindings project through key paths instead of closures.
private extension Float {
    var isOn: Bool {
        get { self != 0 }
        set { self = newValue ? 1 : 0 }
    }

    var choiceIndex: Int {
        get { Int(self) }
        set { self = Float(newValue) }
    }
}

#Preview {
    DemoParameterView(parameter: .slider("Speed", 0...2, default: 1), value: .constant(1))
        .padding()
}
