import Foundation
import SceneSprockets
@testable import SceneSprocketsComposerSupport
import Testing

// #491: a material edit that fails is reported to the user instead of being dropped.
@MainActor
@Test func failedMaterialEditIsReported() {
    struct Failure: LocalizedError {
        var errorDescription: String? { "The material could not be built." }
    }
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    #expect(model.materialEditError == nil)
    model.reportingMaterialEditErrors("Metal Material") {
        throw Failure()
    }
    #expect(model.materialEditError?.actionName == "Metal Material")
    #expect(model.materialEditError?.message == "The material could not be built.")

    model.materialEditError = nil
    model.reportingMaterialEditErrors("Color") {}
    #expect(model.materialEditError == nil)
}

// The edits the inspector makes go through the reporting path and still apply.
@MainActor
@Test func materialEditsStillApply() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Box")
    let node = try #require(model.selectedNode)
    model.setBaseColor([0, 1, 0], of: node)
    #expect(EditorModel.baseColor(of: try #require(model.materials(of: node).first)) == [0, 1, 0])
    #expect(model.materialEditError == nil)
}
