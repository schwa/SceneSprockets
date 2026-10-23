import SwiftUI

// Read-only scene preview for the Quick Look extension.
public struct QuickLookPreviewView: View {
    @State private var model: EditorModel

    public init(document: ComposerDocument) {
        _model = State(initialValue: EditorModel(sceneGraph: document.sceneGraph))
    }

    public var body: some View {
        ScenePreviewView(model: model)
    }
}
