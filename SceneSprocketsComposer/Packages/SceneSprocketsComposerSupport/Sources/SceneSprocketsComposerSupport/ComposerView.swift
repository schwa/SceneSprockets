import CollaborationKitUI
import os
import SceneSprockets
import SceneSprocketsGizmos
import SceneSprocketsPBR
import SwiftUI

private let insertLogger = Logger(subsystem: "io.schwa.SceneSprocketsComposer", category: "Insert")

// Three panes: scene graph tree, preview, inspector.
public struct ComposerView: View {
    @State private var model: EditorModel
    private let document: ComposerDocument
    @AppStorage(GizmoSize.storageKey)
    private var gizmoSize = GizmoSize.small
    @Environment(CollaborationCredentials.self)
    private var credentials
    // This document's conversation; kept here so it survives sidebar tab switches.
    @State private var assistantStore: ConversationStore?
    // Makes each assistant turn one undo step (#203).
    @State private var assistantTurnUndo: AssistantTurnUndo?
    // An error or loader warnings from Insert Model File…
    @State private var insertMessage: String?
    // A .gltf waiting for its folder to be granted (#206).
    @State private var fileNeedingFolder: URL?
    // Shown first, explaining why the folder is needed (#213).
    @State private var folderAccessRequest: FolderAccessRequest?
    @State private var isChoosingFolder = false
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

    private func externalFiles(_ url: URL) throws -> [String] {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try ModelFile.externalFiles(url)
    }

    private func insertModel(_ url: URL, scopedURL: URL) {
        do {
            let warnings = try model.insertModel(from: url, scopedURL: scopedURL)
            // Scene archives cannot store imported meshes yet; saving keeps the nodes but drops the geometry. Loader
            // warnings are summarized; the full text goes to the log (#206).
            for warning in warnings {
                insertLogger.warning("Insert \(url.lastPathComponent, privacy: .public): \(warning, privacy: .public)")
            }
            insertMessage = (["The model's meshes are not saved with the document yet (#157, #158)."] + InsertWarnings.summary(warnings)).joined(separator: "\n")
        } catch {
            insertMessage = error.localizedDescription
        }
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            VStack(spacing: 0) {
                Picker("Sidebar", selection: $model.sidebarTab) {
                    Label("Scene", systemImage: "list.bullet.indent").tag(SidebarTab.scene)
                    Label("Assistant", systemImage: "bubble.left.and.text.bubble.right").tag(SidebarTab.assistant)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                switch model.sidebarTab {
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
                    TabView(selection: $model.inspectorTab) {
                        Tab("Inspector", systemImage: "slider.horizontal.3", value: InspectorTab.inspector) {
                            NodeInspectorView(model: model)
                        }
                        Tab("Render", systemImage: "camera.aperture", value: InspectorTab.render) {
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
        .fileImporter(isPresented: $model.isImportingModel, allowedContentTypes: ModelFile.contentTypes) { result in
            do {
                let url = try result.get()
                let files = try externalFiles(url)
                if !files.isEmpty {
                    // Explain first; the folder importer opens from the alert's button (#213).
                    folderAccessRequest = FolderAccessRequest(file: url, externalFileCount: files.count)
                } else {
                    insertModel(url, scopedURL: url)
                }
            } catch {
                insertMessage = error.localizedDescription
            }
        }
        .background {
            // A second importer must live on another view; this one asks for the folder of a .gltf whose buffers and
            // images are separate files, which the sandbox does not grant with the file (#206). As in the
            // MetalSprocketsGLTF GLTFViewer demo.
            Color.clear
                // onCancellation reports Cancel directly, so no ordering against the completion is needed (#230).
                .fileImporter(isPresented: $isChoosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                    if let file = fileNeedingFolder {
                        switch result.map(\.first) {
                        case .success(let folder?) where ModelFile.isFile(file, inside: folder):
                            insertModel(file, scopedURL: folder)
                        case .success(let folder?):
                            insertMessage = FolderAccessRequest.wrongFolderMessage(file: file, folder: folder)
                        case .success(nil), .failure:
                            insertMessage = FolderAccessRequest.cancelledMessage(file: file)
                        }
                    }
                    fileNeedingFolder = nil
                } onCancellation: {
                    if let file = fileNeedingFolder {
                        insertMessage = FolderAccessRequest.cancelledMessage(file: file)
                    }
                    fileNeedingFolder = nil
                }
                .fileDialogMessage("\(fileNeedingFolder?.lastPathComponent ?? "This file") loads other files from its folder. Choose that folder to allow access.")
                .fileDialogDefaultDirectory(fileNeedingFolder?.deletingLastPathComponent())
                .fileDialogConfirmationLabel("Allow Access")
        }
        .alert(FolderAccessRequest.title, isPresented: $folderAccessRequest.isPresent, presenting: folderAccessRequest) { request in
            Button("Choose Folder\u{2026}") {
                fileNeedingFolder = request.file
                isChoosingFolder = true
            }
            Button("Cancel", role: .cancel) {
                insertMessage = FolderAccessRequest.cancelledMessage(file: request.file)
            }
        } message: { request in
            Text(request.message)
        }
        .alert("Insert Model File", isPresented: $insertMessage.isPresent) {
            Button("OK") {
                insertMessage = nil
            }
        } message: {
            Text(insertMessage ?? "")
        }
        .onChange(of: assistantStore?.isGenerating ?? false) { _, isGenerating in
            if assistantTurnUndo == nil {
                assistantTurnUndo = AssistantTurnUndo(model: model)
            }
            if isGenerating {
                assistantTurnUndo?.begin()
            } else {
                assistantTurnUndo?.end()
            }
        }
        .onAppear {
            // Saving can run off the main actor, so the document keeps its own copy of the editor state (#204).
            document.attach(model)
            if assistantStore == nil {
                assistantStore = ComposerAssistant.makeStore(credentials: credentials, model: model)
            }
        }
        // A new conversation for the current provider after signing in or out, or switching backend or model.
        .onChange(of: "\(credentials.backend.id)-\(credentials.selectedModel)-\(credentials.hasCredentials)") {
            assistantStore?.cancel()
            assistantStore = ComposerAssistant.makeStore(credentials: credentials, model: model)
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
            Divider()
            Button("Insert Model File\u{2026}", systemImage: "square.and.arrow.down") {
                model.isImportingModel = true
            }
        }
        .help("Add a shape, light, camera or model file")
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
