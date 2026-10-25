import CollaborationKit
import CollaborationKitUI
import CoreGraphics
import MetalSprocketsAddOns
import MetalSprocketsPBR
import Metal
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import Foundation
import GeometryLite3D
import simd
import SceneSprockets
@testable import SceneSprocketsComposerSupport
import Testing
import UniformTypeIdentifiers

@Test func documentTypeIdentifier() {
    #expect(UTType.sceneSprocketsDocument.identifier == "io.schwa.scenesprockets-document")
}

@MainActor
@Test func newDocumentIsEmpty() {
    let document = ComposerDocument()
    #expect(document.sceneGraph.root.children.isEmpty)
}

// #236: every edit goes through EditorModel.perform. At that boundary: the edit changes the saved scene, undo
// restores it exactly, redo applies it again, and the undo step has the edit's name.
@MainActor
struct SceneEditBoundaryTests {
    struct Edit: CustomTestStringConvertible, Sendable {
        var actionName: String
        var apply: @MainActor @Sendable (EditorModel, SceneGraph.Node) -> Void
        var testDescription: String { actionName }
    }

    nonisolated static let edits: [Edit] = [
        Edit(actionName: "Transform") { model, node in model.setTransform(.matrix(.init(diagonal: [2, 2, 2, 1])), of: node, undoTo: node.localTransform) },
        Edit(actionName: "Hide") { model, node in model.setVisible(false, node) },
        Edit(actionName: "Deactivate") { model, node in model.setActive(false, node) },
        Edit(actionName: "Rename") { model, node in model.setLabel("Renamed", of: node) },
        Edit(actionName: "Delete") { model, node in model.delete(node) },
        Edit(actionName: "Add Sphere") { model, _ in model.addShape(.sphere(), label: "Sphere") },
        Edit(actionName: "Move") { model, node in model.reparent(node, to: model.sceneGraph.root.children[1]) },
        Edit(actionName: "Move Down") { model, _ in model.moveSelection(by: 1) },
        Edit(actionName: "Group") { model, _ in model.groupSelection() },
        Edit(actionName: "Light") { model, _ in
            let light = model.sceneGraph.root.children[1]
            guard case .light(var value) = light.content else {
                return
            }
            value.intensity = 7
            model.setLight(value, of: light)
        },
        Edit(actionName: "Color") { model, _ in model.editSelection("Color") { model, node in model.setBaseColor([1, 0, 0], of: node) } },
        Edit(actionName: "Metal Material") { model, node in try? model.editMaterials(of: node, at: 0, actionName: "Metal Material", [.preset(.metal), .uniforms { $0.roughnessFactor = 0.6 }]) },
        Edit(actionName: "Environment Rotation") { model, _ in model[environment: "Environment Rotation"].rotationDegrees = 45 },
        Edit(actionName: "Drop to Floor") { model, _ in model.dropSelectionToFloor() },
    ]

    func sceneJSON(_ model: EditorModel) throws -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
        defer { try? FileManager.default.removeItem(at: url) }
        try SceneArchive.composer.write(model.sceneGraph, to: url)
        return try String(contentsOf: url.appendingPathComponent("scene.json"), encoding: .utf8)
    }

    @Test(arguments: edits)
    func editUndoesAndRedoes(_ edit: Edit) throws {
        let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
        model.addShape(.box(), label: "Box")
        model.addLight(.point)
        let box = model.sceneGraph.root.children[0]
        model.selection = box.id
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        model.undoManager = undoManager
        let before = try sceneJSON(model)
        nonisolated(unsafe) var notified = false
        withObservationTracking {
            model.observe([.transform, .visibility, .label, .content, .structure, .environment])
        } onChange: {
            notified = true
        }
        undoManager.beginUndoGrouping()
        edit.apply(model, box)
        undoManager.endUndoGrouping()
        let after = try sceneJSON(model)
        #expect(after != before)
        #expect(undoManager.undoActionName == edit.actionName)
        #expect(notified)
        undoManager.undo()
        #expect(try sceneJSON(model) == before)
        undoManager.redo()
        #expect(try sceneJSON(model) == after)
    }

    // #237: observers of one aspect are not told about others.
    @Test
    func observersOnlySeeTheirAspect() throws {
        let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
        model.addShape(.box(), label: "Box")
        let box = try #require(model.selectedNode)
        nonisolated(unsafe) var notified: [String] = []
        func track(_ name: String, _ aspects: SceneAspects) {
            withObservationTracking {
                model.observe(aspects)
            } onChange: {
                notified.append(name)
            }
        }
        track("label", .label)
        track("transform", .transform)
        track("tree", [.visibility, .label, .structure])
        model.setTransform(.trs(.init(translation: [1, 0, 0])), of: box, undoTo: box.localTransform)
        #expect(notified == ["transform"])
        notified = []
        track("transform", .transform)
        model.setLabel("Renamed", of: box)
        #expect(Set(notified) == ["label", "tree"])
    }
}

@MainActor
@Test func documentRoundTrips() throws {
    let document = ComposerDocument()
    EditorModel(sceneGraph: document.sceneGraph).addShape(.box(), label: "Box")
    let wrapper = try document.snapshot(contentType: .sceneSprocketsDocument)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try wrapper.write(to: url, options: [], originalContentsURL: nil)
    let loaded = try ComposerDocument(contentsOf: url)
    #expect(loaded.sceneGraph.root.children.map(\.label) == ["Box"])
}

// #175
@MainActor
@Test func savingWritesPreviewImage() throws {
    let document = ComposerDocument()
    EditorModel(sceneGraph: document.sceneGraph).addShape(.box(), label: "Box")
    let wrapper = try document.snapshot(contentType: .sceneSprocketsDocument)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try wrapper.write(to: url, options: [], originalContentsURL: nil)
    let image = try #require(DocumentPreview.image(inBundleAt: url))
    #expect(image.width == 1024)
    #expect(image.height == 768)
    // The box is in the middle; the clear color is black.
    let pixel = try #require(image.cropping(to: CGRect(x: 512, y: 384, width: 1, height: 1)))
    var bytes = [UInt8](repeating: 0, count: 4)
    let context = try #require(CGContext(data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    #expect(Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2]) > 30)
}

// #227: off the main thread, snapshot saves the scene as captured after the last undoable edit; it does not read
// the live graph, which the main actor may be changing.
@MainActor
@Test func offMainSnapshotSavesTheCapturedScene() async throws {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    document.attach(model)
    undoManager.beginUndoGrouping()
    model.addShape(.box(), label: "Captured")
    undoManager.endUndoGrouping()
    let node = try #require(model.sceneGraph.root.children.first)
    for _ in 0 ..< 10 {
        await Task.yield()
    }
    // A change with no undo step, as in the middle of a drag: not captured yet.
    node.label = "Live"
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try await Task.detached {
        try document.snapshot(contentType: .sceneSprocketsDocument).write(to: url, options: [], originalContentsURL: nil)
    }.value
    let loaded = try ComposerDocument(contentsOf: url)
    #expect(loaded.sceneGraph.root.children.first?.label == "Captured")
}

