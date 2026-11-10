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

        let fill = root.addChild(SceneGraph.Node(label: "Fill", content: .light(Light(type: .point, intensity: 15, range: 50, castsShadow: false))))
        fill.trs.translation = [-5, 4, 4]

        root.addShape(.floor(width: 8, length: 8), material([0.4, 0.42, 0.45], shininess: 4), at: [0, -1, 0])
        root.addShape(.sphere(radius: 1), material([0.2, 0.45, 0.9], shininess: 64), at: [0, 0.5, 0])
        root.addShape(.box(width: 1.2, height: 1.2, length: 1.2), material([0.9, 0.25, 0.25]), at: [2.2, -0.4, 0.8])
        root.addShape(.teapot(diameter: 1.6), material([0.75, 0.5, 0.85], shininess: 64), at: [-2.2, -0.5, 1])

        return SceneGraph(root: root)
    }
}
