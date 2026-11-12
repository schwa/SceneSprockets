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

    func view(id: AnyHashable? = "a", shadows: SceneGraphShadows? = nil, cameraMatrix: Binding<simd_float4x4?>? = nil, renderers: [any SceneGraphMaterialRenderer]? = nil) -> SceneView {
        SceneView(sceneGraph, renderers: renderers ?? [renderer])
            .sceneShadows(shadows)
            .sceneCamera(matrix: cameraMatrix)
            .onSceneTap(id: id) { _, _, _ in }
            .sceneDecorations(id: id) { _, _ in nil }
    }

    @Test
    func sameInputsAndClosureIDsAreEqual() {
        let shadows = SceneGraphShadows()
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
        #expect(view(shadows: SceneGraphShadows()) != view(shadows: SceneGraphShadows()))
        #expect(view(cameraMatrix: .constant(.init(diagonal: [2, 1, 1, 1]))) != view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))))
        #expect(view(renderers: [BlinnPhongMaterialRenderer()]) != view())
        // A closure added on one side only.
        #expect(view().sceneOverlay(id: "a") { _ in nil } != view())
    }
}
