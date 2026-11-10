// Tutorial 2: hierarchy and a camera.
//
// A child node's transform is relative to its parent. Move, turn or scale a parent and its children follow.
// Here the moon is a child of a pivot, and the pivot is a child of the planet. Turning the pivot orbits the moon.
// `run(_:)` starts an action on a node. `repeatForever` makes it loop. Tutorial 4 covers actions.
//
// A camera is a node too. Without one, SceneView frames the scene's bounds, so the view jumps as the moon moves.
// A camera node fixes the point of view. SceneView uses the first camera node in the scene.

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

        // The planet spins slowly on its own axis.
        let planet = root.addShape(.sphere(radius: 1), material([0.2, 0.45, 0.9], shininess: 64))
        planet.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 20)))

        // The pivot sits at the planet's center. The moon sits 1.8 units out from the pivot.
        let moonPivot = planet.addChild(SceneGraph.Node(label: "Moon Pivot"))
        moonPivot.addShape(.sphere(radius: 0.3), material([0.8, 0.8, 0.75]), at: [1.8, 0, 0])
        moonPivot.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0.2], duration: 6)))

        // The camera, placed and aimed like any other node.
        let camera = root.addChild(SceneGraph.Node(label: "Camera", content: .camera(SceneView.defaultCamera)))
        camera.trs.translation = [0, 2, 6]
        camera.look(at: .zero)

        return SceneGraph(root: root)
    }
}

#Preview {
    Tutorial2Hierarchy()
}