// #232: the document follows editor changes itself, without the view copying on every update.
@MainActor
@Test func attachedDocumentTracksEditorState() async {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    document.attach(model)
    #expect(document.savedEditorState?.gizmoMode == model.gizmoMode)
    model.gizmoMode = .scale
    model.renderSettings.fieldOfView = 42
    for _ in 0 ..< 10 where document.savedEditorState?.renderSettings.fieldOfView != 42 {
        await Task.yield()
    }
    #expect(document.savedEditorState?.gizmoMode == .scale)
    #expect(document.savedEditorState?.renderSettings.fieldOfView == 42)
}

// #185
@MainActor
@Test func editorStateRoundTrips() throws {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    document.editorModel = model
    model.addShape(.box(), label: "A")
    model.addShape(.sphere(), label: "B")
    model.camera.matrix = .init(diagonal: [1, 2, 3, 1])
    model.camera.target = [4, 5, 6]
    model.renderSettings.showsGrid = false
    model.renderSettings.fieldOfView = 42
    model.gizmoMode = .scale
    model.gizmoSpace = .local
    model.isInspectorPresented = false
    // addShape selected B.
    let saved = model.editorState
    document.updateEditorState()

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try document.snapshot(contentType: .sceneSprocketsDocument).write(to: url, options: [], originalContentsURL: nil)
    let loaded = try ComposerDocument(contentsOf: url)
    #expect(loaded.editorState == saved)
    let reopened = EditorModel(sceneGraph: loaded.sceneGraph)
    reopened.apply(try #require(loaded.editorState))
    #expect(reopened.selectedNode?.label == "B")
    #expect(reopened.camera.target == [4, 5, 6])
    #expect(reopened.gizmo.mode == .scale)
    #expect(reopened.renderSettings.fieldOfView == 42)

    // A broken file falls back to nil (defaults); a partial one keeps what it has.
    try Data("not json".utf8).write(to: url.appendingPathComponent("editor.json"))
    #expect(try ComposerDocument(contentsOf: url).editorState == nil)
    try Data(#"{"renderSettings": {"showsGrid": false}}"#.utf8).write(to: url.appendingPathComponent("editor.json"))
    let partial = try #require(try ComposerDocument(contentsOf: url).editorState)
    #expect(partial.renderSettings.showsGrid == false)
    #expect(partial.renderSettings.showsAxes == true)
    #expect(partial.gizmoMode == .translate)
}

// #188
@MainActor
@Test func debugShapesDrawAndPickLightsAndCameras() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    for type in Light.LightType.allCases {
        model.addLight(type)
    }
    model.addCamera()
    let viewport = SceneViewport(
        cameraMatrix: LookAt(position: [0, 0, 20], target: .zero, up: [0, 1, 0]).cameraMatrix,
        projectionMatrix: PerspectiveProjection(verticalAngleOfView: .degrees(60)).projectionMatrix(aspectRatio: 1),
        viewSize: [400, 400],
        drawableSize: [800, 800]
    )
    let shapes = DebugShapes.shapes(sceneGraph: model.sceneGraph, viewport: viewport)
    #expect(shapes.count == 4)
    #expect(shapes.allSatisfy { !$0.lines.isEmpty })

    // Only a camera, at the origin facing -Z (away from the viewer): its frustum outline surrounds the center.
    let cameraOnly = SceneGraph.empty()
    let camera = SceneGraph.Node(parent: cameraOnly.root, label: "Camera", content: .camera(SceneView.defaultCamera))
    let shape = try #require(DebugShapes.shapes(sceneGraph: cameraOnly, viewport: viewport).first)
    let projected = try #require(viewport.project(shape.lines[1][1]))
    #expect(DebugShapes.hitTest(projected.xy, sceneGraph: cameraOnly, viewport: viewport) === camera)
    #expect(DebugShapes.hitTest([5, 5], sceneGraph: cameraOnly, viewport: viewport) == nil)
    #expect(try DebugShapes.element(sceneGraph: cameraOnly, selected: [camera.id], viewport: viewport) != nil)
}

// #189
@MainActor
@Test func largeGizmoScalesWorldSize() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let small = try #require(model.gizmo.worldSize)
    model.gizmoSize = .large
    #expect(model.gizmo.worldSize == small * GizmoSize.large.scale)
    model.gizmoSize = .small
    #expect(model.gizmo.worldSize == small)
}

// #81: every + menu shape builds geometry; the star's path string must parse.
@Test func everyAddMenuShapeHasGeometry() {
    for kind in ShapeKind.allCases {
        #expect(!kind.shape.mesh().positions.isEmpty, "\(kind.label)")
    }
}

// #192
@MainActor
@Test func lockedNodesCannotBePickedMovedOrDeleted() throws {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    document.editorModel = model
    model.addShape(.box(), label: "Parent")
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let parent = try #require(model.selectedNode)
    let child = SceneGraph.Node(parent: parent, label: "Child")

    undoManager.beginUndoGrouping()
    model.setLocked(true, parent)
    undoManager.endUndoGrouping()
    #expect(model.isLocked(child))
    // Selected in the tree, but the gizmo lets go and delete is refused.
    #expect(model.gizmo.target == nil)
    #expect(!model.canDeleteSelection)
    model.deleteSelection()
    #expect(parent.parent != nil)
    // Viewport picks skip it.
    model.pick(child)
    #expect(model.selection == nil)
    model.selection = child.id
    #expect(model.gizmo.target == nil)

    // Saved and restored by path.
    document.updateEditorState()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try document.snapshot(contentType: .sceneSprocketsDocument).write(to: url, options: [], originalContentsURL: nil)
    let loaded = try ComposerDocument(contentsOf: url)
    let reopened = EditorModel(sceneGraph: loaded.sceneGraph)
    reopened.apply(try #require(loaded.editorState))
    #expect(reopened.isLocked(try #require(loaded.sceneGraph.root.children.first)))

    undoManager.undo()
    #expect(!model.isLocked(child))
    model.pick(child)
    #expect(model.gizmo.target === child)
}

// #193
@MainActor
@Test func hidingRemovesSubtreeAndUndoes() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Parent")
    let parent = try #require(model.selectedNode)
    let child = SceneGraph.Node(parent: parent, label: "Child")
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager

    undoManager.beginUndoGrouping()
    model.setVisible(false, parent)
    undoManager.endUndoGrouping()
    #expect(model.isHidden(child))
    #expect(model.sceneGraph.bounds == nil)
    #expect(model.sceneGraph.hitTest(Ray3D(origin: [0, 0, 5], direction: [0, 0, -1])).isEmpty)
    undoManager.undo()
    #expect(!model.isHidden(child))
    #expect(model.sceneGraph.hitTest(Ray3D(origin: [0, 0, 5], direction: [0, 0, -1])).first?.node === parent)
}

// #190: a conversation only with credentials for the selected backend.
@MainActor
@Test func assistantNeedsCredentials() {
    let signedOut = CollaborationCredentials(store: InMemoryCredentialStore(), backends: [.anthropicAPI], defaultsKey: nil)
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    #expect(ComposerAssistant.makeStore(credentials: signedOut, model: model) == nil)
    let signedIn = CollaborationCredentials(store: InMemoryCredentialStore(anthropicAPIKey: "test-key"), backends: [.anthropicAPI], defaultsKey: nil)
    let store = ComposerAssistant.makeStore(credentials: signedIn, model: model)
    #expect(store != nil)
    store?.cancel()
}

