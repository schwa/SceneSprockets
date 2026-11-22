import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd

// One light at a time over a few casters, to compare directional, spot and point shadows (#67), with the shadow
// settings and a floor that can stop receiving shadows (#66). Ambient occlusion darkens only ambient (Blinn-Phong) or
// image-based (PBR) light, so the emissive sphere stays bright at its contact (#136, #408).
final class ShadowsDemo: DemoScene {
    private static let lightTypes = ["Directional", "Spot", "Point"]

    private let light: SceneGraph.Node
    private let floor: SceneGraph.Node
    private let shadowRenderer = Shadows(intensity: 0.7)
    // Each mesh node with its Blinn-Phong and PBR material, for the "PBR Materials" toggle.
    private var materialSets: [(node: SceneGraph.Node, blinnPhong: any SceneMaterial, pbr: any SceneMaterial)] = []
    private var usesPBR = false

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 6, 9]
        root.addChild(.camera(.demo, label: "Camera", transform: .init(position: eye, lookingAt: [0, 0.5, 0])))
        light = root.addChild(SceneGraph.Node(label: "Light"))
        let floorColor: SIMD3<Float> = [0.6, 0.6, 0.65]
        floor = root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 12, height: 0.1, length: 12), material: BlinnPhongSceneMaterial.plastic(floorColor, shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        var materialSets: [(node: SceneGraph.Node, blinnPhong: any SceneMaterial, pbr: any SceneMaterial)] = []
        materialSets.append((floor, BlinnPhongSceneMaterial.plastic(floorColor, shininess: 8), PBRSceneMaterial(baseColor: floorColor, roughness: 0.8)))
        let casters: [(SceneGraph.Shape, SIMD3<Float>, SIMD3<Float>)] = [
            (.box(), [-2.5, 0.5, 0], [0.9, 0.35, 0.3]),
            (.sphere(radius: 0.6), [0, 0.6, -1], [0.3, 0.6, 0.9]),
            (.torus(ringRadius: 0.6, pipeRadius: 0.2), [2.5, 1.2, 0], [0.9, 0.8, 0.3]),
            (.cylinder(radius: 0.3, height: 2.5), [0.5, 1.25, 1.5], [0.4, 0.8, 0.5])
        ]
        for (shape, position, color) in casters {
            let node = root.addChild(SceneGraph.Node(shape: shape, material: BlinnPhongSceneMaterial.plastic(color), transform: .init(translation: position)))
            materialSets.append((node, BlinnPhongSceneMaterial.plastic(color), PBRSceneMaterial(baseColor: color, roughness: 0.4)))
            if case .torus = shape {
                node.run(.repeatForever(.rotate(by: .pi * 2, around: [1, 0, 0], duration: 6)), forKey: "spin")
            }
        }
        let glow: SIMD3<Float> = [1, 0.45, 0.15]
        let emissivePBR = PBRSceneMaterial(baseColor: .zero, roughness: 1)
        emissivePBR.uniforms.emissiveFactor = glow
        let emissiveBlinnPhong = BlinnPhongSceneMaterial(color: .zero, emission: glow)
        let emissive = root.addChild(SceneGraph.Node(label: "Emissive", shape: .sphere(radius: 0.4), material: emissiveBlinnPhong, transform: .init(translation: [-1.2, 0.4, 1.5])))
        materialSets.append((emissive, emissiveBlinnPhong, emissivePBR))
        self.materialSets = materialSets
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()],
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
                .toggle("PBR Materials", default: false),
                .slider("Vignette", 0...1, default: 0),
                .toggle("Volumetric Fog", default: false)
            ]
        )
    }

    override func update(time _: Float, deltaTime _: Float) {
        let angle = self[value: "Light Angle"]
        let position = SIMD3<Float>(cos(angle) * 3, 4, sin(angle) * 3)
        light.transform = Transform3D(position: position, lookingAt: .zero)
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
        sceneGraph.environment.ambientOcclusion = self[flag: "Ambient Occlusion"] ? SceneGraph.AmbientOcclusion(radius: 0.6, intensity: 0.9, sampleCount: 16) : nil
        if self[flag: "PBR Materials"] != usesPBR {
            usesPBR = self[flag: "PBR Materials"]
            for set in materialSets {
                if case let .mesh(mesh, _, castsShadow, receivesShadow) = set.node.content {
                    set.node.content = .mesh(mesh, materials: [usesPBR ? set.pbr : set.blinnPhong], castsShadow: castsShadow, receivesShadow: receivesShadow)
                }
            }
        }
        // Light beams and shadow shafts through the air (#540); the distance fog stays off.
        let volumetric: SceneGraph.Fog? = self[flag: "Volumetric Fog"] ? SceneGraph.Fog(color: [0, 0, 0, 0], scattering: .init(density: 0.08, intensity: 0.6, anisotropy: 0.4, stepCount: 48, maximumDistance: 25)) : nil
        if sceneGraph.fog != volumetric {
            sceneGraph.fog = volumetric
        }
        let vignette = self[value: "Vignette"]
        sceneGraph.postProcessing = vignette == 0 ? nil : SceneGraph.PostProcessing(vignetteIntensity: vignette)
        let receives = self[flag: "Floor Receives Shadows"]
        if case let .mesh(mesh, materials, castsShadow, receivesShadow) = floor.content, receivesShadow != receives {
            floor.content = .mesh(mesh, materials: materials, castsShadow: castsShadow, receivesShadow: receives)
        }
    }
}
