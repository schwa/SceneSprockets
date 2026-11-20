import DemoKit
import MetalSprockets
import MetalSprocketsUI
import SceneSprockets
import SceneSprocketsGizmos
import simd
import SwiftUI

// Renders one demo. The demo's scene is built the first time the body runs, not in init (#489).
public struct SceneDemoView: View {
    let demo: Demo
    @State private var session = LazyState<DemoSession>()

    public init(demo: Demo) {
        self.demo = demo
    }

    // The scene, if the body has run.
    var builtScene: DemoScene? {
        session.builtValue?.scene
    }

    public var body: some View {
        let session = session.value { DemoSession(demo: demo) }
        SceneDemoContentView(scene: session.scene, delegate: session.delegate)
    }
}

// A demo's scene and what forwards SceneView's updates to it.
@MainActor
struct DemoSession {
    let scene: DemoScene
    let delegate: DemoSceneDelegate

    init(demo: Demo) {
        scene = demo.make()
        delegate = DemoSceneDelegate(scene: scene)
    }
}

// One demo in a SceneView with playback controls, frame timing and an inspector.
struct SceneDemoContentView: View {
    let scene: DemoScene
    let delegate: DemoSceneDelegate
    @State private var cameraMatrix: simd_float4x4?
    @State private var isPaused = false
    @State private var frameTiming = FrameTimingModel()
    // Moves, rotates and scales the selected node (#154).
    @State private var gizmo = TransformGizmo()
    @State private var gizmoMode = TransformGizmo.Mode.translate
    @State private var gizmoSpace = TransformGizmo.Space.world
    @State private var selectionOutline = SelectionOutline()
    // The scene is also drawn in the immersive space (#385); this view pauses so it is advanced only once per frame.
    @State private var isImmersive = false
    // FPS, frame timing and scene counts (#131). Remembered across launches.
    @AppStorage("showsStatistics") private var showsStatistics = false

    init(scene: DemoScene, delegate: DemoSceneDelegate) {
        self.scene = scene
        self.delegate = delegate
        _cameraMatrix = State(initialValue: scene.initialCameraMatrix)
    }

    var body: some View {
        DemoSceneContent(scene: scene, delegate: delegate, isImmersive: isImmersive, isPaused: isPaused, showsStatistics: showsStatistics, cameraMatrix: $cameraMatrix, gizmo: gizmo, selectionOutline: selectionOutline)
        .onFrameTimingChange { frameTiming.statistics = $0 }
        .onChange(of: scene.selectedNodeID, initial: true) {
            gizmo.target = scene.selectedNode
        }
        .onChange(of: gizmoMode, initial: true) {
            gizmo.mode = gizmoMode
        }
        .onChange(of: scene.gizmoMode) {
            if let mode = scene.gizmoMode {
                gizmo.mode = mode
            }
        }
        .onChange(of: gizmoSpace, initial: true) {
            gizmo.space = gizmoSpace
        }
        .overlay(alignment: .topTrailing) {
            if showsStatistics {
                FrameTimingBadge(model: frameTiming)
            }
        }
        .toolbar {
            ForEach(scene.actions) { action in
                Button(action.name, systemImage: action.systemImage) {
                    action.perform()
                }
                .keyboardShortcut(action.shortcut.map { KeyboardShortcut($0, modifiers: []) })
            }
            Picker("Gizmo", selection: $gizmoMode) {
                Label("Move", systemImage: "arrow.up.and.down.and.arrow.left.and.right").tag(TransformGizmo.Mode.translate)
                Label("Rotate", systemImage: "arrow.clockwise").tag(TransformGizmo.Mode.rotate)
                Label("Scale", systemImage: "arrow.up.left.and.arrow.down.right").tag(TransformGizmo.Mode.scale)
            }
            .pickerStyle(.segmented)
            .help("Select a node, then drag the gizmo's handles")
            Picker("Space", selection: $gizmoSpace) {
                Text("World").tag(TransformGizmo.Space.world)
                Text("Local").tag(TransformGizmo.Space.local)
            }
            Button(isPaused ? "Play" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill") {
                isPaused.toggle()
            }
            Toggle("Statistics", systemImage: "speedometer", isOn: $showsStatistics)
                .help("Show FPS, frame timing and scene counts")
            #if os(visionOS)
            ImmersiveSceneToggle(scene: scene, isImmersive: $isImmersive)
            #endif
            if !scene.usesSceneCamera {
                Button("Reset Camera", systemImage: "camera.viewfinder") {
                    cameraMatrix = scene.initialCameraMatrix
                }
            }
        }
        // DemoKit shows this in its own inspector, with a toolbar button to toggle it.
        .demoConfiguration {
            DemoInspectorView(scene: scene)
        }
    }
}

// The demo's SceneView. While the immersive space shows the scene (#385), the window draws nothing, so the scene is
// drawn once. Its own view, not a property of SceneDemoContentView (#493).
private struct DemoSceneContent: View {
    let scene: DemoScene
    let delegate: DemoSceneDelegate
    let isImmersive: Bool
    let isPaused: Bool
    let showsStatistics: Bool
    @Binding var cameraMatrix: simd_float4x4?
    let gizmo: TransformGizmo
    let selectionOutline: SelectionOutline

    var body: some View {
        if isImmersive {
            ContentUnavailableView("Showing in Immersive Space", systemImage: "visionpro", description: Text("Exit Immersive to see the scene here."))
        } else {
            SceneView(scene.sceneGraph, renderers: scene.renderers)
                .sceneCameraControl(!scene.usesSceneCamera)
                .sceneDelegate(delegate)
                .scenePlaying(!isPaused)
                .sceneShadows(scene.shadows)
                .sceneCamera(matrix: scene.usesSceneCamera ? .constant(nil) : $cameraMatrix)
                .sceneHitTestOptions(.init(categoryBitMask: scene.pickCategoryBitMask))
                .sceneManipulator(gizmo)
                .sceneDebugMode(scene.debugMode)
                .sceneStatistics(showsStatistics)
                .onSceneTap { hit in
                    scene.pick(hit)
                }
                .sceneOverlay(scene.showsSelectionOutline ? { @MainActor @Sendable [scene, selectionOutline] viewport in
                    try selectionOutline.element(nodes: scene.selectedNode.map { [$0] } ?? [], sceneGraph: scene.sceneGraph, viewport: viewport)
                } : nil)
        }
    }
}

// Frame timing changes every frame. It lives in an object, so only the badge that reads it updates, not the whole
// demo view (#475).
@MainActor
@Observable
final class FrameTimingModel {
    var statistics: FrameTimingStatistics?
}

struct FrameTimingBadge: View {
    let model: FrameTimingModel

    var body: some View {
        if let statistics = model.statistics {
            FrameTimingView(statistics: statistics, options: .all)
                .padding()
        }
    }
}

// Forwards SceneView's per-frame update to the demo.
final class DemoSceneDelegate: ViewDelegate {
    let scene: DemoScene

    init(scene: DemoScene) {
        self.scene = scene
    }

    func sceneView(updateAtTime time: Float, deltaTime: Float) {
        scene.update(time: time, deltaTime: deltaTime)
    }
}
