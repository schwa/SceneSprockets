import Metal
import SwiftUI
import Testing
import simd
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong

// #235: SceneView compares equal when its inputs are the same and its closures carry the same closuresID, so
// SwiftUI can skip its body.
@MainActor
struct SceneViewEquatableTests {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    let renderer = BlinnPhongMaterialRenderer()

    func view(options: SceneView.Options = [], closuresID: AnyHashable? = "a", shadows: SceneGraphShadows? = nil, cameraMatrix: Binding<simd_float4x4?>? = nil, renderers: [any SceneGraphMaterialRenderer]? = nil) -> SceneView {
        SceneView(
            sceneGraph: sceneGraph,
            options: options,
            renderers: renderers ?? [renderer],
            shadows: shadows,
            cameraMatrix: cameraMatrix,
            onTapAt: { _, _, _ in },
            decorations: { _, _ in nil },
            closuresID: closuresID
        )
    }

    @Test
    func sameInputsAndClosuresIDAreEqual() {
        let shadows = SceneGraphShadows()
        #expect(view(shadows: shadows) == view(shadows: shadows))
        #expect(view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))) == view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))))
    }

    @Test
    func changesMakeThemUnequal() {
        #expect(view(closuresID: nil) != view(closuresID: nil))
        #expect(view(closuresID: "a") != view(closuresID: "b"))
        #expect(view(options: [.showsStatistics]) != view())
        #expect(view(shadows: SceneGraphShadows()) != view(shadows: SceneGraphShadows()))
        #expect(view(cameraMatrix: .constant(.init(diagonal: [2, 1, 1, 1]))) != view(cameraMatrix: .constant(.init(diagonal: [1, 1, 1, 1]))))
        #expect(view(renderers: [BlinnPhongMaterialRenderer()]) != view())
    }
}
