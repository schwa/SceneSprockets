import SceneSprocketsGizmos
import SwiftUI

extension FocusedValues {
    @Entry var editorModel: EditorModel?
}

// The Scene menu: gizmo tool and space, framing and adding shapes for the focused document.
public struct ComposerCommands: Commands {
    @FocusedValue(\.editorModel)
    private var model

    public init() {}

    public var body: some Commands {
        // ⌘1–3 pick the gizmo tool, so panels use ⌃⌘ (left) and ⌥⌘ (right), like Xcode's inspectors.
        CommandGroup(after: .sidebar) {
            Group {
                Button("Show Scene") { model?.show(SidebarTab.scene) }
                    .keyboardShortcut("1", modifiers: [.control, .command])
                Button("Show Assistant") { model?.show(SidebarTab.assistant) }
                    .keyboardShortcut("2", modifiers: [.control, .command])
                Divider()
                Button("Show Inspector") { model?.show(InspectorTab.inspector) }
                    .keyboardShortcut("1", modifiers: [.option, .command])
                Button("Show Render Settings") { model?.show(InspectorTab.render) }
                    .keyboardShortcut("2", modifiers: [.option, .command])
            }
            .disabled(model == nil)
        }
        CommandMenu("Scene") {
            if let model {
                @Bindable var model = model
                Picker("Tool", selection: $model.gizmoMode) {
                    Text("Move").tag(TransformGizmo.Mode.translate)
                        .keyboardShortcut("1")
                    Text("Rotate").tag(TransformGizmo.Mode.rotate)
                        .keyboardShortcut("2")
                    Text("Scale").tag(TransformGizmo.Mode.scale)
                        .keyboardShortcut("3")
                }
                .pickerStyle(.inline)
                Picker("Space", selection: $model.gizmoSpace) {
                    Text("World").tag(TransformGizmo.Space.world)
                    Text("Local").tag(TransformGizmo.Space.local)
                }
                .pickerStyle(.inline)
                Divider()
                Button("Frame Selection") {
                    model.frameSelection()
                }
                Button("Drop to Floor") {
                    model.dropSelectionToFloor()
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
                .disabled(!model.canDropSelectionToFloor)
                Divider()
                AddShapeMenu(model: model)
            } else {
                Text("No Document")
            }
        }
    }
}
