import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftUI
import Testing

// #235: SceneView compares equal when its inputs are the same and each closure carries the same id, so SwiftUI can
// skip its body. #369: the settings come from scene… methods, and closures without an id always count as changed.
@MainActor
struct SceneViewEquatableTests {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    let renderer = BlinnPhongMaterialRenderer()

    func view(id: AnyHashable? = "a", shadows: Shadows? = nil, cameraMatrix: Binding<simd_float4x4?>? = nil, renderers: [any MaterialRenderer]? = nil) -> SceneView {
        SceneView(sceneGraph, renderers: renderers ?? [renderer])
            .sceneShadows(shadows)
            .sceneCamera(matrix: cameraMatrix)
            .onSceneTap(id: id) { _, _, _ in }
            .sceneDecorations(id: id) { _, _ in nil }
    }

    @Test
    func sameInputsAndClosureIDsAreEqual() {
        let shadows = Shadows()
        #expect(view(shadows: shadows) == view(shadows: shadows))
        #expect(view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))) == view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))))
        // No closures need no id.
        #expect(SceneView(sceneGraph, renderers: [renderer]).sceneCameraControl() == SceneView(sceneGraph, renderers: [renderer]).sceneCameraControl())
    }

    @Test
    func changesMakeThemUnequal() {
        #expect(view(id: nil) != view(id: nil))
        #expect(view(id: "a") != view(id: "b"))
        #expect(view().sceneStatistics() != view())
        #expect(view().sceneCameraControl() != view())
        #expect(view().sceneDefaultLighting() != view())
        #expect(view(shadows: Shadows()) != view(shadows: Shadows()))
        #expect(view(cameraMatrix: .constant(.init(diagonal: [2, 1, 1, 1]))) != view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))))
        // A renderer with other settings; a new one with the same settings is equal (#487).
        #expect(view(renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [1, 0, 0])]) != view())
        // A closure added on one side only.
        #expect(view().sceneOverlay(id: "a") { _ in nil } != view())
        #expect(view().onSceneFrameTimingChange(id: "a") { _ in } != view())
        #expect(view().onSceneFrameTimingChange(id: "a") { _ in } == view().onSceneFrameTimingChange(id: "a") { _ in })
        #expect(view().sceneHitTestOptions(.init(categoryBitMask: 0b10)) != view())
        #expect(view().sceneHitTestOptions(.init(categoryBitMask: 0b10)) == view().sceneHitTestOptions(.init(categoryBitMask: 0b10)))
    }

    // #376: taps use the same HitTestOptions as SceneGraph.hitTest, narrowed by the camera's mask.
    @Test
    func tapHitTestOptionsCombineWithTheCameraMask() {
        let root = SceneGraph.Node()
        let options = SceneView.tapHitTestOptions(.init(categoryBitMask: 0b0110, backFaceCulling: true, rootNode: root), cameraCategoryBitMask: 0b0011)
        #expect(options.categoryBitMask == 0b0010)
        #expect(options.backFaceCulling)
        #expect(options.rootNode === root)
    }

    // #487: the tutorials write `renderers: [BlinnPhongMaterialRenderer()]` in a body, so each pass makes a new
    // renderer. Two of them with the same settings are the same renderer, so SceneView compares equal.
    @Test
    func inlineBlinnPhongRenderersCompareEqual() {
        #expect(BlinnPhongMaterialRenderer() == BlinnPhongMaterialRenderer())
        #expect(BlinnPhongMaterialRenderer(ambientLightColor: [1, 0, 0]) != BlinnPhongMaterialRenderer())
        let first = SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
        let second = SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
        #expect(first == second)
    }

    // #485: the body must not read the scene's nodes, or SwiftUI evaluates it again every time a node moves.
    @Test(arguments: [false, true])
    func bodyDoesNotDependOnNodes(cameraControl: Bool) {
        let root = SceneGraph.Node()
        root.addChild(SceneGraph.Node(content: .camera(Camera.default)))
        let box = root.addChild(SceneGraph.Node(shape: .box(), material: BlinnPhongSceneMaterial(color: [1, 1, 1])))
        let view = SceneView(SceneGraph(root: root), renderers: [BlinnPhongMaterialRenderer()])
            .sceneCameraControl(cameraControl)
            .sceneStatistics(true)
            .sceneFrameTiming(true)
        nonisolated(unsafe) var fired = false
        withObservationTracking {
            _ = view.body
        } onChange: {
            fired = true
        }
        box.transform.translation.x += 1
        #expect(!fired)
    }
}
