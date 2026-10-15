import MetalSprocketsSceneGraph
import simd

// One light at a time over a few casters, to compare directional, spot and point shadows (#67), with the shadow
// settings and a floor that can stop receiving shadows (#66).
final class ShadowsDemo: DemoScene {
    private static let lightTypes = ["Directional", "Spot", "Point"]

    private let light: SceneGraph.Node
    private let floor: SceneGraph.Node
    private let shadowRenderer = SceneGraphShadows(intensity: 0.7)

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 6, 9]
        root.addChild(.camera(eye: eye, target: [0, 0.5, 0]))
        light = SceneGraph.Node(parent: root, label: "Light")
        floor = SceneGraph.Node(parent: root, label: "Floor", shape: .box(width: 12, height: 0.1, length: 12), material: BlinnPhongSceneMaterial.plastic([0.6, 0.6, 0.65], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        let casters: [(SceneGraph.Shape, SIMD3<Float>, SIMD3<Float>)] = [
            (.box(), [-2.5, 0.5, 0], [0.9, 0.35, 0.3]),
            (.sphere(radius: 0.6), [0, 0.6, -1], [0.3, 0.6, 0.9]),
            (.torus(ringRadius: 0.6, pipeRadius: 0.2), [2.5, 1.2, 0], [0.9, 0.8, 0.3]),
            (.cylinder(radius: 0.3, height: 2.5), [0.5, 1.25, 1.5], [0.4, 0.8, 0.5]),
        ]
        for (shape, position, color) in casters {
            let node = SceneGraph.Node(parent: root, shape: shape, material: BlinnPhongSceneMaterial.plastic(color), device: demoDevice, trs: .init(translation: position))
            if case .torus = shape {
                node.run(.repeatForever(.rotate(by: .pi * 2, around: [1, 0, 0], duration: 6)), forKey: "spin")
            }
        }
        super.init(
            sceneGraph: SceneGraph(root: root),
            cameraMatrix: .camera(eye: eye, target: [0, 0.5, 0]),
            parameters: [
                .choice("Light", Self.lightTypes),
                .toggle("Shadows", default: true),
                .slider("Shadow Intensity", 0...1, default: 0.7),
                .slider("Softness", 0...4, default: 1),
                .toggle("Blue Shadows", default: false),
                .toggle("Floor Receives Shadows", default: true),
                .slider("Light Angle", 0...(2 * .pi), default: 0.6),
                .toggle("Ambient Occlusion", default: false),
                .slider("Vignette", 0...1, default: 0),
            ]
        )
    }

    override func update(time: Float, deltaTime: Float) {
        let angle = self[value: "Light Angle"]
        let position = SIMD3<Float>(cos(angle) * 3, 4, sin(angle) * 3)
        light.transform = .camera(eye: position, target: .zero)
        let content: Light = switch Int(self[value: "Light"]) {
        case 1: .spot(color: [1, 1, 1], intensity: 40, innerConeAngle: .pi / 8, outerConeAngle: .pi / 5)
        case 2: Light(type: .point, color: [1, 1, 1], intensity: 40)
        default: Light(type: .directional, color: [1, 1, 1], intensity: 1)
        }
        if case let .light(current) = light.content, current.type == content.type {
            // Unchanged; keep the content so the structure revision does not change every frame.
        } else {
            light.content = .light(content)
        }
        if self[flag: "Shadows"] != (shadows != nil) {
            shadows = self[flag: "Shadows"] ? shadowRenderer : nil
        }
        shadowRenderer.intensity = self[value: "Shadow Intensity"]
        shadowRenderer.softness = Int(self[value: "Softness"].rounded())
        shadowRenderer.color = self[flag: "Blue Shadows"] ? [0.2, 0.3, 1] : .zero
        let ambientOcclusion = self[flag: "Ambient Occlusion"] ? SceneGraph.AmbientOcclusion(radius: 0.6, intensity: 0.9, sampleCount: 16) : nil
        let vignette = self[value: "Vignette"]
        sceneGraph.postProcessing = ambientOcclusion == nil && vignette == 0 ? nil : SceneGraph.PostProcessing(vignetteIntensity: vignette, ambientOcclusion: ambientOcclusion)
        let receives = self[flag: "Floor Receives Shadows"]
        if case let .mesh(mesh, materials, castsShadow, receivesShadow) = floor.content, receivesShadow != receives {
            floor.content = .mesh(mesh, materials: materials, castsShadow: castsShadow, receivesShadow: receives)
        }
    }
}
