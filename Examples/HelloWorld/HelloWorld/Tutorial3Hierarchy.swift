// Tutorial 3: hierarchy.
//
// A child node's transform is relative to its parent. Move, turn or scale a parent and its children follow.
// Here the moon is a child of a pivot, and the pivot is a child of the planet. Turning the pivot orbits the moon.
// `run(_:)` starts an action on a node. `repeatForever` makes it loop.

import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SwiftUI

struct Tutorial3Hierarchy: View {
    @State private var sceneGraph = Self.makeSceneGraph()
    @State private var shadows = SceneGraphShadows(intensity: 0.7, softness: 2)

    var body: some View {
        SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl], renderers: [BlinnPhongMaterialRenderer()], shadows: shadows)
    }

    private static func makeSceneGraph() -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")

        let fill = root.addChild(SceneGraph.Node(label: "Fill", content: .light(Light(type: .point, intensity: 15, range: 50, castsShadow: false))))
        fill.trs.translation = [-5, 4, 4]
        let spot = root.addChild(SceneGraph.Node(label: "Spot", content: .light(Light(type: .spot, intensity: 80, range: 30, outerConeAngle: .pi / 4))))
        spot.trs.translation = [3, 7, 3]
        spot.look(at: .zero)
        root.addShape(.floor(width: 8, length: 8), material([0.4, 0.42, 0.45], shininess: 4), at: [0, -1, 0])

        // The planet spins slowly on its own axis.
        let planet = root.addShape(.sphere(radius: 1), material([0.2, 0.45, 0.9], shininess: 64), at: [0, 0.8, 0])
        planet.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 20)))

        // The pivot sits at the planet's center. The moon sits 1.8 units out from the pivot.
        let moonPivot = planet.addChild(SceneGraph.Node(label: "Moon Pivot"))
        moonPivot.addShape(.sphere(radius: 0.3), material([0.8, 0.8, 0.75]), at: [1.8, 0, 0])
        moonPivot.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0.2], duration: 6)))

        return SceneGraph(root: root)
    }
}

#Preview {
    Tutorial3Hierarchy()
}
