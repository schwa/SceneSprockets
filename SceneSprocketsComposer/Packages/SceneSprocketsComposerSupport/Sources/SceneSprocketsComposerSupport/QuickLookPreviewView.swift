import SwiftUI

// Read-only scene preview for the Quick Look extension. The model is built the first time the body runs (#489).
public struct QuickLookPreviewView: View {
    private let document: ComposerDocument
    @State private var model = LazyState<EditorModel>()

    public init(document: ComposerDocument) {
        self.document = document
    }

    public var body: some View {
        ScenePreviewView(model: model.value { EditorModel(sceneGraph: document.sceneGraph) })
    }
}
