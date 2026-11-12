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

        root.addChild(.light(.point(intensity: 15, range: 50, castsShadow: false), label: "Fill", transform: .init(translation: [-5, 4, 4])))
        root.addChild(.light(.spot(intensity: 80, range: 30, outerConeAngle: .pi / 4), label: "Spot", transform: .init(position: [3, 7, 3], lookingAt: .zero)))
        root.addChild(SceneGraph.Node(shape: .floor(width: 8, length: 8), material: material([0.4, 0.42, 0.45], shininess: 4), transform: .init(translation: [0, -1, 0])))

        let bulbPivot = root.addChild(SceneGraph.Node(label: "Bulb Pivot"))
        let bulb = bulbPivot.addChild(.light(.point(color: [1, 0.6, 0.2], intensity: 6, range: 6, castsShadow: false), label: "Bulb", transform: .init(translation: [2.5, 1.2, 0])))
        bulb.addChild(SceneGraph.Node(shape: .sphere(radius: 0.2), material: material([1, 0.6, 0.2], emission: [1, 0.6, 0.2])))
        bulbPivot.run(.repeatForever(.rotate(by: -2 * .pi, around: [0, 1, 0], duration: 9)))

        let pointer = root.addChild(SceneGraph.Node(label: "Pointer"))
        pointer.transform.translation = [0, -0.2, 0]
        pointer.constraints = [.lookAt(target: bulb)]
        let cone = pointer.addChild(SceneGraph.Node(shape: .cone(bottomRadius: 0.4, height: 1.2), material: material([0.95, 0.8, 0.2])))
        cone.transform.rotation = Rotation3D(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))

        root.addChild(.camera(label: "Camera", transform: .init(position: [0, 3, 8], lookingAt: [0, 0.5, 0])))

        return SceneGraph(root: root)
    }
}
