import Foundation
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd
import SwiftMesh

// A train of meshing spur gears from Mesh.gear, in brass, steel and copper. The first gear drives; each next gear
// turns the other way at a speed set by the tooth counts.
final class GearsDemo: DemoScene {
    private struct Link {
        var node: SceneGraph.Node
        var spec: GearSpec
        // Index of the gear this one meshes with, and the direction to it; nil for the driver.
        var parent: Int?
        var direction: Float
    }

    private var links: [Link] = []
    private var angle: Float = 0
    private let train: SceneGraph.Node
    private var builtTeeth: [Int] = []

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0.6, 1.2, 7]
        let target: SIMD3<Float> = [0.6, 0.2, 0]
        root.addChild(.camera(eye: eye, target: target))
        _ = SceneGraph.Node(parent: root, label: "Key", transform: .camera(eye: [3, 4, 6], target: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.88], intensity: 2.5)))
        var rim = Light(type: .point, color: [0.5, 0.65, 1], intensity: 25)
        rim.range = 20
        _ = SceneGraph.Node(parent: root, label: "Rim", trs: .init(translation: [-4, 2, -2]), content: .light(rim))
        _ = SceneGraph.Node(parent: root, label: "Backplate", shape: .box(width: 12, height: 7, length: 0.1), material: BlinnPhongSceneMaterial.plastic([0.08, 0.08, 0.09], shininess: 8), trs: .init(translation: [0.6, 0.2, -0.4]))
        train = SceneGraph.Node(parent: root, label: "Gear Train")
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [0.05, 0.05, 0.06]), PBRMaterialRenderer()],
            cameraMatrix: .camera(eye: eye, target: target),
            parameters: [
                .slider("Driver Teeth", 8...48, default: 24),
                .slider("Second Teeth", 8...48, default: 12),
                .slider("Third Teeth", 8...48, default: 36),
                .slider("Fourth Teeth", 8...48, default: 16),
                .slider("Speed", 0...2, default: 0.5)
            ]
        )
        shadows = SceneGraphShadows(intensity: 0.6, softness: 2)
        rebuild()
    }

    private var requestedTeeth: [Int] {
        ["Driver Teeth", "Second Teeth", "Third Teeth", "Fourth Teeth"].map { Int(self[value: $0].rounded()) }
    }

    override func update(time _: Float, deltaTime: Float) {
        if requestedTeeth != builtTeeth {
            rebuild()
        }
        // About one turn per 4 s for a 24-tooth driver at speed 1, whatever its size.
        angle += deltaTime * self[value: "Speed"] * 2 * .pi / 4 * 24 / Float(links.first?.spec.teeth ?? 24)
        var angles: [Float] = []
        for link in links {
            let value = link.parent.map { parent in
                GearTrain.angle(of: link.spec, meshingWith: links[parent].spec, firstAngle: angles[parent], direction: link.direction)
            } ?? angle
            angles.append(value)
            link.node.trs.rotation = simd_quatf(angle: value, axis: [0, 0, 1])
        }
    }

    // Lays the gears out zigzagging left to right, each meshing with the one before.
    private func rebuild() {
        builtTeeth = requestedTeeth
        train.removeAllChildren()
        links = []
        let materials = [
            (try? PBRSceneMaterial(baseColor: [0.85, 0.65, 0.3, 1], metallic: 1, roughness: 0.3)),
            (try? PBRSceneMaterial(baseColor: [0.75, 0.76, 0.78, 1], metallic: 1, roughness: 0.25)),
            (try? PBRSceneMaterial(baseColor: [0.9, 0.5, 0.35, 1], metallic: 1, roughness: 0.35))
        ]
        let directions: [Float] = [0, -0.5, 0.45, -0.3]
        var center = SIMD2<Float>(-2.2, 0.4)
        for (index, teeth) in builtTeeth.enumerated() {
            let spec = GearSpec(teeth: teeth, module: 0.1, thickness: 0.18 + Float(index % 2) * 0.06, holeRadius: 0.12)
            var direction: Float = 0
            if index > 0 {
                direction = directions[index]
                center = GearTrain.center(of: spec, meshingWith: links[index - 1].spec, at: center, direction: direction)
            }
            let material: any SceneSprockets.Material = materials[index % materials.count] ?? BlinnPhongSceneMaterial.plastic([0.7, 0.6, 0.3])
            let node = SceneGraph.Node(parent: train, label: "Gear \(teeth)", trs: .init(translation: [center.x, center.y, 0]), content: .mesh(MetalMesh(mesh: .gear(spec), device: demoDevice), material: material))
            // An axle through each bore.
            _ = SceneGraph.Node(parent: train, label: "Axle", shape: .cylinder(radius: 0.11, height: 0.6), material: BlinnPhongSceneMaterial.plastic([0.2, 0.2, 0.22], shininess: 48), trs: .init(translation: [center.x, center.y, -0.1], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
            links.append(Link(node: node, spec: spec, parent: index > 0 ? index - 1 : nil, direction: direction))
        }
    }
}
