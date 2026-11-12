// Tutorial 1: a sphere on screen.
//
// A scene graph is a tree of nodes. A node with a shape and a material draws a mesh.
// SceneView draws the graph. With no camera in the scene, it uses a default camera that frames the scene.
// `.sceneDefaultLighting()` adds a light at the camera when the scene has no lights, like SceneKit.

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

#Preview {
    Tutorial1Sphere()
}
