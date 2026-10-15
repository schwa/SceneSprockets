import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsPBR
import MetalSprocketsSceneGraph
import SwiftMesh
import simd

// A grid of PBR spheres (metallic increases left to right, roughness bottom to top) and, on the right, a column of
// Blinn-Phong spheres with matching shininess: both renderers in one pass, sharing camera, lights and depth.
final class PBRMaterialsDemo: DemoScene {
    private let grid: SceneGraph.Node
    private var blinnPhongNodes: [SceneGraph.Node] = []
    private var blinnPhongOpacity: Float = 1

    init() {
        let sphere = MetalMesh(mesh: .sphere(latitudeSegments: 32, longitudeSegments: 64), device: demoDevice)
        let root = SceneGraph.Node(label: "Root")
        root.addChild(.camera(eye: [0, 0, 14]))
        root.addChild(.pointLight("Key Light", at: [4, 4, 6], intensity: 60))
        root.addChild(.pointLight("Rim Light", at: [-5, -2, 3], color: [0.6, 0.7, 1], intensity: 30))
        grid = SceneGraph.Node(parent: root, label: "Grid")
        let count = 5
        let spacing: Float = 2.2
        let offset = -spacing / 2
        for row in 0..<count {
            let roughness = max(Float(row) / Float(count - 1), 0.05)
            let y = Float(row - count / 2) * spacing
            for column in 0..<count {
                let metallic = Float(column) / Float(count - 1)
                // try! is fine in a demo: PBRMaterial only fails if Metal cannot allocate a tiny buffer.
                let material = try! PBRSceneMaterial(device: demoDevice, baseColor: [0.9, 0.35, 0.2, 1], metallic: metallic, roughness: roughness)
                let position = SIMD3<Float>(Float(column - count / 2) * spacing + offset, y, 0)
                _ = SceneGraph.Node(parent: grid, label: "M \(column) R \(row)", trs: .init(translation: position), content: .mesh(sphere, material: material))
            }
            let blinnPhong = BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.2], shininess: 4 + (1 - roughness) * 120)
            let position = SIMD3<Float>(Float(count - count / 2) * spacing + offset + 0.4, y, 0)
            blinnPhongNodes.append(SceneGraph.Node(parent: grid, label: "Blinn-Phong R \(row)", trs: .init(translation: position), content: .mesh(sphere, material: blinnPhong)))
        }
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer(device: demoDevice)],
            cameraMatrix: .camera(eye: [0, 0, 14], target: .zero),
            parameters: [.toggle("Turn", default: false), .slider("Blinn-Phong Opacity", 0...1, default: 1)]
        )
    }

    override func update(time: Float, deltaTime: Float) {
        let opacity = self[value: "Blinn-Phong Opacity"]
        if opacity != blinnPhongOpacity {
            blinnPhongOpacity = opacity
            for node in blinnPhongNodes {
                if case let .mesh(mesh, materials, castsShadow, receivesShadow) = node.content, var material = materials.first as? BlinnPhongSceneMaterial {
                    material.opacity = opacity
                    node.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
                }
            }
        }
        if self[flag: "Turn"] {
            grid.trs.rotation = simd_normalize(simd_quatf(angle: deltaTime * 0.4, axis: [0, 1, 0]) * grid.trs.rotation)
        }
    }
}
