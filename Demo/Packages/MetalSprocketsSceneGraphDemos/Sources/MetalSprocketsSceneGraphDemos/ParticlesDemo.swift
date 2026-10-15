import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSceneGraph
import simd

// A fountain (alpha blended, with gravity) and a fire (additive) on a floor (#50).
final class ParticlesDemo: DemoScene {
    private let fountain = SceneGraph.ParticleSystem(seed: 1)
    private let fire = SceneGraph.ParticleSystem(seed: 2)

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 3, 8]
        root.addChild(.camera(eye: eye, target: [0, 1.5, 0]))
        _ = SceneGraph.Node(parent: root, label: "Sun", transform: .camera(eye: [2, 6, 4], target: .zero), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 0.8)))
        _ = SceneGraph.Node(parent: root, label: "Floor", shape: .box(width: 10, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.35, 0.35, 0.4], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))

        fountain.birthRate = 300
        fountain.lifetime = 2
        fountain.lifetimeRange = 0.5
        fountain.spreadAngle = 0.25
        fountain.speed = 5
        fountain.speedRange = 1
        fountain.acceleration = [0, -6, 0]
        fountain.startSize = 0.12
        fountain.endSize = 0.05
        fountain.startColor = [0.5, 0.75, 1, 0.9]
        fountain.endColor = [0.3, 0.5, 1, 0]
        _ = SceneGraph.Node(parent: root, label: "Fountain", trs: .init(translation: [-1.8, 0, 0])).particleSystems = [fountain]

        fire.birthRate = 200
        fire.lifetime = 0.9
        fire.lifetimeRange = 0.4
        fire.emitterShape = .sphere(radius: 0.25)
        fire.spreadAngle = 0.4
        fire.speed = 1.6
        fire.damping = 0.5
        fire.startSize = 0.45
        fire.endSize = 0.1
        fire.startColor = [1, 0.55, 0.15, 0.8]
        fire.endColor = [0.8, 0.1, 0.02, 0]
        fire.blendMode = .additive
        _ = SceneGraph.Node(parent: root, label: "Fire", trs: .init(translation: [1.8, 0.2, 0])).particleSystems = [fire]

        super.init(
            sceneGraph: SceneGraph(root: root),
            cameraMatrix: .camera(eye: eye, target: [0, 1.5, 0]),
            parameters: [
                .slider("Fountain Rate", 0...1_000, default: 300),
                .slider("Gravity", 0...15, default: 6),
                .slider("Fire Rate", 0...600, default: 200),
            ]
        )
    }

    override func update(time: Float, deltaTime: Float) {
        fountain.birthRate = self[value: "Fountain Rate"]
        fountain.acceleration = [0, -self[value: "Gravity"], 0]
        fire.birthRate = self[value: "Fire Rate"]
    }
}
