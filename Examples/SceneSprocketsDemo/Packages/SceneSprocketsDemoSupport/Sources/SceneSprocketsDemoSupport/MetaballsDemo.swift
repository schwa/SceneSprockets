import GeometryLite3D
import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsBlinnPhong
import simd

// Raymarched signed distance blobs that merge as they move (SceneSprocketsAddOns#3). The shape is rebuilt every
// frame; only its program and bounding box change, so watch the frame time in Release.
final class MetaballsDemo: DemoScene {
    private let blobs: SceneGraph.Node
    private let color: SIMD3<Float> = [0.3, 0.55, 0.95]

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 3, 7]
        root.addChild(.camera(.demo, label: "Camera", transform: .init(position: eye, lookingAt: [0, 1, 0])))
        root.addChild(SceneGraph.Node(label: "Light", transform: .init(position: [3, 6, 4], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
        root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 10, height: 0.1, length: 10), material: BlinnPhongSceneMaterial.plastic([0.6, 0.6, 0.65], shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        root.addChild(SceneGraph.Node(label: "Pillar", shape: .cylinder(radius: 0.15, height: 2.4), material: BlinnPhongSceneMaterial.plastic([0.9, 0.5, 0.3]), transform: .init(translation: [0, 1.2, 0])))
        blobs = root.addChild(SceneGraph.Node(label: "Metaballs"))
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(), SignedDistanceRenderer()],
            cameraMatrix: .camera(eye: eye, target: [0, 1, 0]),
            parameters: [
                .slider("Blobs", 1...16, default: 6),
                .slider("Smoothing", 0...1.5, default: 0.6),
                .slider("Speed", 0...2, default: 1),
                .toggle("Shadows", default: true),
                .toggle("Ambient Occlusion", default: false)
            ]
        )
    }

    override func update(time: Float, deltaTime _: Float) {
        let count = Int(self[value: "Blobs"].rounded())
        let speed = self[value: "Speed"]
        let spheres = (0..<count).map { index -> SignedDistanceShape in
            let phase = Float(index) / Float(count) * 2 * .pi
            let t = time * speed
            let position = SIMD3<Float>(
                cos(phase + t * 0.7) * 0.9,
                1.2 + sin(phase * 2 + t * 1.3) * 0.5,
                sin(phase + t * 0.9) * 0.9
            )
            return .sphere(radius: 0.35 + 0.1 * sin(phase * 3 + t), transform: .init(translation: position))
        }
        let shape = SignedDistanceShape.smoothUnion(spheres, smoothing: self[value: "Smoothing"])
        try? blobs.setSignedDistanceShape(shape, surface: .blinnPhong(.plastic(color, shininess: 48)), device: demoDevice)
        shadows = self[flag: "Shadows"] ? (shadows ?? Shadows(intensity: 0.7)) : nil
        sceneGraph.environment.ambientOcclusion = self[flag: "Ambient Occlusion"] ? SceneGraph.AmbientOcclusion(radius: 0.6, intensity: 0.9, sampleCount: 16) : nil
    }
}
