// Tutorial 3: lights and shadows.
//
// Lights are nodes too, so you place and aim them with the node's transform.
// A point light shines in all directions. A spot light shines in a cone along its -Z axis; `look(at:)` aims it.
// Pass SceneGraphShadows to SceneView, and lights with `castsShadow` (the default) cast shadows.

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

        // A soft fill light that does not cast shadows.
        let fill = root.addChild(SceneGraph.Node(label: "Fill", content: .light(Light(type: .point, intensity: 15, range: 50, castsShadow: false))))
        fill.trs.translation = [-5, 4, 4]

        // A spot light above the scene, aimed at the origin.
        let spot = root.addChild(SceneGraph.Node(label: "Spot", content: .light(Light(type: .spot, intensity: 80, range: 30, outerConeAngle: .pi / 4))))
        spot.trs.translation = [3, 7, 3]
        spot.look(at: .zero)

        // A floor to catch the shadows.
        root.addShape(.floor(width: 8, length: 8), material([0.4, 0.42, 0.45], shininess: 4), at: [0, -1, 0])

        root.addShape(.sphere(radius: 1), material([0.2, 0.45, 0.9], shininess: 64), at: [0, 0.5, 0])
        root.addShape(.box(width: 1.2, height: 1.2, length: 1.2), material([0.9, 0.25, 0.25]), at: [2.2, -0.4, 0.8])
        root.addShape(.teapot(diameter: 1.6), material([0.75, 0.5, 0.85], shininess: 64), at: [-2.2, -0.5, 1])

        return SceneGraph(root: root)
    }
}

#Preview {
    Tutorial3Lights()
}
