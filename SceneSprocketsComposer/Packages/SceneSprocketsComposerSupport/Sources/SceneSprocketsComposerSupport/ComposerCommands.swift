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
                Divider()
                AddShapeMenu(model: model)
            } else {
                Text("No Document")
            }
        }
    }
}
