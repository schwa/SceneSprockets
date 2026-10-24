import CollaborationKitUI
import SceneSprockets
import SceneSprocketsGizmos
import SwiftUI

// Three panes: scene graph tree, preview, inspector.
public struct ComposerView: View {
    @State private var model: EditorModel
    private let document: ComposerDocument
    @AppStorage(GizmoSize.storageKey)
    private var gizmoSize = GizmoSize.small
    @Environment(CollaborationCredentials.self)
    private var credentials
    @State private var sidebarTab = SidebarTab.scene
    // This document's conversation; kept here so it survives sidebar tab switches.
    @State private var assistantStore: ConversationStore?

    private enum SidebarTab {
        case scene
        case assistant
    }
    @Environment(\.undoManager)
    private var undoManager

    public init(document: ComposerDocument) {
        let model = EditorModel(sceneGraph: document.sceneGraph)
        if let state = document.editorState {
            model.apply(state)
        }
        self.document = document
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                Picker("Sidebar", selection: $sidebarTab) {
                    Label("Scene", systemImage: "list.bullet.indent").tag(SidebarTab.scene)
                    Label("Assistant", systemImage: "bubble.left.and.text.bubble.right").tag(SidebarTab.assistant)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                switch sidebarTab {
                case .scene:
                    SceneTreeView(model: model)

                case .assistant:
                    AssistantPanel(store: assistantStore)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 300)
        } detail: {
            ScenePreviewView(model: model)
                .inspector(isPresented: $model.isInspectorPresented) {
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
                    ToolbarItemGroup(placement: .principal) {
                        AddShapeMenu(model: model)
                        GizmoToolbarContent(model: model)
                        Button("Frame Selection", systemImage: "viewfinder") {
                            model.frameSelection()
                        }
                        .keyboardShortcut("f", modifiers: [])
                        .help("Frame the selected node, or the whole scene (F)")
                        Button("Delete", systemImage: "trash") {
                            model.deleteSelection()
                        }
                        .disabled(!model.canDeleteSelection)
                        .help("Delete the selected node")
                    }
                    ToolbarItem {
                        Button("Inspector", systemImage: "sidebar.trailing") {
                            model.isInspectorPresented.toggle()
                        }
                    }
                }
        }
        .focusedSceneValue(\.editorModel, model)
        .onAppear {
            document.editorModel = model
            if assistantStore == nil {
                assistantStore = ComposerAssistant.makeStore(credentials: credentials)
            }
        }
        // A new conversation for the current provider after signing in or out, or switching backend or model.
        .onChange(of: "\(credentials.backend.id)-\(credentials.selectedModel)-\(credentials.hasCredentials)") {
            assistantStore?.cancel()
            assistantStore = ComposerAssistant.makeStore(credentials: credentials)
        }
        .onDisappear {
            assistantStore?.cancel()
        }
        .onChange(of: gizmoSize, initial: true) {
            model.gizmoSize = gizmoSize
        }
        .onChange(of: undoManager, initial: true) {
            model.undoManager = undoManager
        }
    }
}

struct AddShapeMenu: View {
    var model: EditorModel

    var body: some View {
        Menu("Add", systemImage: "plus") {
            ForEach(ShapeKind.allCases) { kind in
                Button(kind.label, systemImage: kind.systemImage) {
                    model.addShape(kind.shape, label: kind.label)
                }
            }
            Divider()
            ForEach(Light.LightType.allCases, id: \.self) { type in
                Button(EditorModel.label(for: type), systemImage: type == .point ? "lightbulb" : "sun.max") {
                    model.addLight(type)
                }
            }
            Divider()
            Button("Camera", systemImage: "camera") {
                model.addCamera()
            }
        }
        .help("Add a shape, light or camera")
    }
}

enum ShapeKind: CaseIterable, Identifiable {
    case box, sphere, plane, cylinder, cone, capsule, torus, tube, pyramid, floor, star

    var id: Self { self }

    var label: String {
        switch self {
        case .box: "Box"
        case .sphere: "Sphere"
        case .plane: "Plane"
        case .cylinder: "Cylinder"
        case .cone: "Cone"
        case .capsule: "Capsule"
        case .torus: "Torus"
        case .tube: "Tube"
        case .pyramid: "Pyramid"
        case .floor: "Floor"
        case .star: "Star"
        }
    }

    var systemImage: String {
        switch self {
        case .box: "cube"
        case .sphere: "circle"
        case .plane: "square"
        case .cylinder: "cylinder"
        case .cone: "cone"
        case .capsule: "capsule"
        case .torus: "circle.circle"
        case .tube: "circle.dotted.circle"
        case .pyramid: "pyramid"
        case .floor: "square.bottomhalf.filled"
        case .star: "star"
        }
    }

    var shape: SceneGraph.Shape {
        switch self {
        case .box: .box()
        case .sphere: .sphere()
        case .plane: .plane()
        case .cylinder: .cylinder()
        case .cone: .cone()
        case .capsule: .capsule()
        case .torus: .torus()
        case .tube: .tube()
        case .pyramid: .pyramid()
        case .floor: .floor()
        case .star: .extrudedPath(Self.starPath, extrusionDepth: 0.2)
        }
    }

    // A five-pointed star, 1 unit across, as a SwiftUI Path description.
    private static let starPath: String = {
        let points = (0..<10).map { index in
            let angle = Float.pi / 2 + Float(index) * .pi / 5
            let radius: Float = index.isMultiple(of: 2) ? 0.5 : 0.2
            return "\(radius * cos(angle)) \(radius * sin(angle))"
        }
        return "\(points[0]) m " + points.dropFirst().map { "\($0) l" }.joined(separator: " ") + " h"
    }()
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