// #191, #202: the scene tools, called directly as the model would.
@MainActor
@Test func sceneToolsQueryAndEditTheScene() async throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    #expect(Set(tools.collaborationTools.map(\.name)) == ["query", "select", "create", "update", "delete", "setEnvironment", "dropToFloor"])

    let group = try tools.create(kind: "Box", count: nil, label: "Group", parent: nil, translation: [0, 1, 0], translations: nil, rotationDegrees: nil, scale: nil, color: nil)
    let ball = try tools.create(kind: "sphere", count: nil, label: "Ball", parent: group, translation: [1, 2, 3], translations: nil, rotationDegrees: [0, 30, 0], scale: nil, color: [1, 0, 0])
    let lamp = try tools.create(kind: "point light", count: nil, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil)
    #expect([group, ball, lamp] == ["n1", "n2", "n3"])
    let ballNode = try tools.node(id: ball)
    #expect(ballNode.parent === (try tools.node(id: group)))
    #expect(ballNode.localTransform.trs.translation == [1, 2, 3])
    #expect(abs(SceneTools.eulerDegrees(ballNode.localTransform.trs.rotation).y - 30) < 0.01)
    #expect(EditorModel.baseColor(of: try #require(model.materials(of: ballNode).first)) == [1, 0, 0])

    let scene = try tools.query()
    #expect(scene.contains(#""id":"n2""#) && scene.contains(#""parent":"n1""#) && scene.contains(#""selection":["n3"]"#))
    // At gimbal lock the angles must stay finite, or query's JSON fails.
    let locked = SceneTools.eulerDegrees(SceneTools.rotation(eulerDegrees: [0, 90, 0]))
    #expect(locked.x.isFinite && locked.y.isFinite && locked.z.isFinite)

    // Several nodes at once; reparenting to the root.
    _ = try tools.update(ids: [group, ball], label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: [2, 2, 2], color: nil, metallic: nil, roughness: nil, isVisible: false, isActive: nil)
    #expect(ballNode.localTransform.trs.scale == [2, 2, 2] && !ballNode.isVisible)
    _ = try tools.update(ids: [ball], label: nil, parent: "root", translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil)
    #expect(ballNode.parent === model.sceneGraph.root)
    _ = try tools.select(ids: [ball])
    #expect(model.selectedNode === ballNode)

    #expect(throws: ToolError.self) { try tools.update(ids: [group], label: nil, parent: group, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil) }
    #expect(throws: ToolError.self) { try tools.create(kind: "dodecahedron", count: nil, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil) }
    #expect(throws: ToolError.self) { try tools.update(ids: [lamp], label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: [1, 1, 1], metallic: nil, roughness: nil, isVisible: nil, isActive: nil) }
    model.setLocked(true, ballNode)
    #expect(throws: ToolError.self) { try tools.delete(ids: [ball]) }
    model.setLocked(false, ballNode)
    _ = try tools.delete(ids: [ball, lamp])
    #expect(throws: ToolError.self) { try tools.node(id: ball) }
    #expect(model.sceneGraph.root.children.count == 1)
}

// #198
@MainActor
@Test func materialEditsApplyAsValues() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let blinnPhong = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.2, 0.4, 0.6]), specular: .color(0.5), shininess: 32)

    // Kind: converts keeping the color; no change when already that kind.
    let pbr = try #require(try MaterialEdit.applying([.kind(.pbr)], to: blinnPhong, device: device) as? PBRSceneMaterial)
    #expect(EditorModel.baseColor(of: pbr) == [0.2, 0.4, 0.6])
    #expect(try MaterialEdit.applying([.kind(.blinnPhong)], to: blinnPhong, device: device) == nil)

    // Edits that do not fit the material are skipped.
    #expect(try MaterialEdit.applying([.uniforms { $0.roughnessFactor = 1 }, .doubleSided(true)], to: blinnPhong, device: device) == nil)
    var textured = blinnPhong
    textured.diffuse = .texture(try #require(device.makeTexture(descriptor: .texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false))))
    #expect(try MaterialEdit.applying([.baseColor([1, 0, 0])], to: textured, device: device) == nil)

    // Several PBR edits make one copy that keeps the textures and leaves the original alone.
    let edited = try #require(try MaterialEdit.applying([.uniforms { $0.roughnessFactor = 0.9 }, .doubleSided(true), .baseColor([1, 0, 0])], to: pbr, device: device) as? PBRSceneMaterial)
    #expect(edited.pbrMaterial.uniforms.roughnessFactor == 0.9)
    #expect(edited.pbrMaterial.doubleSided)
    #expect(edited.pbrMaterial.uniforms.baseColorFactor == [1, 0, 0, 1])
    #expect(pbr.pbrMaterial.uniforms.roughnessFactor == 0.5)
    #expect(zip(edited.pbrMaterial.textureBindings, pbr.pbrMaterial.textureBindings).allSatisfy { $0.texture === $1.texture })

    // Presets use the color set before them; glass stays clear white.
    let metal = try #require(try MaterialEdit.applying([.baseColor([1, 0, 0]), .preset(.metal)], to: blinnPhong, device: device) as? PBRSceneMaterial)
    #expect(metal.pbrMaterial.uniforms.metallicFactor == 1)
    #expect(metal.pbrMaterial.uniforms.baseColorFactor == [1, 0, 0, 1])
    let glass = try #require(try MaterialEdit.applying([.baseColor([1, 0, 0]), .preset(.glass)], to: blinnPhong, device: device) as? PBRSceneMaterial)
    #expect(glass.pbrMaterial.uniforms.transmissionFactor == 1)
    #expect(glass.pbrMaterial.uniforms.baseColorFactor == [1, 1, 1, 1])
}

// #197
@MainActor
@Test func insertModelAddsUnderSelectionAsOneUndoStep() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Box")
    let box = try #require(model.selectedNode)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).obj")
    defer { try? FileManager.default.removeItem(at: url) }
    try "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".write(to: url, atomically: true, encoding: .utf8)

    undoManager.beginUndoGrouping()
    try model.insertModel(from: url)
    undoManager.endUndoGrouping()
    let inserted = try #require(model.selectedNode)
    #expect(inserted.parent === box)
    #expect(inserted.label == url.deletingPathExtension().lastPathComponent)
    undoManager.undo()
    #expect(box.children.isEmpty)

    // A locked selection sends it to the root instead.
    model.selection = box.id
    undoManager.beginUndoGrouping()
    model.setLocked(true, box)
    try model.insertModel(from: url)
    undoManager.endUndoGrouping()
    #expect(model.selectedNode?.parent === model.sceneGraph.root)
}

// #158: an inserted model's meshes are saved with the document.
@MainActor
@Test func insertedMeshesAreSavedWithTheDocument() throws {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    let obj = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).obj")
    defer { try? FileManager.default.removeItem(at: obj) }
    try "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".write(to: obj, atomically: true, encoding: .utf8)
    try model.insertModel(from: obj)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try document.snapshot(contentType: .sceneSprocketsDocument).write(to: url, options: [], originalContentsURL: nil)
    let loaded = try ComposerDocument(contentsOf: url)
    let vertexCounts = loaded.sceneGraph.nodesWithWorldTransforms(includeHidden: true).compactMap { entry -> Int? in
        if case let .mesh(mesh, _, _, _) = entry.node.content { mesh.vertexCount } else { nil }
    }
    #expect(vertexCounts == [3])
}

