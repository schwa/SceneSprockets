import SceneSprocketsGizmos
import SwiftUI

// Three panes: scene graph tree, preview, inspector.
public struct ComposerView: View {
    @State private var model: EditorModel
    @State private var isInspectorPresented = true
    @Environment(\.undoManager)
    private var undoManager

    public init(document: ComposerDocument) {
        _model = State(initialValue: EditorModel(sceneGraph: document.sceneGraph))
    }

    public var body: some View {
        NavigationSplitView {
            SceneTreeView(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 240)
        } detail: {
            ScenePreviewView(model: model)
                .inspector(isPresented: $isInspectorPresented) {
                    TabView {
                        Tab("Inspector", systemImage: "slider.horizontal.3") {
                            NodeInspectorView(model: model)
                        }
                        Tab("Render", systemImage: "camera.aperture") {
                            RenderSettingsView(model: model)
                        }
                    }
                    .inspectorColumnWidth(min: 240, ideal: 300)
                }
                .toolbar {
                    GizmoToolbarContent(model: model)
                    Button("Frame Selection", systemImage: "viewfinder") {
                        model.frameSelection()
                    }
                    .keyboardShortcut("f", modifiers: [])
                    .help("Frame the selected node, or the whole scene (F)")
                    Button("Inspector", systemImage: "sidebar.trailing") {
                        isInspectorPresented.toggle()
                    }
                }
        }
        .onChange(of: undoManager, initial: true) {
            model.undoManager = undoManager
        }
    }
}

struct GizmoToolbarContent: View {
    @Bindable var model: EditorModel

    var body: some View {
        Picker("Tool", selection: $model.gizmoMode) {
            Label("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right").tag(TransformGizmo.Mode.translate)
            Label("Rotate", systemImage: "arrow.clockwise").tag(TransformGizmo.Mode.rotate)
            Label("Scale", systemImage: "arrow.up.left.and.arrow.down.right").tag(TransformGizmo.Mode.scale)
        }
        .pickerStyle(.segmented)
        .help("Select a node, then drag the gizmo's handles")
        Picker("Space", selection: $model.gizmoSpace) {
            Text("World").tag(TransformGizmo.Space.world)
            Text("Local").tag(TransformGizmo.Space.local)
        }
    }
}
