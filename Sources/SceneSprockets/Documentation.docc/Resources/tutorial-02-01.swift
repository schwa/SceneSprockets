import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SwiftUI

struct Tutorial2Hierarchy: View {
    @State private var sceneGraph = Self.makeSceneGraph()

    var body: some View {
        SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl, .autoenablesDefaultLighting], renderers: [BlinnPhongMaterialRenderer()])
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")

        let planet = root.addChild(SceneGraph.Node(shape: .sphere(radius: 1), material: material([0.2, 0.45, 0.9], shininess: 64)))
        planet.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 20)))

        return SceneGraph(root: root)
    }
}
