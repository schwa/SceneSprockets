// Tutorial 5: constraints.
//
// Constraints adjust a node's transform every frame, after actions run.
// - `lookAt(target:)` turns the node so its -Z axis points at another node.
// - `billboard(freeAxes:)` turns the node to face the camera.
// This tutorial also shows emission: a material that glows, carried by a node that is also a light.

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
        fill.trs.translation = [-5, 4, 4]
        let spot = root.addChild(SceneGraph.Node(label: "Spot", content: .light(Light(type: .spot, intensity: 80, range: 30, outerConeAngle: .pi / 4))))
        spot.trs.translation = [3, 7, 3]
        spot.look(at: .zero)
        root.addShape(.floor(width: 8, length: 8), material([0.4, 0.42, 0.45], shininess: 4), at: [0, -1, 0])

        // A glowing bulb that carries its own warm point light around the scene.
        let bulbPivot = root.addChild(SceneGraph.Node(label: "Bulb Pivot"))
        let bulb = bulbPivot.addChild(SceneGraph.Node(label: "Bulb", content: .light(Light(type: .point, color: [1, 0.6, 0.2], intensity: 6, range: 6, castsShadow: false))))
        bulb.trs.translation = [2.5, 1.2, 0]
        bulb.addShape(.sphere(radius: 0.2), material([1, 0.6, 0.2], emission: [1, 0.6, 0.2]))
        bulbPivot.run(.repeatForever(.rotate(by: -2 * .pi, around: [0, 1, 0], duration: 9)))

        // Look-at: the pointer always aims at the bulb. The cone points along +Y, so it is tipped onto the pointer's -Z.
        let pointer = root.addChild(SceneGraph.Node(label: "Pointer"))
        pointer.trs.translation = [0, -0.2, 0]
        pointer.constraints = [.lookAt(target: bulb)]
        let cone = pointer.addShape(.cone(bottomRadius: 0.4, height: 1.2), material([0.95, 0.8, 0.2]))
        cone.trs.rotation = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])

        // Billboard: the title turns around Y to face the camera.
        let title = root.addShape(.text("Hello, World", fontSize: 0.4, extrusionDepth: 0.08), material([0.95, 0.95, 0.95]), at: [0, 2, 0])
        title.constraints = [.billboard(freeAxes: .y)]

        // A fixed camera (tutorial 2), so the orbiting bulb does not move the view.
        let camera = root.addChild(SceneGraph.Node(label: "Camera", content: .camera(SceneView.defaultCamera)))
        camera.trs.translation = [0, 3, 8]
        camera.look(at: [0, 0.5, 0])

        return SceneGraph(root: root)
    }
}

#Preview {
    Tutorial5Constraints()
}