// #157: an inserted glTF is one unit: its inside is locked, a click picks the model, and saving keeps the file.
@MainActor
@Test func insertedGLTFIsKeptByReference() throws {
    let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    let indices: [UInt16] = [0, 1, 2, 0]
    let buffer = (positions.withUnsafeBytes { Data($0) } + indices.withUnsafeBytes { Data($0) }).base64EncodedString()
    let json = """
    {"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"Tri","mesh":0}],
    "meshes":[{"primitives":[{"attributes":{"POSITION":0},"indices":1}]}],
    "accessors":[{"bufferView":0,"componentType":5126,"count":3,"type":"VEC3","max":[1,1,0],"min":[0,0,0]},
    {"bufferView":1,"componentType":5123,"count":3,"type":"SCALAR"}],
    "bufferViews":[{"buffer":0,"byteLength":36},{"buffer":0,"byteOffset":36,"byteLength":6}],
    "buffers":[{"byteLength":44,"uri":"data:application/octet-stream;base64,\(buffer)"}]}
    """
    let gltf = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    defer { try? FileManager.default.removeItem(at: gltf) }
    try json.write(to: gltf, atomically: true, encoding: .utf8)

    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    try model.insertModel(from: gltf)
    let root = try #require(model.selectedNode)
    #expect(root.modelSource != nil)
    let inside = try #require(model.sceneGraph.nodesWithWorldTransforms(includeHidden: true).map(\.node).first { $0 !== root && root.isAncestor(of: $0) })
    #expect(model.isLocked(inside))
    #expect(!model.isLocked(root))
    model.selection = nil
    model.pick(inside)
    #expect(model.selectedNode === root)
    // Nothing can be added inside the model, which is saved as its file.
    #expect(!model.canAddChildren(to: root))
    model.addShape(.box(), label: "Box")
    let box = try #require(model.selectedNode)
    #expect(!model.reparent(box, to: root))
    model.selection = root.id
    try model.insertModel(from: gltf)
    #expect(model.selectedNode?.parent === model.sceneGraph.root)
    model.delete(try #require(model.selectedNode))
    model.delete(box)
    root.trs.translation = [2, 0, 0]

    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try document.snapshot(contentType: .sceneSprocketsDocument).write(to: url, options: [], originalContentsURL: nil)
    #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("models/0/\(gltf.lastPathComponent)").path))
    let loaded = try ComposerDocument(contentsOf: url)
    let loadedRoot = try #require(loaded.sceneGraph.root.children.first)
    #expect(loadedRoot.modelSource != nil)
    #expect(loadedRoot.trs.translation == [2, 0, 0])
    #expect(loaded.sceneGraph.meshEntries().count == 1)
}

// #196
@MainActor
@Test func deactivatingIsUndoableAndDimsTheSubtree() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Parent")
    let parent = try #require(model.selectedNode)
    let child = SceneGraph.Node(parent: parent, label: "Child")
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    undoManager.beginUndoGrouping()
    model.setActive(false, parent)
    undoManager.endUndoGrouping()
    #expect(model.isHidden(child))
    #expect(model.sceneGraph.bounds == nil)
    undoManager.undo()
    #expect(parent.isActive)
    #expect(!model.isHidden(child))
}

// #204: AppKit takes the snapshot on a background queue when saving on quit.
@MainActor
@Test func snapshotWorksOffTheMainThread() async throws {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    model.addShape(.box(), label: "Box")
    model.renderSettings.showsGrid = false
    document.attach(model)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    let wasOffMain = try await Task.detached {
        let wrapper = try document.snapshot(contentType: .sceneSprocketsDocument)
        try wrapper.write(to: url, options: [], originalContentsURL: nil)
        return pthread_main_np() == 0
    }.value
    #expect(wasOffMain)
    let loaded = try ComposerDocument(contentsOf: url)
    #expect(loaded.editorState?.renderSettings.showsGrid == false)
    #expect(loaded.sceneGraph.root.children.first?.label == "Box")
    #expect(DocumentPreview.image(inBundleAt: url) != nil)
}

// #200: repeated work in one call.
@MainActor
@Test func sceneToolsBatchCreateAndUpdate() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "sphere", count: 8, label: "Ball", parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: [0, 0, 1]).components(separatedBy: ", ")
    #expect(ids.count == 8)
    #expect(model.sceneGraph.root.children.map(\.label) == (1...8).map { "Ball \($0)" })

    // Distribute along x with one call.
    let positions = (0..<8).map { [Double($0) * 2, 0, 0] }
    _ = try tools.update(ids: ids, label: nil, parent: nil, translation: nil, translations: positions, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil)
    #expect(model.sceneGraph.root.children.map { $0.localTransform.trs.translation.x } == [0, 2, 4, 6, 8, 10, 12, 14])

    // translations alone sets the count.
    let row = try tools.create(kind: "box", count: nil, label: nil, parent: nil, translation: nil, translations: [[0, 3, 0], [1, 3, 0]], rotationDegrees: nil, scale: nil, color: nil)
    #expect(row.components(separatedBy: ", ").count == 2)

    #expect(throws: ToolError.self) { try tools.create(kind: "box", count: 3, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0]], rotationDegrees: nil, scale: nil, color: nil) }
    #expect(throws: ToolError.self) { try tools.create(kind: "box", count: 0, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil) }
    #expect(throws: ToolError.self) { try tools.update(ids: ids, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0]], rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil) }
}

// #201: multiple selection in the model, the tools and delete; "align the selected objects" in two calls.
@MainActor
@Test func multipleSelectionForSelectionAwareEdits() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 3, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0], [2, 1, 0], [4, 3, 0]], rotationDegrees: nil, scale: nil, color: nil).components(separatedBy: ", ")
    let nodes = try ids.map { try tools.node(id: $0) }

    // Click, then shift-click twice: the last one is primary; shift-clicking it again removes it.
    model.pick(nodes[0])
    model.pick(nodes[2], extending: true)
    #expect(model.selectedIDs == [nodes[0].id, nodes[2].id] && model.selection == nodes[2].id)
    #expect(model.gizmo.target === nodes[2])
    model.pick(nodes[2], extending: true)
    #expect(model.selectedIDs == [nodes[0].id] && model.selection == nodes[0].id)
    // A plain click replaces it.
    model.pick(nodes[1])
    #expect(model.selectedIDs == [nodes[1].id])

    // The assistant sees and sets the whole selection; aligning is one update.
    _ = try tools.select(ids: [ids[0], ids[1], ids[2]])
    #expect(try tools.query().contains(#""selection":["n1","n2","n3"]"#))
    _ = try tools.update(ids: ids, label: nil, parent: nil, translation: nil, translations: nodes.map { [Double($0.localTransform.trs.translation.x), 0, 0] }, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil)
    #expect(nodes.allSatisfy { $0.localTransform.trs.translation.y == 0 })

    // Delete removes every selected node.
    model.select([nodes[0].id, nodes[1].id])
    model.deleteSelection()
    #expect(model.sceneGraph.root.children.map(\.label) == [nodes[2].label])
    #expect(model.selectedIDs.isEmpty && model.selection == nil)
}

