import Interaction3D
import MetalSprockets
import SceneSprockets
import SceneSprocketsGizmos
import simd
import SwiftUI

struct ScenePreviewView: View {
    @Bindable var model: EditorModel
    @Environment(\.self)
    private var environment
    @Environment(\.displayScale)
    private var displayScale
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
            debugMode: settings.debugMode,
            materialChannel: settings.materialChannel,
            onTapAt: { point, viewport, hit in
                isFocused = true
                // Light and camera shapes are drawn on top, so they win over meshes behind them.
                let shapeHit = settings.showsLightsAndCameras ? DebugShapes.hitTest(point, sceneGraph: model.sceneGraph, viewport: viewport) : nil
                model.pick(shapeHit ?? hit?.node)
            },
            decorations: { [selectedNode = model.selectedNode, sceneGraph = model.sceneGraph, displayScale] context, drawableSize in
                let grid = try settings.decorations(context: context, drawableSize: drawableSize)
                guard settings.showsLightsAndCameras else {
                    return grid
                }
                // Sized in view points, like hit testing. The scene's reversed depth does not change x and y.
                let viewport = SceneViewport(cameraMatrix: context.cameraMatrix, projectionMatrix: context.projectionMatrix, viewSize: drawableSize / Float(displayScale), drawableSize: drawableSize)
                let shapes = try DebugShapes.element(sceneGraph: sceneGraph, selection: selectedNode, viewport: viewport)
                return try MetalSprockets.Group {
                    if let grid {
                        grid
                    }
                    if let shapes {
                        shapes
                    }
                }
                .eraseToAnyElement()
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
