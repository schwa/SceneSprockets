import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SwiftUI

struct Tutorial3Lights: View {
    @State private var sceneGraph = Self.makeSceneGraph()
    @State private var shadows = SceneGraphShadows(intensity: 0.7, softness: 2)

    var body: some View {
        SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl], renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")

        root.addChild(.light(.point(intensity: 15, range: 50, castsShadow: false), label: "Fill", transform: .init(translation: [-5, 4, 4])))

        root.addChild(.light(.spot(intensity: 80, range: 30, outerConeAngle: .pi / 4), label: "Spot", transform: .init(position: [3, 7, 3], lookingAt: .zero)))

        root.addChild(SceneGraph.Node(shape: .floor(width: 8, length: 8), material: material([0.4, 0.42, 0.45], shininess: 4), transform: .init(translation: [0, -1, 0])))
        root.addChild(SceneGraph.Node(shape: .sphere(radius: 1), material: material([0.2, 0.45, 0.9], shininess: 64), transform: .init(translation: [0, 0.5, 0])))
        root.addChild(SceneGraph.Node(shape: .box(width: 1.2, height: 1.2, length: 1.2), material: material([0.9, 0.25, 0.25]), transform: .init(translation: [2.2, -0.4, 0.8])))
        root.addChild(SceneGraph.Node(shape: .teapot(diameter: 1.6), material: material([0.75, 0.5, 0.85], shininess: 64), transform: .init(translation: [-2.2, -0.5, 1])))

        return SceneGraph(root: root)
    }
}
