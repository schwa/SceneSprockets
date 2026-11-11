import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftUI

struct Tutorial4Actions: View {
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

        let hopper = root.addShape(.box(width: 0.8, height: 0.8, length: 0.8), material([0.9, 0.25, 0.25]), at: [2, -0.6, 0])
        let squash = SceneGraph.Action.scale(to: [1.3, 0.6, 1.3], duration: 0.25).timingMode(.easeOut)
        let stretch = SceneGraph.Action.scale(to: [0.85, 1.25, 0.85], duration: 0.2)
        let rise = SceneGraph.Action.move(by: [0, 1.2, 0], duration: 0.45).timingMode(.easeOut)
        hopper.run(.repeatForever(.sequence([
            squash, .group([stretch, rise, .rotate(by: .pi / 2, around: [0, 1, 0], duration: 0.9)]),
            rise.reversed(), squash, .scale(to: [1, 1, 1], duration: 0.2), .wait(duration: 0.6),
        ])))

        let glass = root.addShape(.torus(ringRadius: 0.7, pipeRadius: 0.2), material([0.6, 0.9, 0.8], shininess: 128, opacity: 0.5), at: [-2, 0.5, 0])
        glass.run(.repeatForever(.group([
            .rotateBy(x: 2 * .pi, y: 0, z: .pi, duration: 8),
            .sequence([.fadeOut(duration: 2), .fadeIn(duration: 2)]),
        ])))

        let teapot = root.addShape(.teapot(diameter: 1.6), material([0.75, 0.5, 0.85], shininess: 64), at: [0, -0.5, 1.5])
        teapot.run(.repeatForever(.custom(duration: 3) { node, elapsed in
            let phase = elapsed / 3 * 2 * .pi
            node.trs.rotation = Rotation3D(simd_quatf(angle: sin(phase) * 0.3, axis: [0, 0, 1]) * simd_quatf(angle: phase, axis: [0, 1, 0]))
        }))

        let camera = root.addChild(SceneGraph.Node(label: "Camera", content: .camera(SceneView.defaultCamera)))
        camera.trs.translation = [0, 3, 8]
        camera.look(at: [0, 0, 0])

        return SceneGraph(root: root)
    }
}
