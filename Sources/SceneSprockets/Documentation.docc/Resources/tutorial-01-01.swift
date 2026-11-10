import SceneSprockets
import SceneSprocketsBlinnPhong
import SwiftUI

struct Tutorial1Sphere: View {
    @State private var sceneGraph = Self.makeSceneGraph()

    var body: some View {
        EmptyView()
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")
        return SceneGraph(root: root)
    }
}
