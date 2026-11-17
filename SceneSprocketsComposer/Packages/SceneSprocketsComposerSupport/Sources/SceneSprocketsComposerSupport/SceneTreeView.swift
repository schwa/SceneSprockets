import SceneSprockets
import SwiftUI

struct SceneTreeView: View {
    @Bindable var model: EditorModel

    // The Scene row stands for "no node selected", which shows scene settings in the inspector. Default Camera and
    // Default Lighting (#207) are editor rows next to Scene, not scene nodes. The selection is a key-path binding to
    // EditorModel.treeSelection (#223).
    var body: some View {
        List(selection: $model.treeSelection) {
            Label("Scene", systemImage: "globe")
                .tag(TreeItem.scene)
            Label("Default Camera", systemImage: "camera.viewfinder")
                .tag(TreeItem.editor(.defaultCamera))
            Label("Default Lighting", systemImage: "lightbulb.max")
                .foregroundStyle(model.isDefaultLightingActive ? .primary : .secondary)
                .tag(TreeItem.editor(.defaultLighting))
            OutlineGroup(model.outlineRoots, children: \.outlineChildren) { node in
                HStack {
                    Label(model.displayName(of: node), systemImage: node.systemImage)
                        .opacity(model.isHidden(node) ? 0.45 : 1)
                    Spacer()
                    SceneTreeVisibilityButton(model: model, node: node)
                    SceneTreeLockButton(model: model, node: node)
                }
                .tag(TreeItem.node(node.id))
                // Drag a row onto a group to move it inside, or onto any other row to move it before that row (#222).
                .draggable(model.beginTreeDrag(node))
                .dropDestination(for: String.self) { items, _ in
                    model.dropTreeItems(items, onto: node)
                }
                .contextMenu {
                    Button(model.isVisible(node) ? "Hide" : "Show", systemImage: model.isVisible(node) ? "eye.slash" : "eye") {
                        model.setVisible(!node.isVisible, node)
                    }
                    Button(model.isActive(node) ? "Deactivate" : "Activate", systemImage: model.isActive(node) ? "pause.circle" : "play.circle") {
                        model.setActive(!node.isActive, node)
                    }
                    Button(model.lockedNodes.contains(node.id) ? "Unlock" : "Lock", systemImage: model.lockedNodes.contains(node.id) ? "lock.open" : "lock") {
                        model.setLocked(!model.lockedNodes.contains(node.id), node)
                    }
                    Button("Group Selection", systemImage: "square.on.square") {
                        if !model.selectedIDs.contains(node.id) {
                            model.selection = node.id
                        }
                        model.groupSelection()
                    }
                    Button("Ungroup", systemImage: "square.on.square.dashed") {
                        model.selection = node.id
                        model.ungroupSelection()
                    }
                    .disabled(node.children.isEmpty || model.isLocked(node))
                    Button("Drop to Floor", systemImage: "arrow.down.to.line") {
                        model.dropToFloor(node)
                    }
                    .disabled(model.isLocked(node) || model.sceneGraph.worldBounds(of: node) == nil)
                    Button("Delete", systemImage: "trash") {
                        model.delete(node)
                    }
                    .disabled(node.parent == nil || model.isLocked(node))
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

// Faint when visible. Its own view, so a visibility change updates this button, not the whole row (#493).
private struct SceneTreeVisibilityButton: View {
    let model: EditorModel
    let node: SceneGraph.Node

    var body: some View {
        let isVisible = model.isVisible(node)
        Button(isVisible ? "Hide" : "Show", systemImage: isVisible ? "eye" : "eye.slash") {
            model.setVisible(!isVisible, node)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(isVisible ? .tertiary : .primary)
        .buttonStyle(.plain)
        .help(isVisible ? "Hide" : "Show")
    }
}

// Faint when unlocked, or when only an ancestor is locked.
private struct SceneTreeLockButton: View {
    let model: EditorModel
    let node: SceneGraph.Node

    var body: some View {
        let isLockedItself = model.lockedNodes.contains(node.id)
        let isLocked = model.isLocked(node)
        Button(isLockedItself ? "Unlock" : "Lock", systemImage: isLocked ? "lock.fill" : "lock.open") {
            model.setLocked(!isLockedItself, node)
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(isLockedItself ? .primary : .tertiary)
        .buttonStyle(.plain)
        .help(isLockedItself ? "Unlock" : "Lock")
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
