import SceneSprockets
import SwiftUI

struct SceneTreeView: View {
    @Bindable var model: EditorModel

    // The Scene row stands for "no node selected", which shows scene settings in the inspector.
    // Default Camera and Default Lighting (#207) are editor rows next to Scene, not scene nodes.
    private enum Item: Hashable {
        case scene
        case editor(EditorItem)
        case node(SceneGraph.Node.ID)
    }

    // Multiple selection (#201). Choosing Scene, or nothing, clears the node selection. The primary node stays
    // primary while it is still selected; otherwise the newly added node becomes primary.
    private var listSelection: Binding<Set<Item>> {
        Binding(get: {
            if let editorItem = model.editorItem {
                return [.editor(editorItem)]
            }
            return model.selectedIDs.isEmpty ? [.scene] : Set(model.selectedIDs.map(Item.node))
        }, set: { items in
            let ids = items.compactMap { item -> SceneGraph.Node.ID? in
                if case let .node(id) = item { id } else { nil }
            }
            guard !ids.isEmpty else {
                // An editor row selects alone; Scene or nothing clears everything.
                let editorItem = items.lazy.compactMap { item -> EditorItem? in
                    if case let .editor(editorItem) = item { editorItem } else { nil }
                }.first
                model.selection = nil
                model.editorItem = editorItem
                return
            }
            let added = ids.first { !model.selectedIDs.contains($0) }
            model.select(ids, primary: added ?? model.selection)
        })
    }

    var body: some View {
        List(selection: listSelection) {
            Label("Scene", systemImage: "globe")
                .tag(Item.scene)
            Label("Default Camera", systemImage: "camera.viewfinder")
                .tag(Item.editor(.defaultCamera))
            Label("Default Lighting", systemImage: "lightbulb.max")
                .foregroundStyle(model.isDefaultLightingActive ? .primary : .secondary)
                .tag(Item.editor(.defaultLighting))
            OutlineGroup([model.sceneGraph.root], children: \.outlineChildren) { node in
                HStack {
                    Label(node.displayName, systemImage: node.systemImage)
                        .opacity(model.isHidden(node) ? 0.45 : 1)
                    Spacer()
                    visibilityButton(node)
                    lockButton(node)
                }
                .tag(Item.node(node.id))
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

    // Faint when visible.
    private func visibilityButton(_ node: SceneGraph.Node) -> some View {
        let isVisible = model.isVisible(node)
        return Button {
            model.setVisible(!isVisible, node)
        } label: {
            Image(systemName: isVisible ? "eye" : "eye.slash")
                .foregroundStyle(isVisible ? .tertiary : .primary)
        }
        .buttonStyle(.plain)
        .help(isVisible ? "Hide" : "Show")
    }

    // Faint when unlocked, or when only an ancestor is locked.
    private func lockButton(_ node: SceneGraph.Node) -> some View {
        let isLockedItself = model.lockedNodes.contains(node.id)
        let isLocked = model.isLocked(node)
        return Button {
            model.setLocked(!isLockedItself, node)
        } label: {
            Image(systemName: isLocked ? "lock.fill" : "lock.open")
                .foregroundStyle(isLockedItself ? .primary : .tertiary)
        }
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
