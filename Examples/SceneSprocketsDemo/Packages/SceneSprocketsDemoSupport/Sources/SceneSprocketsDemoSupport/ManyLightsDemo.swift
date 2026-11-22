import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd

// Hundreds of short-range colored point lights drifting over a floor of pillars (#519). From 16 lights on, lights are
// assigned to clusters, so each pixel shades only the lights near it; compare frame times with the statistics overlay.
final class ManyLightsDemo: DemoScene {
    private static let maximumLightCount = 512

    private let lightsNode: SceneGraph.Node
    private var lights: [(node: SceneGraph.Node, phase: Float, radius: Float, speed: Float)] = []
    private var materialSets: [(node: SceneGraph.Node, blinnPhong: any SceneMaterial, pbr: any SceneMaterial)] = []
    private var usesPBR = false

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 14, 18]
        root.addChild(.camera(.demo, label: "Camera", transform: .init(position: eye, lookingAt: .zero)))
        // A dim key light, so the scene reads without the point lights.
        root.addChild(SceneGraph.Node(label: "Moon", transform: .init(position: [3, 10, 4], lookingAt: .zero), content: .light(Light(type: .directional, color: [0.6, 0.7, 1], intensity: 0.05))))
        let floorColor: SIMD3<Float> = [0.55, 0.55, 0.6]
        let floor = root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 30, height: 0.1, length: 30), material: BlinnPhongSceneMaterial.plastic(floorColor, shininess: 16), transform: .init(translation: [0, -0.05, 0])))
        materialSets.append((floor, BlinnPhongSceneMaterial.plastic(floorColor, shininess: 16), PBRSceneMaterial(baseColor: floorColor, roughness: 0.5)))
        for x in stride(from: -12, through: 12, by: 4) {
            for z in stride(from: -12, through: 12, by: 4) {
                let color: SIMD3<Float> = [0.8, 0.8, 0.8]
                let pillar = root.addChild(SceneGraph.Node(shape: .cylinder(radius: 0.4, height: 2), material: BlinnPhongSceneMaterial.plastic(color), transform: .init(translation: [Float(x), 1, Float(z)])))
                materialSets.append((pillar, BlinnPhongSceneMaterial.plastic(color), PBRSceneMaterial(baseColor: color, roughness: 0.3)))
            }
        }
        lightsNode = root.addChild(SceneGraph.Node(label: "Point Lights"))
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero), PBRMaterialRenderer(environmentIntensity: 0.05)],
            cameraMatrix: .camera(eye: eye, target: .zero),
            parameters: [
                .slider("Lights", 1...Float(Self.maximumLightCount), default: 256),
                .slider("Light Range", 1...6, default: 2.5),
                .toggle("PBR Materials", default: false)
            ]
        )
    }

    override func update(time: Float, deltaTime _: Float) {
        let count = Int(self[value: "Lights"].rounded())
        let range = self[value: "Light Range"]
        // Children are added and removed only when the count changes, so the structure revision stays put otherwise.
        while lights.count < count {
            let index = lights.count
            // Golden-angle spiral over the floor; hues around the color wheel.
            let fraction = Float(index) / Float(Self.maximumLightCount)
            let hue = (Float(index) * 0.618034).truncatingRemainder(dividingBy: 1)
            let color = SIMD3<Float>((0 ..< 3).map { channel in 0.5 + 0.5 * cos(2 * .pi * (hue + Float(channel) / 3)) })
            let node = lightsNode.addChild(SceneGraph.Node(content: .light(Light(type: .point, color: color, intensity: 3, range: range))))
            lights.append((node, Float(index) * 2.399963, 1 + sqrt(fraction) * 13, 0.2 + fraction * 0.3))
        }
        while lights.count > count {
            lights.removeLast().node.removeFromParent()
        }
        for (node, phase, radius, speed) in lights {
            let angle = phase + time * speed
            let wobble = sin(time * 1.3 + phase) * 0.6
            node.transform = Transform3D(translation: [cos(angle) * (radius + wobble), 0.6 + 0.3 * sin(time * 2 + phase), sin(angle) * (radius + wobble)])
            if case let .light(light) = node.content, light.range != range {
                var updated = light
                updated.range = range
                node.content = .light(updated)
            }
        }
        if self[flag: "PBR Materials"] != usesPBR {
            usesPBR = self[flag: "PBR Materials"]
            for set in materialSets {
                if case let .mesh(mesh, _, castsShadow, receivesShadow) = set.node.content {
                    set.node.content = .mesh(mesh, materials: [usesPBR ? set.pbr : set.blinnPhong], castsShadow: castsShadow, receivesShadow: receivesShadow)
                }
            }
        }
    }
}
