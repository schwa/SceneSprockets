import DemoKit
import MetalSprockets
import SceneSprockets
import MetalSprocketsUI
import simd
import SwiftUI

// Renders one demo in a SceneView with playback controls, frame timing and an inspector.
public struct SceneDemoView: View {
    let demo: Demo
    @State private var scene: DemoScene
    @State private var delegate: DemoSceneDelegate
    @State private var cameraMatrix: simd_float4x4?
    @State private var isPaused = false
    @State private var frameTimingStatistics: FrameTimingStatistics?

    public init(demo: Demo) {
        self.demo = demo
        let scene = demo.make()
        _scene = State(initialValue: scene)
        _delegate = State(initialValue: DemoSceneDelegate(scene: scene))
        _cameraMatrix = State(initialValue: scene.initialCameraMatrix)
    }

    public var body: some View {
        SceneView(
            sceneGraph: scene.sceneGraph,
            options: scene.usesSceneCamera ? [] : [.allowsCameraControl],
            renderers: scene.renderers,
            delegate: delegate,
            isPlaying: !isPaused,
            shadows: scene.shadows,
            cameraMatrix: scene.usesSceneCamera ? .constant(nil) : $cameraMatrix,
            hitTestCategoryBitMask: scene.pickCategoryBitMask
        ) { hit in
            scene.pick(hit)
        }
        .onFrameTimingChange { frameTimingStatistics = $0 }
        .overlay(alignment: .topTrailing) {
            if let frameTimingStatistics {
                FrameTimingView(statistics: frameTimingStatistics, options: .all)
                    .padding()
            }
        }
        .toolbar {
            ForEach(scene.actions) { action in
                if let shortcut = action.shortcut {
                    Button(action.name, systemImage: action.systemImage) {
                        action.perform()
                    }
                    .keyboardShortcut(shortcut, modifiers: [])
                } else {
                    Button(action.name, systemImage: action.systemImage) {
                        action.perform()
                    }
                }
            }
            Button(isPaused ? "Play" : "Pause", systemImage: isPaused ? "play.fill" : "pause.fill") {
                isPaused.toggle()
            }
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

// Forwards SceneView's per-frame update to the demo.
final class DemoSceneDelegate: SceneViewDelegate {
    let scene: DemoScene

    init(scene: DemoScene) {
        self.scene = scene
    }

    func sceneView(updateAtTime time: Float, deltaTime: Float) {
        scene.update(time: time, deltaTime: deltaTime)
    }
}
