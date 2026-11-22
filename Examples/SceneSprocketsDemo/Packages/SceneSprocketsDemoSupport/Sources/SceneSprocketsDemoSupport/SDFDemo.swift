import GeometryLite3D
import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsBlinnPhong
import simd

// Raymarched signed distance shapes (SceneSprocketsAddOns#3), lit and depth-tested like meshes (#529). Each scene
// shows one part of SignedDistanceShape: metaballs merge spheres with a smooth union, Carved cuts a sphere out of a
// rounded box with a smooth subtraction, Lens keeps where two spheres overlap with a smooth intersection, and Chain
// joins capsules. The shape is rebuilt every frame; only its program and bounding box change, so watch the frame time
// in Release.
final class SDFDemo: DemoScene {
    static let scenes = ["Metaballs", "Carved", "Lens", "Chain"]

    private let shape: SceneGraph.Node
    private let color: SIMD3<Float> = [0.3, 0.55, 0.95]

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 3, 7]
        root.addChild(.camera(.demo, label: "Camera", transform: .init(position: eye, lookingAt: [0, 1, 0])))
        root.addChild(SceneGraph.Node(label: "Light", transform: .init(position: [3, 6, 4], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 1, 1], intensity: 1))))
        root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 10, height: 0.1, length: 10), material: BlinnPhongSceneMaterial.plastic([0.6, 0.6, 0.65], shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        shape = root.addChild(SceneGraph.Node(label: "Signed Distance Shape"))
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(), SignedDistanceRenderer()],
            cameraMatrix: .camera(eye: eye, target: [0, 1, 0]),
            parameters: [
                .choice("Scene", Self.scenes),
                .slider("Blobs", 1...16, default: 6),
                .slider("Smoothing", 0...1.5, default: 0.6),
                .slider("Speed", 0...2, default: 1),
                .toggle("Shadows", default: true),
                .toggle("Ambient Occlusion", default: false)
            ]
        )
    }

    override func update(time: Float, deltaTime _: Float) {
        let t = time * self[value: "Speed"]
        let smoothing = self[value: "Smoothing"]
        let scene = Self.scenes[min(max(Int(self[value: "Scene"]), 0), Self.scenes.count - 1)]
        let signedDistance = Self.shape(scene: scene, time: t, smoothing: smoothing, blobs: Int(self[value: "Blobs"].rounded()))
        try? shape.setSignedDistanceShape(signedDistance, surface: .blinnPhong(.plastic(color, shininess: 48)), device: demoDevice)
        shadows = self[flag: "Shadows"] ? (shadows ?? Shadows(intensity: 0.7)) : nil
        sceneGraph.environment.ambientOcclusion = self[flag: "Ambient Occlusion"] ? SceneGraph.AmbientOcclusion(radius: 0.6, intensity: 0.9, sampleCount: 16) : nil
    }

    // The shape for one scene at `time`.
    static func shape(scene: String, time t: Float, smoothing: Float, blobs: Int) -> SignedDistanceShape {
        let center = Transform3D(translation: [0, 1.2, 0])
        switch scene {
        case "Carved":
            // A sphere that moves through a rounded box, carving a smooth dent in it.
            let box = SignedDistanceShape.roundedBox(size: [1.8, 1.8, 1.8], cornerRadius: 0.2, transform: center)
            let cutter = SignedDistanceShape.sphere(radius: 0.75, transform: .init(translation: [sin(t) * 1.1, 1.2 + cos(t * 0.7) * 0.4, 0.9]))
            return .smoothSubtraction(box, cutter, smoothing: smoothing * 0.3)
        case "Lens":
            // Only where two spheres overlap: a lens that thickens as they move together. They stay closer than their
            // combined radius, so the lens never vanishes.
            let separation = 0.4 + 0.3 * sin(t)
            let left = SignedDistanceShape.sphere(radius: 1, transform: .init(translation: [-separation, 1.2, 0]))
            let right = SignedDistanceShape.sphere(radius: 1, transform: .init(translation: [separation, 1.2, 0]))
            return .smoothIntersection(left, right, smoothing: smoothing * 0.3)
        case "Chain":
            // Capsules along a wave, joined smoothly where they meet.
            let points = (0...6).map { index -> SIMD3<Float> in
                let x = Float(index) * 0.5 - 1.5
                return [x, 1.2 + sin(x * 2 + t * 2) * 0.35, cos(x * 1.5 + t) * 0.3]
            }
            let links = zip(points, points.dropFirst()).map { SignedDistanceShape.capsule(start: $0, end: $1, radius: 0.18) }
            return .smoothUnion(links, smoothing: smoothing * 0.3)
        default:
            // Spheres orbiting the center that merge as they pass.
            let count = max(blobs, 1)
            let spheres = (0..<count).map { index -> SignedDistanceShape in
                let phase = Float(index) / Float(count) * 2 * .pi
                let position = SIMD3<Float>(cos(phase + t * 0.7) * 0.9, 1.2 + sin(phase * 2 + t * 1.3) * 0.5, sin(phase + t * 0.9) * 0.9)
                return .sphere(radius: 0.35 + 0.1 * sin(phase * 3 + t), transform: .init(translation: position))
            }
            return .smoothUnion(spheres, smoothing: smoothing)
        }
    }
}
