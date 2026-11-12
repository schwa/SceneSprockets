import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftUI

struct Tutorial5Constraints: View {
    @State private var sceneGraph = Self.makeSceneGraph()
    @State private var shadows = SceneGraphShadows(intensity: 0.7, softness: 2)

    var body: some View {
        SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl], renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")

        root.addChild(.light(.point(intensity: 15, range: 50, castsShadow: false), label: "Fill", transform: .init(translation: [-5, 4, 4])))
        root.addChild(.light(.spot(intensity: 80, range: 30, outerConeAngle: .pi / 4), label: "Spot", transform: .init(position: [3, 7, 3], lookingAt: .zero)))
        root.addChild(SceneGraph.Node(shape: .floor(width: 8, length: 8), material: BlinnPhongSceneMaterial(color: [0.4, 0.42, 0.45], shininess: 4), transform: .init(translation: [0, -1, 0])))

        root.addChild(.camera(label: "Camera", transform: .init(position: [0, 3, 8], lookingAt: [0, 0.5, 0])))

        return SceneGraph(root: root)
    }
}
