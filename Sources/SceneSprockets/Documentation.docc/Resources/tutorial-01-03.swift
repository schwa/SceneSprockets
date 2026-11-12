import SceneSprockets
import SceneSprocketsBlinnPhong
import SwiftUI

struct Tutorial1Sphere: View {
    @State private var sceneGraph = Self.makeSceneGraph()

    var body: some View {
        SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
            .sceneCameraControl()
            .sceneDefaultLighting()
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")
        let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.2, 0.45, 0.9]), specular: .color(0.5), shininess: 64)
        root.addChild(SceneGraph.Node(label: "Sphere", shape: .sphere(radius: 1), material: material))
        return SceneGraph(root: root)
    }
}
