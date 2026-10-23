import Foundation
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
