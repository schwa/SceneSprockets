#if os(visionOS)
import Foundation
import GeometryLite3D
import MetalSprockets
import MetalSprocketsUI
import SceneSprockets
import simd
import SwiftUI

// What the immersive space shows: the scene a demo window sent it (#385). The render loop reads it off the main actor.
final class ImmersiveSceneBox: @unchecked Sendable {
    static let shared = ImmersiveSceneBox()

    struct Shown {
        var sceneGraph: SceneGraph
        var renderers: [any MaterialRenderer]
    }

    private let lock = NSLock()
    private var shown: Shown?
    // Fixed from the viewer's head on the first frame that has it.
    private var placement: simd_float4x4?

    func show(_ value: Shown?) {
        lock.withLock {
            shown = value
            placement = nil
        }
    }

    var current: Shown? {
        lock.withLock { shown }
    }

    // About 1 m in front of where the head was when the space opened, a little below eye height, facing the viewer.
    func placement(headTransform: simd_float4x4?) -> simd_float4x4? {
        lock.withLock {
            if placement == nil, let headTransform {
                let head = headTransform.columns.3.xyz
                var forward = -SIMD3(headTransform.columns.2.x, 0, headTransform.columns.2.z)
                forward = simd_length(forward) > 1e-4 ? simd_normalize(forward) : [0, 0, -1]
                var matrix = simd_float4x4(simd_quatf(angle: atan2(-forward.x, -forward.z), axis: [0, 1, 0]))
                matrix.columns.3 = SIMD4(head + forward * 1.0 + [0, -0.3, 0], 1)
                placement = matrix
            }
            return placement
        }
    }
}

/// An immersive space that draws the scene a demo window sent with ``ImmersiveSceneToggle``, scaled to about 0.5 m
/// in radius and centered in front of the viewer.
struct SceneDemoImmersiveSpace: Scene {
    static let id = "SceneDemoImmersive"

    var body: some Scene {
        ImmersiveSpace(id: Self.id) {
            ImmersiveRenderContent { context in
                if let shown = ImmersiveSceneBox.shared.current {
                    Self.element(shown, context: context)
                } else {
                    ImmersiveRenderPass(context: context) {
                        EmptyElement()
                    }
                }
            }
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }

    // Runs on the immersive render loop, off the main actor.
    nonisolated static func element(_ shown: ImmersiveSceneBox.Shown, context: ImmersiveContext) -> some Element {
        let bounds = shown.sceneGraph.bounds ?? BoundingBox3D(min: [-1, -1, -1], max: [1, 1, 1])
        let center = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 1e-4)
        let scale = 0.5 / radius
        let placement = ImmersiveSceneBox.shared.placement(headTransform: context.deviceAnchor?.originFromAnchorTransform) ?? {
            var fallback = matrix_identity_float4x4
            fallback.columns.3 = [0, 1.2, -1, 1]
            return fallback
        }()
        var scaling = matrix_identity_float4x4
        scaling.columns.0.x = scale
        scaling.columns.1.y = scale
        scaling.columns.2.z = scale
        var centering = matrix_identity_float4x4
        centering.columns.3 = SIMD4(-center, 1)
        return SceneImmersiveElement(
            shown.sceneGraph,
            renderers: shown.renderers,
            context: context,
            sceneTransform: placement * scaling * centering,
            defaultLight: Light(type: .directional, color: [1, 1, 1], intensity: 1)
        )
    }
}

/// Opens and closes the immersive space showing `scene`. While it is open, the window's view should pause, so the
/// scene is not advanced twice per frame.
struct ImmersiveSceneToggle: View {
    let scene: DemoScene
    @Binding var isImmersive: Bool
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var isTransitioning = false

    var body: some View {
        Button(isImmersive ? "Exit Immersive" : "Immersive", systemImage: isImmersive ? "xmark.circle" : "visionpro") {
            isTransitioning = true
            Task {
                if isImmersive {
                    await dismissImmersiveSpace()
                    ImmersiveSceneBox.shared.show(nil)
                    isImmersive = false
                } else {
                    ImmersiveSceneBox.shared.show(.init(sceneGraph: scene.sceneGraph, renderers: scene.renderers))
                    if case .opened = await openImmersiveSpace(id: SceneDemoImmersiveSpace.id) {
                        isImmersive = true
                    } else {
                        ImmersiveSceneBox.shared.show(nil)
                    }
                }
                isTransitioning = false
            }
        }
        .disabled(isTransitioning)
    }
}
#endif
