import SceneSprockets
import SwiftUI

struct SceneTreeView: View {
    @Bindable var model: EditorModel

    var body: some View {
        List(selection: $model.selection) {
            OutlineGroup([model.sceneGraph.root], children: \.outlineChildren) { node in
                Label(node.displayName, systemImage: node.systemImage)
            }
        }
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
