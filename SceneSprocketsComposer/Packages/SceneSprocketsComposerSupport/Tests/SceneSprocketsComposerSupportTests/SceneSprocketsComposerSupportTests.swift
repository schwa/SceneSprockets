import CollaborationKit
import CollaborationKitUI
import CoreGraphics
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

@MainActor
@Test func transformChangeUndoes() throws {
    let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
    model.addShape(.box(), label: "Box")
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let node = try #require(model.sceneGraph.root.children.first)
    let before = node.localTransform.matrix
    undoManager.beginUndoGrouping()
    model.setTransform(.matrix(.init(diagonal: [2, 2, 2, 1])), of: node, undoTo: node.localTransform)
    undoManager.endUndoGrouping()
    #expect(node.localTransform.matrix != before)
    undoManager.undo()
    #expect(node.localTransform.matrix == before)
    undoManager.redo()
    #expect(node.localTransform.matrix != before)
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
    #expect(try DebugShapes.element(sceneGraph: cameraOnly, selection: camera, viewport: viewport) != nil)
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
    #expect(ComposerAssistant.makeStore(credentials: signedOut) == nil)
    let signedIn = CollaborationCredentials(store: InMemoryCredentialStore(anthropicAPIKey: "test-key"), backends: [.anthropicAPI], defaultsKey: nil)
    let store = ComposerAssistant.makeStore(credentials: signedIn)
    #expect(store != nil)
    store?.cancel()
}

// #198
@MainActor
@Test func materialEditsReplaceAndUndo() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Box")
    let node = try #require(model.selectedNode)
    let undoManager = UndoManager()
    undoManager.groupsByEvent = false
    model.undoManager = undoManager
    let original = try #require(model.materials(of: node).first as? BlinnPhongSceneMaterial)

    // Blinn-Phong to PBR keeps the color.
    undoManager.beginUndoGrouping()
    model.setMaterial(try EditorModel.converted(original, to: .pbr, device: device), at: 0, of: node)
    undoManager.endUndoGrouping()
    let pbr = try #require(model.materials(of: node).first as? PBRSceneMaterial)
    #expect(EditorModel.baseColor(of: pbr) == EditorModel.baseColor(of: original))

    // PBR edits make a copy that keeps the textures and leaves the original alone.
    let edited = try EditorModel.editedPBR(pbr, device: device) { $0.roughnessFactor = 0.9 }
    #expect(edited.pbrMaterial.uniforms.roughnessFactor == 0.9)
    #expect(pbr.pbrMaterial.uniforms.roughnessFactor == 0.5)
    #expect(zip(edited.pbrMaterial.textureBindings, pbr.pbrMaterial.textureBindings).allSatisfy { $0.texture === $1.texture })

    // Presets.
    let metal = try MaterialPreset.metal.material(color: [1, 0, 0], device: device)
    #expect(metal.pbrMaterial.uniforms.metallicFactor == 1)
    #expect(metal.pbrMaterial.uniforms.baseColorFactor == [1, 0, 0, 1])
    #expect(try MaterialPreset.glass.material(color: [1, 0, 0], device: device).pbrMaterial.uniforms.transmissionFactor == 1)

    undoManager.undo()
    #expect(model.materials(of: node).first is BlinnPhongSceneMaterial)
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
