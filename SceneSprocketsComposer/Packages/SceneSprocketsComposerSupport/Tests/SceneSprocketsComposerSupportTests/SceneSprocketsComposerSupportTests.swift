import CoreGraphics
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
