import Interaction3D
import MetalSprockets
import SceneSprockets
import SceneSprocketsGizmos
import simd
import SwiftUI

final class PointerTracker {
    var location: SIMD2<Float> = .zero
    var viewSize: SIMD2<Float> = .zero
}

struct ScenePreviewView: View {
    @Bindable var model: EditorModel
    @Environment(\.self)
    private var environment
    @Environment(\.displayScale)
    private var displayScale
    // Focused on click so Edit > Delete (the Delete key) reaches onDeleteCommand.
    @FocusState private var isFocused: Bool
    // The last pointer position and view size, for the context menu (#220). Not observed: it changes on every mouse
    // move, and nothing should redraw for that.
    @State private var pointer = PointerTracker()

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
            // A key-path binding, which SwiftUI can compare; a Binding(get:set:) is new on every pass (#223).
            cameraMatrix: $model.viewCameraMatrix,
            cameraTarget: model.camera.target,
            camera: settings.camera,
            manipulator: model.gizmo,
            debugMode: settings.debugMode,
            materialChannel: settings.materialChannel,
            onTapAt: { point, viewport, hit in
                isFocused = true
                // Light and camera shapes are drawn on top, so they win over meshes behind them.
                let shapeHit = settings.showsLightsAndCameras ? DebugShapes.hitTest(point, sceneGraph: model.sceneGraph, viewport: viewport) : nil
                // Shift-click adds to or removes from the selection (#201).
                model.pick(shapeHit ?? hit?.node, extending: Self.isExtendingSelection)
            },
            decorations: { [selectedIDs = model.selectedIDs, sceneGraph = model.sceneGraph, displayScale, accentColor = Color(.sRGB, red: Double(outlineColor.x), green: Double(outlineColor.y), blue: Double(outlineColor.z))] context, drawableSize in
                let grid = try settings.decorations(context: context, drawableSize: drawableSize)
                // Sized in view points, like hit testing. The scene's reversed depth does not change x and y.
                let viewport = SceneViewport(cameraMatrix: context.cameraMatrix, projectionMatrix: context.projectionMatrix, viewSize: drawableSize / Float(displayScale), drawableSize: drawableSize)
                let shapes = settings.showsLightsAndCameras ? try DebugShapes.element(sceneGraph: sceneGraph, selected: selectedIDs, viewport: viewport) : nil
                let boxes = try BoundingBoxes.element(mode: settings.boundingBoxes, sceneGraph: sceneGraph, selected: selectedIDs, selectedColor: accentColor, viewProjection: viewport.projectionMatrix * viewport.viewMatrix, drawableSize: drawableSize)
                guard shapes != nil || boxes != nil else {
                    return grid
                }
                return try MetalSprockets.Group {
                    if let grid {
                        grid
                    }
                    if let shapes {
                        shapes
                    }
                    if let boxes {
                        boxes
                    }
                }
                .eraseToAnyElement()
            },
            overlay: { [selectedNodes = model.selectedNodes, outline = model.selectionOutline, sceneGraph = model.sceneGraph] viewport in
                guard settings.outlinesSelection, !selectedNodes.isEmpty else {
                    return nil
                }
                outline.color = outlineColor
                outline.width = 6
                return try outline.element(nodes: selectedNodes, sceneGraph: sceneGraph, viewport: viewport)
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
        .onContinuousHover { phase in
            if case let .active(location) = phase {
                pointer.location = [Float(location.x), Float(location.y)]
            }
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            pointer.viewSize = [Float(size.width), Float(size.height)]
        }
        .contextMenu {
            contextMenuItems
        }
    }

    // Right-click menu (#220). Each action first selects what is under the pointer, then acts on the selection, so it
    // works on the clicked object, or on the current selection when clicking empty space.
    @ViewBuilder
    private var contextMenuItems: some View {
        Button("Select") {
            targetPointer()
        }
        Button("Frame Selection") {
            targetPointer()
            model.frameSelection()
        }
        Button("Drop to Floor") {
            targetPointer()
            model.dropSelectionToFloor()
        }
        Button("Group") {
            targetPointer()
            model.groupSelection()
        }
        Button("Ungroup") {
            targetPointer()
            model.ungroupSelection()
        }
        Divider()
        Button("Hide") {
            targetPointer()
            model.editSelection("Hide") { model, node in model.setVisible(false, node) }
        }
        Button("Lock") {
            targetPointer()
            model.editSelection("Lock") { model, node in model.setLocked(true, node) }
        }
        Button("Delete", role: .destructive) {
            targetPointer()
            model.deleteSelection()
        }
        Divider()
        AddShapeMenu(model: model)
    }

    // Selects the node under the pointer, unless it is already part of the selection (keeps a multiple selection).
    // Over empty space the selection stays as it is.
    private func targetPointer() {
        guard let node = model.node(at: pointer.location, viewSize: pointer.viewSize), !model.isLocked(node) else {
            return
        }
        if !model.selectedIDs.contains(node.id) {
            model.selection = node.id
        }
    }

    // Read when the tap arrives; SceneView's tap callback has no modifier keys.
    private static var isExtendingSelection: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift)
        #else
        false
        #endif
    }
}