// #199
@MainActor
@Test func sceneToolsReadAndSetTheEnvironment() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let tools = SceneTools(model: model)
    #expect(try tools.query().contains(#""environment":{"#))

    undoManager.beginUndoGrouping()
    _ = try tools.setEnvironment(background: nil, backgroundColor: [0, 0, 1], backgroundBlur: nil, map: "studio", intensity: 2, rotationDegrees: 90)
    undoManager.endUndoGrouping()
    guard case let .color(color) = model.environment.background else {
        Issue.record("expected a color background")
        return
    }
    #expect(color == [0, 0, 1, 1])
    #expect(model.environment.map === PBREnvironment.studio)
    #expect(model.environment.intensity == 2)
    #expect(abs(model.environment.rotation - .pi / 2) < 1e-5)
    #expect(try tools.query().contains(#""map":"studio""#))

    undoManager.beginUndoGrouping()
    _ = try tools.setEnvironment(background: "environment", backgroundColor: nil, backgroundBlur: 0.5, map: nil, intensity: nil, rotationDegrees: nil)
    undoManager.endUndoGrouping()
    #expect(try tools.query().contains(#""backgroundBlur":0.5"#))
    #expect(throws: ToolError.self) { try tools.setEnvironment(background: "sky", backgroundColor: nil, backgroundBlur: nil, map: nil, intensity: nil, rotationDegrees: nil) }
    #expect(throws: ToolError.self) { try tools.setEnvironment(background: nil, backgroundColor: nil, backgroundBlur: nil, map: "/tmp/x.hdr", intensity: nil, rotationDegrees: nil) }

    undoManager.undo()
    undoManager.undo()
    guard case .none = model.environment.background else {
        Issue.record("undo should restore the default background")
        return
    }
}

// #216: per-node labels and colors, so varied repeated work also fits in one call; the schema exposes them and the
// descriptions lead with batching.
@MainActor
@Test func sceneToolsBatchLabelsAndColors() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "sphere", count: nil, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0], [2, 0, 0], [4, 0, 0]], rotationDegrees: nil, scale: nil, color: nil, labels: ["Red", "Green", "Blue"], colors: [[1, 0, 0], [0, 1, 0], [0, 0, 1]]).components(separatedBy: ", ")
    let nodes = try ids.map { try tools.node(id: $0) }
    #expect(nodes.map(\.label) == ["Red", "Green", "Blue"])
    #expect(try nodes.map { EditorModel.baseColor(of: try #require(model.materials(of: $0).first)) } == [[1, 0, 0], [0, 1, 0], [0, 0, 1]])
    _ = try tools.update(ids: ids, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil, labels: ["A", "B", "C"], colors: [[0, 0, 0], [0.5, 0.5, 0.5], [1, 1, 1]])
    #expect(nodes.map(\.label) == ["A", "B", "C"])
    #expect(throws: ToolError.self) { try tools.create(kind: "box", count: 2, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, labels: ["Only one"], colors: nil) }

    let create = try #require(tools.collaborationTools.first { $0.name == "create" })
    let schema = String(describing: create.inputSchema)
    #expect(schema.contains("labels") && schema.contains("colors"))
    #expect(create.description.hasPrefix("Use one call"))
    let update = try #require(tools.collaborationTools.first { $0.name == "update" })
    #expect(update.description.hasPrefix("Use one call"))
}

// #217: 'make these glass' — presets and transmission/IOR through the tools, on Blinn-Phong and PBR nodes alike.
@MainActor
@Test func sceneToolsMakeThingsGlass() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    // New shapes are Blinn-Phong, which has no transmission, so a preset must switch them to PBR.
    let ids = try tools.create(kind: "sphere", count: 2, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: [1, 0, 0]).components(separatedBy: ", ")
    _ = try tools.update(ids: ids, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil, preset: "glass")
    for id in ids {
        let material = try #require(model.materials(of: try tools.node(id: id)).first as? PBRSceneMaterial)
        #expect(material.pbrMaterial.uniforms.transmissionFactor == 1)
    }
    // Fine control: transmission and IOR directly.
    _ = try tools.update(ids: [ids[0]], label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil, transmission: 0.5, ior: 1.33)
    let water = try #require(model.materials(of: try tools.node(id: ids[0])).first as? PBRSceneMaterial)
    #expect(water.pbrMaterial.uniforms.transmissionFactor == 0.5 && water.pbrMaterial.uniforms.ior == 1.33)
    // Metal keeps the color.
    _ = try tools.update(ids: [ids[1]], label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: [0, 0, 1], metallic: nil, roughness: nil, isVisible: nil, isActive: nil, preset: "metal")
    let metal = try #require(model.materials(of: try tools.node(id: ids[1])).first as? PBRSceneMaterial)
    #expect(metal.pbrMaterial.uniforms.metallicFactor == 1 && metal.pbrMaterial.uniforms.baseColorFactor == [0, 0, 1, 1])
    #expect(throws: ToolError.self) { try tools.update(ids: [ids[0]], label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil, preset: "jelly") }
    // Presets are offered by create too.
    let glass = try tools.create(kind: "box", count: nil, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil, preset: "glass")
    let glassMaterial = try #require(model.materials(of: try tools.node(id: glass)).first as? PBRSceneMaterial)
    #expect(glassMaterial.pbrMaterial.uniforms.transmissionFactor == 1)
}

// #218: the system prompt names every tool and covers the points the issue asks for.
@MainActor
@Test func systemPromptCoversToolsAndGuidance() {
    let prompt = ComposerAssistant.systemPrompt
    let tools = SceneTools(model: EditorModel(sceneGraph: SceneGraph.empty()))
    for name in tools.collaborationTools.map(\.name) {
        #expect(prompt.contains("- \(name):"), "\(name) is not described")
    }
    for topic in ["dropToFloor after", "never stack them", "prefer PBR", "preset glass", "key light", "Shadows", "one call"] {
        #expect(prompt.contains(topic), "\(topic)")
    }
}

// #203
@MainActor
@Test func assistantTurnIsOneUndoStep() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let tools = SceneTools(model: model)
    let turn = AssistantTurnUndo(model: model)

    undoManager.beginUndoGrouping()
    turn.begin()
    var ids: [String] = []
    for _ in 0..<3 {
        ids.append(try tools.create(kind: "box", count: nil, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil))
    }
    _ = try tools.update(ids: [ids[0]], label: nil, parent: nil, translation: [1, 0, 0], translations: nil, rotationDegrees: nil, scale: nil, color: nil, metallic: nil, roughness: nil, isVisible: nil, isActive: nil)
    turn.end()
    undoManager.endUndoGrouping()
    #expect(model.undoManager === undoManager)
    #expect(model.sceneGraph.root.children.count == 3)
    #expect(undoManager.undoActionName == AssistantTurnUndo.actionName)

    undoManager.undo()
    #expect(model.sceneGraph.root.children.isEmpty)
    #expect(!undoManager.canUndo)
    undoManager.redo()
    #expect(model.sceneGraph.root.children.count == 3)
    #expect(model.sceneGraph.root.children.first?.localTransform.trs.translation == [1, 0, 0])
    undoManager.undo()
    #expect(model.sceneGraph.root.children.isEmpty)

    // A turn that changes nothing adds no step.
    undoManager.redo()
    turn.begin()
    _ = try tools.query()
    turn.end()
    undoManager.undo()
    #expect(model.sceneGraph.root.children.isEmpty)
}

