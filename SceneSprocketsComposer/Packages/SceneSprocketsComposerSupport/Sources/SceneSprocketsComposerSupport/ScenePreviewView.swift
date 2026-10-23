import Interaction3D
import SceneSprockets
import SceneSprocketsGizmos
import simd
import SwiftUI

struct ScenePreviewView: View {
    @Bindable var model: EditorModel
    @State private var lastDragTranslation: CGSize?
    @State private var lastMagnification: CGFloat?
    @Environment(\.self)
    private var environment

    var body: some View {
        // Our own camera control instead of SceneView's: its gestures beat the gizmo's. These are attached outside
        // SceneView, so the gizmo's drag (inside) wins when the pointer is on a handle.
        let settings = model.renderSettings
        // The drawable is not sRGB, so pass the gamma-encoded components.
        let accent = Color.accentColor.resolve(in: environment)
        let outlineColor = SIMD4<Float>(accent.red, accent.green, accent.blue, accent.opacity)
        SceneView(
            sceneGraph: model.sceneGraph,
            options: settings.options,
            renderers: model.renderers,
            shadows: settings.shadows,
            cameraMatrix: .constant(model.camera.matrix),
            camera: settings.camera,
            manipulator: model.gizmo,
            onTap: { hit in
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
        .gesture(cameraDrag)
        .simultaneousGesture(cameraMagnify)
        #if os(macOS)
        .onScrollWheel(delta: Binding(get: { 0 }, set: { model.camera.zoom(by: Float($0) * 0.01) }))
        #endif
    }

    // Drag orbits; Option-drag pans (macOS).
    private var cameraDrag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let last = lastDragTranslation ?? .zero
                lastDragTranslation = value.translation
                let delta = SIMD2<Float>(Float(value.translation.width - last.width), Float(value.translation.height - last.height))
                if isPanModifierDown {
                    model.camera.pan(by: delta)
                } else {
                    model.camera.orbit(by: delta)
                }
            }
            .onEnded { _ in
                lastDragTranslation = nil
            }
    }

    private var cameraMagnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let last = lastMagnification ?? 1
                lastMagnification = value.magnification
                model.camera.zoom(by: Float(log(value.magnification / last)))
            }
            .onEnded { _ in
                lastMagnification = nil
            }
    }

    private var isPanModifierDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.option)
        #else
        false
        #endif
    }
}
