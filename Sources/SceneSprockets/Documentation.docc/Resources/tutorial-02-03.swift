import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SwiftUI

struct Tutorial2Hierarchy: View {
    @State private var sceneGraph = Self.makeSceneGraph()

    var body: some View {
        SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
            .sceneCameraControl()
            .sceneDefaultLighting()
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")

        let planet = root.addChild(SceneGraph.Node(shape: .sphere(radius: 1), material: BlinnPhongSceneMaterial(color: [0.2, 0.45, 0.9], shininess: 64)))
        planet.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 20)))

        let moonPivot = planet.addChild(SceneGraph.Node(label: "Moon Pivot"))
        moonPivot.addChild(SceneGraph.Node(shape: .sphere(radius: 0.3), material: BlinnPhongSceneMaterial(color: [0.8, 0.8, 0.75]), transform: .init(translation: [1.8, 0, 0])))
        moonPivot.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0.2], duration: 6)))

        root.addChild(.camera(label: "Camera", transform: .init(position: [0, 2, 6], lookingAt: .zero)))

        return SceneGraph(root: root)
    }
}