// #206: one line per distinct problem with a count, not one full NSError per primitive.
@Test func insertWarningsAreSummarized() {
    let error = #"Error Domain=NSCocoaErrorDomain Code=257 "The file “glass_of_water.bin” couldn’t be opened because you don’t have permission to view it." UserInfo={NSFilePath=/Users/x/glass_of_water.bin, NSUnderlyingError=0x7b40d5ec10 {Error Domain=NSPOSIXErrorDomain Code=1 "Operation not permitted"}}"#
    let warnings = (0..<17).map { "Skipped \(String(format: "%02d", $0))_Water[0]: \(error)" } + ["No camera"]
    let summary = InsertWarnings.summary(warnings)
    #expect(summary.count == 2)
    #expect(summary[0] == "17 \u{00D7} The file “glass_of_water.bin” couldn’t be opened because you don’t have permission to view it.")
    #expect(summary[1] == "No camera")
    // Capped, with a note for the rest.
    let many = InsertWarnings.summary((0..<20).map { "Problem \($0)" })
    #expect(many.count == InsertWarnings.maximumLines + 1)
    #expect(many.last == "and 12 more (see the log)")
}

// #208: every parameter in the list edits through editedPBR, keeps textures, and leaves the original alone.
@MainActor
@Test func everyPBRParameterIsEditable() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let original = try PBRSceneMaterial(device: device)
    for parameter in PBRParameters.scalars {
        let before = original.pbrMaterial.uniforms[keyPath: parameter.keyPath]
        let value = parameter.range.lowerBound + (parameter.range.upperBound - parameter.range.lowerBound) * 0.37
        let edited = try EditorModel.editedPBR(original, device: device) { $0[keyPath: parameter.keyPath] = value }
        #expect(edited.pbrMaterial.uniforms[keyPath: parameter.keyPath] == value, "\(parameter.name)")
        #expect(original.pbrMaterial.uniforms[keyPath: parameter.keyPath] == before, "\(parameter.name)")
        #expect(parameter.range.lowerBound < parameter.range.upperBound)
    }
    for parameter in PBRParameters.colors {
        let edited = try EditorModel.editedPBR(original, device: device) { $0[keyPath: parameter.keyPath] = [0.1, 0.2, 0.3] }
        #expect(edited.pbrMaterial.uniforms[keyPath: parameter.keyPath] == [0.1, 0.2, 0.3], "\(parameter.name)")
    }
    for parameter in PBRParameters.toggles {
        let edited = try EditorModel.editedPBR(original, device: device) { $0[keyPath: parameter.keyPath] = 1 }
        #expect(edited.pbrMaterial.uniforms[keyPath: parameter.keyPath] == 1, "\(parameter.name)")
    }
    let doubleSided = try EditorModel.editedPBR(original, device: device, doubleSided: !original.pbrMaterial.doubleSided)
    #expect(doubleSided.pbrMaterial.doubleSided != original.pbrMaterial.doubleSided)
    // Names are unique within the list, which the inspector's ForEach needs.
    let names = PBRParameters.scalars.map(\.name) + PBRParameters.colors.map(\.name) + PBRParameters.toggles.map(\.name)
    #expect(Set(names).count == names.count)
    // 24 floats, 6 colors and 3 flags, plus base color, alpha mode, attenuation distance and double-sided in the view.
    #expect((PBRParameters.scalars.count, PBRParameters.colors.count, PBRParameters.toggles.count) == (24, 6, 3))
}

// #207: editor rows and node selection exclude each other; default lighting is active only without scene lights.
@MainActor
@Test func defaultCameraAndLightingRows() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Box")
    let box = try #require(model.selectedNode)
    model.editorItem = .defaultCamera
    #expect(model.selection == nil && model.selectedIDs.isEmpty)
    model.selection = box.id
    #expect(model.editorItem == nil)

    #expect(model.isDefaultLightingActive)
    model.addLight(.point)
    #expect(!model.isDefaultLightingActive)
    model.renderSettings.usesDefaultLighting = false
    #expect(!model.isDefaultLightingActive)
}

// #205
@MainActor
@Test func multipleSelectionGizmoInspectorAndSaving() throws {
    let document = ComposerDocument()
    let model = EditorModel(sceneGraph: document.sceneGraph)
    document.editorModel = model
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 3, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0], [2, 0, 0], [4, 0, 0]], rotationDegrees: nil, scale: nil, color: nil).components(separatedBy: ", ")
    let nodes = try ids.map { try tools.node(id: $0) }
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    model.select([nodes[0].id, nodes[1].id], primary: nodes[0].id)

    // Gizmo drag on the primary: the other selected node follows; the unselected one does not.
    undoManager.beginUndoGrouping()
    model.beginGizmoDrag(nodes[0])
    nodes[0].localTransform = .trs(.init(translation: [0, 1, 0]))
    model.continueGizmoDrag(nodes[0])
    model.endGizmoDrag(nodes[0])
    undoManager.endUndoGrouping()
    #expect(nodes[1].localTransform.trs.translation == [2, 1, 0])
    #expect(nodes[2].localTransform.trs.translation == [4, 0, 0])
    undoManager.undo()
    #expect(nodes[0].localTransform.trs.translation == .zero)
    #expect(nodes[1].localTransform.trs.translation == [2, 0, 0])

    // Shared inspector edits apply to every selected node as one step.
    undoManager.beginUndoGrouping()
    model.editSelection("Visibility") { model, node in model.setVisible(false, node) }
    model.editSelection("Color") { model, node in model.setBaseColor([1, 0, 0], of: node) }
    undoManager.endUndoGrouping()
    #expect(!nodes[0].isVisible && !nodes[1].isVisible && nodes[2].isVisible)
    #expect(EditorModel.baseColor(of: try #require(model.materials(of: nodes[1]).first)) == [1, 0, 0])

    // The whole selection is saved, primary last.
    model.select([nodes[0].id, nodes[2].id], primary: nodes[2].id)
    document.updateEditorState()
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try document.snapshot(contentType: .sceneSprocketsDocument).write(to: url, options: [], originalContentsURL: nil)
    let loaded = try ComposerDocument(contentsOf: url)
    let reopened = EditorModel(sceneGraph: loaded.sceneGraph)
    reopened.apply(try #require(loaded.editorState))
    #expect(reopened.selectedIDs.count == 2)
    #expect(reopened.selectedNode === loaded.sceneGraph.root.children[2])
}

// #209: light edits are undoable; the cone angles keep inner at or below outer.
@MainActor
@Test func lightEditing() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addLight(.spot)
    let node = try #require(model.selectedNode)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    guard case .light(let original) = node.content else {
        Issue.record("not a light")
        return
    }
    var edited = original
    edited.color = [1, 0.5, 0]
    edited.intensity = 7
    edited.range = 12
    undoManager.beginUndoGrouping()
    model.setLight(edited, of: node)
    undoManager.endUndoGrouping()
    guard case .light(let stored) = node.content else {
        Issue.record("not a light")
        return
    }
    #expect(stored == edited)
    undoManager.undo()
    guard case .light(let restored) = node.content else {
        Issue.record("not a light")
        return
    }
    #expect(restored == original)

    let cone = Light.spot(innerConeAngle: 0.2, outerConeAngle: 0.4)
    let widerInner = LightEditing.settingCone(\.innerConeAngle, to: 0.6, of: cone)
    #expect(widerInner.innerConeAngle == 0.6 && widerInner.outerConeAngle == 0.6)
    let narrowerOuter = LightEditing.settingCone(\.outerConeAngle, to: 0.1, of: cone)
    #expect(narrowerOuter.innerConeAngle == 0.1 && narrowerOuter.outerConeAngle == 0.1)
    let fine = LightEditing.settingCone(\.outerConeAngle, to: 0.5, of: cone)
    #expect(fine.innerConeAngle == 0.2 && fine.outerConeAngle == 0.5)
}

