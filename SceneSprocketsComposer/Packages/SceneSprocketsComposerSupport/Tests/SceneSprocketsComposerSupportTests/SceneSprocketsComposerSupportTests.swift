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
@Test func newDocumentHasStarterContent() {
    let document = ComposerDocument()
    #expect(document.sceneGraph.root.children.map(\.label) == ["Floor", "Box", "Sun"])
}

@MainActor
@Test func transformChangeUndoes() throws {
    let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
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
    let wrapper = try document.snapshot(contentType: .sceneSprocketsDocument)
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("scenesprocketsd")
    defer { try? FileManager.default.removeItem(at: url) }
    try wrapper.write(to: url, options: [], originalContentsURL: nil)
    let loaded = try ComposerDocument(contentsOf: url)
    #expect(loaded.sceneGraph.root.children.map(\.label) == ["Floor", "Box", "Sun"])
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
