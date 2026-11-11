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

        let fill = root.addChild(SceneGraph.Node(label: "Fill", content: .light(Light(type: .point, intensity: 15, range: 50, castsShadow: false))))
        fill.transform.translation = [-5, 4, 4]
        let spot = root.addChild(SceneGraph.Node(label: "Spot", content: .light(Light(type: .spot, intensity: 80, range: 30, outerConeAngle: .pi / 4))))
        spot.transform.translation = [3, 7, 3]
        spot.look(at: .zero)
        root.addShape(.floor(width: 8, length: 8), material([0.4, 0.42, 0.45], shininess: 4), at: [0, -1, 0])

        let camera = root.addChild(SceneGraph.Node(label: "Camera", content: .camera(SceneView.defaultCamera)))
        camera.transform.translation = [0, 3, 8]
        camera.look(at: [0, 0.5, 0])

        return SceneGraph(root: root)
    }
}