// #210: bottoms land on y = 0, including rotated and nested nodes; one undo step; children of dropped nodes skipped.
@MainActor
@Test func dropToFloor() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 2, label: nil, parent: nil, translation: nil, translations: [[0, 3, 0], [2, -1, 0]], rotationDegrees: nil, scale: nil, color: nil).components(separatedBy: ", ")
    // A tilted box inside a raised, scaled parent.
    let parent = try tools.create(kind: "box", count: nil, label: "Parent", parent: nil, translation: [5, 4, 0], translations: nil, rotationDegrees: nil, scale: [2, 2, 2], color: nil)
    let child = try tools.create(kind: "box", count: nil, label: "Child", parent: parent, translation: [0, 1, 0], translations: nil, rotationDegrees: [45, 0, 0], scale: nil, color: nil)
    let nodes = try (ids + [parent, child]).map { try tools.node(id: $0) }
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager

    model.select([nodes[0].id, nodes[1].id, nodes[3].id])
    undoManager.beginUndoGrouping()
    model.dropSelectionToFloor()
    undoManager.endUndoGrouping()
    for node in [nodes[0], nodes[1], nodes[3]] {
        let bounds = try #require(model.sceneGraph.worldBounds(of: node))
        #expect(abs(bounds.min.y) < 1e-4, "\(node.label ?? "")")
    }
    #expect(nodes[0].localTransform.trs.translation.x == 0 && nodes[1].localTransform.trs.translation.x == 2)
    #expect(nodes[2].localTransform.trs.translation == [5, 4, 0])
    undoManager.undo()
    #expect(nodes[0].localTransform.trs.translation == [0, 3, 0])
    #expect(nodes[3].localTransform.trs.translation == [0, 1, 0])

    // Selecting the parent and its child drops the parent only; the child moves with it.
    model.select([nodes[2].id, nodes[3].id])
    undoManager.beginUndoGrouping()
    model.dropSelectionToFloor()
    undoManager.endUndoGrouping()
    #expect(nodes[3].localTransform.trs.translation == [0, 1, 0])
    #expect(abs(try #require(model.sceneGraph.worldBounds(of: nodes[2])).min.y) < 1e-4)
    undoManager.beginUndoGrouping()
    #expect(try tools.dropToFloor(ids: [ids[0]]).hasPrefix("Dropped"))
    undoManager.endUndoGrouping()
}

// #211
@MainActor
@Test func boundingBoxes() throws {
    let edges = BoundingBoxes.edges(BoundingBox3D(min: [0, 0, 0], max: [1, 2, 3]))
    #expect(edges.count == 12)
    #expect(edges.allSatisfy { start, end in (0..<3).filter { start[$0] != end[$0] }.count == 1 })

    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 3, label: nil, parent: nil, translation: nil, translations: nil, rotationDegrees: nil, scale: nil, color: nil).components(separatedBy: ", ")
    model.addLight(.point)
    let nodes = try ids.map { try tools.node(id: $0) }
    nodes[2].isVisible = false
    let selected: Set = [nodes[0].id]
    #expect(BoundingBoxes.nodes(mode: .none, sceneGraph: model.sceneGraph, selected: selected).isEmpty)
    #expect(BoundingBoxes.nodes(mode: .selected, sceneGraph: model.sceneGraph, selected: selected).map(\.node.id) == [nodes[0].id])
    // All meshes, but not lights or hidden nodes.
    let all = BoundingBoxes.nodes(mode: .all, sceneGraph: model.sceneGraph, selected: selected)
    #expect(all.map(\.node.id) == [nodes[0].id, nodes[1].id])
    #expect(all.map(\.isSelected) == [true, false])
}

// #213
@Test func folderAccessMessages() {
    let file = URL(fileURLWithPath: "/Models/glass_of_water.gltf")
    #expect(FolderAccessRequest(file: file, externalFileCount: 2).message == "glass_of_water.gltf loads 2 other files (buffers, textures) from its folder. macOS lets the app read them only if you choose that folder.")
    #expect(FolderAccessRequest(file: file, externalFileCount: 1).message.contains("1 other file "))
    #expect(FolderAccessRequest.cancelledMessage(file: file) == "glass_of_water.gltf was not inserted: its folder was not chosen.")
    #expect(FolderAccessRequest.wrongFolderMessage(file: file, folder: URL(fileURLWithPath: "/Other")) == "glass_of_water.gltf is not inside Other. Choose the folder that contains it.")
}

// #220: right-click picks what is under the pointer through the editor camera.
@MainActor
@Test func nodeUnderPointer() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Box")
    let box = try #require(model.selectedNode)
    model.camera.matrix = LookAt(position: [0, 0, 5], target: .zero, up: [0, 1, 0]).cameraMatrix
    let size = SIMD2<Float>(800, 600)
    #expect(model.node(at: size / 2, viewSize: size) === box)
    #expect(model.node(at: [5, 5], viewSize: size) == nil)
    #expect(model.node(at: [5, 5], viewSize: .zero) == nil)
}

// #221: group and ungroup keep world positions, undo as one step each, and skip nested picks.
@MainActor
@Test func groupAndUngroup() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 3, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0], [4, 0, 0], [2, 2, 0]], rotationDegrees: nil, scale: nil, color: nil).components(separatedBy: ", ")
    let nodes = try ids.map { try tools.node(id: $0) }
    let worlds = nodes.map(\.worldTransform)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager

    model.select([nodes[0].id, nodes[1].id])
    undoManager.beginUndoGrouping()
    model.groupSelection()
    undoManager.endUndoGrouping()
    let group = try #require(model.selectedNode)
    #expect(group.label == "Group" && group.parent === model.sceneGraph.root)
    #expect(group.children.map(\.id) == [nodes[0].id, nodes[1].id])
    #expect(group.localTransform.trs.translation == [2, 0, 0])
    #expect(model.sceneGraph.root.children.map(\.id) == [group.id, nodes[2].id])
    for index in 0..<2 {
        #expect(simd_distance(nodes[index].worldTransform.columns.3, worlds[index].columns.3) < 1e-5)
    }

    undoManager.undo()
    #expect(model.sceneGraph.root.children.map(\.id) == nodes.map(\.id))
    #expect(simd_distance(nodes[1].worldTransform.columns.3, worlds[1].columns.3) < 1e-5)
    undoManager.redo()
    #expect(nodes[0].parent?.label == "Group")

    // Ungroup puts the children back where the group was, in order.
    let redone = try #require(nodes[0].parent)
    model.selection = redone.id
    #expect(model.canUngroupSelection)
    undoManager.beginUndoGrouping()
    model.ungroupSelection()
    undoManager.endUndoGrouping()
    #expect(model.sceneGraph.root.children.map(\.id) == nodes.map(\.id))
    #expect(model.selectedIDs == [nodes[0].id, nodes[1].id])
    for index in 0..<3 {
        #expect(simd_distance(nodes[index].worldTransform.columns.3, worlds[index].columns.3) < 1e-5)
    }
    // A box is not a group.
    model.selection = nodes[0].id
    #expect(!model.canUngroupSelection)
}

