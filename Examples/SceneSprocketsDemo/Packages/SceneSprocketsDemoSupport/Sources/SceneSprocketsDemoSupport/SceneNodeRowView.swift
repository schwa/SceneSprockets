import SceneSprockets
import SwiftUI

// One node in the scene outline, with its children in a disclosure group.
struct SceneNodeRowView: View {
    var node: SceneGraph.Node
    var scene: DemoScene
    @Binding var selectedNodeID: SceneGraph.Node.ID?

    var body: some View {
        if node.children.isEmpty {
            SceneNodeRowLabel(node: node, scene: scene, selectedNodeID: $selectedNodeID)
        } else {
            DisclosureGroup {
                ForEach(node.children) { child in
                    Self(node: child, scene: scene, selectedNodeID: $selectedNodeID)
                }
            } label: {
                SceneNodeRowLabel(node: node, scene: scene, selectedNodeID: $selectedNodeID)
            }
        }
    }
}

// The row itself: name, selection and the visibility button. Used in two places (#493).
private struct SceneNodeRowLabel: View {
    var node: SceneGraph.Node
    var scene: DemoScene
    @Binding var selectedNodeID: SceneGraph.Node.ID?

    var body: some View {
        HStack {
            Button {
                selectedNodeID = selectedNodeID == node.id ? nil : node.id
            } label: {
                Label(node.label ?? "Untitled", systemImage: iconName)
                    .bold(selectedNodeID == node.id)
                    .foregroundStyle(node.isVisible ? .primary : .secondary)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(node.isVisible ? "Hide" : "Show", systemImage: node.isVisible ? "eye" : "eye.slash") {
                scene.toggleVisibility(of: node)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
    }

    private var iconName: String {
        switch node.content {
        case .empty: "folder"
        case .mesh: "cube"
        case .instancedMesh: "square.stack.3d.up"
        case .light: "lightbulb"
        case .camera: "camera"
        }
    }
}
