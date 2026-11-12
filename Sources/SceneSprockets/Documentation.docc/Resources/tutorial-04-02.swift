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

        root.addChild(.light(.point(intensity: 15, range: 50, castsShadow: false), label: "Fill", transform: .init(translation: [-5, 4, 4])))
        root.addChild(.light(.spot(intensity: 80, range: 30, outerConeAngle: .pi / 4), label: "Spot", transform: .init(position: [3, 7, 3], lookingAt: .zero)))
        root.addChild(SceneGraph.Node(shape: .floor(width: 8, length: 8), material: BlinnPhongSceneMaterial(color: [0.4, 0.42, 0.45], shininess: 4), transform: .init(translation: [0, -1, 0])))

        let hopper = root.addChild(SceneGraph.Node(shape: .box(width: 0.8, height: 0.8, length: 0.8), material: BlinnPhongSceneMaterial(color: [0.9, 0.25, 0.25]), transform: .init(translation: [2, -0.6, 0])))
        let squash = SceneGraph.Action.scale(to: [1.3, 0.6, 1.3], duration: 0.25).timingMode(.easeOut)
        let stretch = SceneGraph.Action.scale(to: [0.85, 1.25, 0.85], duration: 0.2)
        let rise = SceneGraph.Action.move(by: [0, 1.2, 0], duration: 0.45).timingMode(.easeOut)
        hopper.run(.repeatForever(.sequence([
            squash, .group([stretch, rise, .rotate(by: .pi / 2, around: [0, 1, 0], duration: 0.9)]),
            rise.reversed(), squash, .scale(to: [1, 1, 1], duration: 0.2), .wait(duration: 0.6),
        ])))

        root.addChild(.camera(label: "Camera", transform: .init(position: [0, 3, 8], lookingAt: [0, 0, 0])))

        return SceneGraph(root: root)
    }
}
