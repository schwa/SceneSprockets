import Interaction3D
import SceneSprockets
import SceneSprocketsGizmos
import simd
import SwiftUI

struct ScenePreviewView: View {
    @Bindable var model: EditorModel
    @Environment(\.self)
    private var environment
    // Focused on click so Edit > Delete (the Delete key) reaches onDeleteCommand.
    @FocusState private var isFocused: Bool

    var body: some View {
        let settings = model.renderSettings
        // The drawable is not sRGB, so pass the gamma-encoded components.
        let accent = Color.accentColor.resolve(in: environment)
        let outlineColor = SIMD4<Float>(accent.red, accent.green, accent.blue, accent.opacity)
        // SceneView's camera control leaves drags that start on the gizmo to the gizmo.
        SceneView(
            sceneGraph: model.sceneGraph,
            options: settings.options.union(.allowsCameraControl),
            renderers: model.renderers,
            shadows: settings.shadows,
            cameraMatrix: Binding(get: { model.camera.matrix }, set: { model.camera.matrix = $0 ?? model.camera.matrix }),
            cameraTarget: model.camera.target,
            camera: settings.camera,
            manipulator: model.gizmo,
            onTap: { hit in
                isFocused = true
                model.selection = hit?.node.id
            },
            decorations: { context, drawableSize in
                try settings.decorations(context: context, drawableSize: drawableSize)
            },
            overlay: { [selectedNode = model.selectedNode, outline = model.selectionOutline, sceneGraph = model.sceneGraph] viewport in
                guard settings.outlinesSelection, let selectedNode else {
                    return nil
                }
                outline.color = outlineColor
                outline.width = 6
                return try outline.element(nodes: [selectedNode], sceneGraph: sceneGraph, viewport: viewport)
            }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        #if os(macOS)
        .onDeleteCommand {
            model.deleteSelection()
        }
        #endif
    }
}