// #222: reorder among siblings, move before a node in another parent or into a group; world positions kept; undo
// restores the exact order (reparent's undo used to put a node one slot off within the same parent).
@MainActor
@Test func reorderNodes() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 3, label: nil, parent: nil, translation: nil, translations: [[0, 0, 0], [2, 0, 0], [4, 0, 0]], rotationDegrees: nil, scale: nil, color: nil, labels: ["A", "B", "C"]).components(separatedBy: ", ")
    let (a, b, c) = (try tools.node(id: ids[0]), try tools.node(id: ids[1]), try tools.node(id: ids[2]))
    let root = model.sceneGraph.root
    func order(_ node: SceneGraph.Node) -> [String] {
        node.children.compactMap(\.label)
    }
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    func step(_ work: () -> Void) {
        undoManager.beginUndoGrouping()
        work()
        undoManager.endUndoGrouping()
    }

    step { model.move(c, before: a) }
    #expect(order(root) == ["C", "A", "B"])
    undoManager.undo()
    #expect(order(root) == ["A", "B", "C"])

    model.selection = a.id
    step { model.moveSelection(by: 1) }
    #expect(order(root) == ["B", "A", "C"])
    step { model.moveSelection(by: -1) }
    #expect(order(root) == ["A", "B", "C"])
    step { model.moveSelection(by: -1) }
    #expect(order(root) == ["A", "B", "C"])

    // Into a group, and out again before a root node; world positions kept.
    model.select([b.id])
    step { model.groupSelection() }
    let group = try #require(b.parent)
    step { model.move(c, into: group) }
    #expect(order(group) == ["B", "C"])
    #expect(abs(c.worldTransform.columns.3.x - 4) < 1e-5)
    step { model.move(c, before: a) }
    #expect(order(root) == ["C", "A", "Group"])
    // No cycles: a group cannot go before its own child.
    #expect(!model.move(group, before: b))
    // Tree drops: onto a group goes inside, onto anything else goes before it.
    step { model.drop(a, onto: group) }
    #expect(order(group) == ["B", "A"])
    step { model.drop(a, onto: c) }
    #expect(order(root) == ["A", "C", "Group"])
}

// #225: per-axis toggles map to AxisLinesRenderPipeline.Axes and round-trip through editor.json.
@Test func axisLineToggles() throws {
    var settings = RenderSettings()
    #expect(settings.axes == .all)
    settings.showsYAxis = false
    #expect(settings.axes == [.x, .z])
    let decoded = try JSONDecoder().decode(RenderSettings.self, from: JSONEncoder().encode(settings))
    #expect(!decoded.showsYAxis && decoded.showsXAxis && decoded.showsZAxis)
    // Older files without the keys show all axes.
    #expect(try JSONDecoder().decode(RenderSettings.self, from: Data("{}".utf8)).axes == .all)
}

// #177: framing keeps the view direction and orbits the framed center.
@Test func framingKeepsViewDirection() {
    var camera = EditorCamera()
    let direction = simd_normalize(camera.matrix.columns.2)
    camera.frame(BoundingBox3D(min: [9, -1, -1], max: [11, 1, 1]), fieldOfView: 60)
    #expect(camera.target == [10, 0, 0])
    #expect(simd_distance(simd_normalize(camera.matrix.columns.2), direction) < 0.0001)
    let position = SIMD3<Float>(camera.matrix.columns.3.x, camera.matrix.columns.3.y, camera.matrix.columns.3.z)
    #expect(abs(simd_distance(position, camera.target) - simd_length(SIMD3<Float>(1, 1, 1)) / sin(Float.pi / 6) * 1.1) < 0.001)
}

// #186
@MainActor
@Test func addLightSelectsAndUndoes() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    for type in Light.LightType.allCases {
        undoManager.beginUndoGrouping()
        model.addLight(type)
        undoManager.endUndoGrouping()
        let node = try #require(model.selectedNode)
        guard case .light(let light) = node.content else {
            Issue.record("not a light")
            return
        }
        #expect(light.type == type)
        #expect(node.parent === model.sceneGraph.root)
        if type != .point {
            // Aimed down.
            #expect(node.localTransform.matrix.columns.2.y > 0)
        }
    }
    #expect(model.sceneGraph.root.children.count == 3)
    undoManager.undo()
    #expect(model.sceneGraph.root.children.count == 2)
}

// #187
@MainActor
@Test func addCameraUsesEditorCamera() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let undoManager = UndoManager()
    model.undoManager = undoManager
    model.addCamera()
    let node = try #require(model.selectedNode)
    guard case .camera = node.content else {
        Issue.record("not a camera")
        return
    }
    #expect(node.localTransform.matrix == model.camera.matrix)
    undoManager.undo()
    #expect(model.sceneGraph.root.children.isEmpty)
}

// #224: the inspectors' key-path properties write through the model's undoable setters.
@MainActor
@Test func inspectorPropertiesEditTheSelection() throws {
    let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
    model.addShape(.box(), label: "Box")
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let node = try #require(model.selectedNode)
    undoManager.beginUndoGrouping()
    model.selectedTRS.translation.x = 2
    model.selectedTRS.rotationDegrees[double: 1] = 30
    model.selectedLabel = ""
    model.selectedIsVisible = false
    model[environment: "Environment Rotation"].rotationDegrees = 90
    undoManager.endUndoGrouping()
    #expect(node.localTransform.trs.translation.x == 2)
    #expect(abs(model.selectedTRS.rotationDegrees.y - 30) < 0.01)
    #expect(node.label == nil)
    #expect(!model.isVisible(node))
    #expect(abs(model.environment.rotation - .pi / 2) < 0.0001)
    undoManager.undo()
    #expect(node.localTransform.trs.translation.x == 0)
    #expect(node.label == "Box")
    #expect(model.isVisible(node))
    #expect(model.environment.rotation == 0)
}

@MainActor
@Test func lightConePropertiesKeepInnerInsideOuter() {
    var light = Light(type: .spot, color: [1, 1, 1], intensity: 1)
    light.outerCone = .degrees(30)
    light.innerCone = .degrees(40)
    #expect(light.outerConeAngle == light.innerConeAngle)
    light.isRangeLimited = false
    #expect(light.range == .infinity)
    var message: String? = "x"
    message.isPresent = false
    #expect(message == nil)
}

// #226
@MainActor
@Test func selectionWorldBoundsCombinesSelectedNodes() throws {
    let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
    model.addShape(.box(), label: "A")
    model.addShape(.box(), label: "B")
    let a = try #require(model.sceneGraph.root.children.first)
    let b = try #require(model.sceneGraph.root.children.last)
    model.selection = a.id
    let single = try #require(model.selectionWorldBounds)
    let width = single.max.x - single.min.x
    #expect(width > 0)
    b.localTransform = .trs(Transform3D(translation: [3, 0, 0]))
    model.select([a.id, b.id], primary: a.id)
    let combined = try #require(model.selectionWorldBounds)
    #expect(abs((combined.max.x - combined.min.x) - (width + 3)) < 0.0001)
    model.addLight(.point)
    #expect(model.selectionWorldBounds == nil)
}
