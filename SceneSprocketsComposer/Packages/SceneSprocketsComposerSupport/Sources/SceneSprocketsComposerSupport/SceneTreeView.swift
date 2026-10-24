import SceneSprockets
import SwiftUI

struct SceneTreeView: View {
    @Bindable var model: EditorModel

    // The Scene row stands for "no node selected", which shows scene settings in the inspector.
    private enum Item: Hashable {
        case scene
        case node(SceneGraph.Node.ID)
    }

    private var listSelection: Binding<Item?> {
        Binding(get: { model.selection.map(Item.node) ?? .scene }, set: { item in
            if case let .node(id) = item {
                model.selection = id
            } else {
                model.selection = nil
            }
        })
    }

    var body: some View {
        List(selection: listSelection) {
            Label("Scene", systemImage: "globe")
                .tag(Item.scene)
            OutlineGroup([model.sceneGraph.root], children: \.outlineChildren) { node in
                Label(node.displayName, systemImage: node.systemImage)
                    .tag(Item.node(node.id))
                    .contextMenu {
                        Button("Delete", systemImage: "trash") {
                            model.delete(node)
                        }
                        .disabled(node.parent == nil)
                    }
            }
        }
        #if os(macOS)
        .onDeleteCommand {
            model.deleteSelection()
        }
        #endif
    }
}

extension SceneGraph.Node {
    // OutlineGroup needs nil to mark a leaf.
    // swiftlint:disable:next discouraged_optional_collection
    var outlineChildren: [SceneGraph.Node]? {
        children.isEmpty ? nil : children
    }

    var displayName: String {
        label ?? "Untitled"
    }

    var systemImage: String {
        switch content {
        case .empty:
            "circle.dotted"

        case .mesh:
            "cube"

        case .light:
            "lightbulb"

        case .camera:
            "camera"
        }
    }
}
