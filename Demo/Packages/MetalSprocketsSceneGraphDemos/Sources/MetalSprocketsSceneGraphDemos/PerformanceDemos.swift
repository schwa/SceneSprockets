import GeometryLite3D
import MetalSprocketsSceneGraph
import SwiftMesh
import simd

// A large grid of identical crates. Same mesh and material, so Blinn-Phong draws each color in one instanced call;
// boxes outside the view are culled.
final class InstancingDemo: DemoScene {
    static let sizes = [10, 25, 50, 100]
    private let grid: SceneGraph.Node
    private let box = MetalMesh(mesh: .box(), device: demoDevice)
    private var builtSize = 0
    private var crates: [SceneGraph.Node] = []

    init() {
        let root = SceneGraph.Node(label: "Root")
        root.addChild(.camera(eye: [0, 30, 40]))
        _ = SceneGraph.Node(parent: root, label: "Sun", trs: .init(rotation: simd_quatf(angle: -.pi / 3, axis: simd_normalize([1, 0.3, 0]))), content: .light(Light(type: .directional, intensity: 0.9)))
        root.addChild(.pointLight("Fill", at: [0, 20, 30], color: [0.5, 0.6, 0.9], intensity: 400))
        grid = SceneGraph.Node(parent: root, label: "Grid")
        super.init(sceneGraph: SceneGraph(root: root), cameraMatrix: .camera(eye: [0, 30, 40], target: .zero), parameters: [
            .choice("Grid", Self.sizes.map { "\($0) × \($0)" }, default: 1),
            .toggle("Wave", default: true),
        ])
    }

    override func update(time: Float, deltaTime: Float) {
        let size = Self.sizes[min(max(Int(self[value: "Grid"]), 0), Self.sizes.count - 1)]
        if size != builtSize {
            rebuild(size: size)
        }
        guard self[flag: "Wave"] else {
            return
        }
        let spacing: Float = 60 / Float(size)
        for (index, crate) in crates.enumerated() {
            let row = index / size
            let column = index % size
            let x = (Float(column) - Float(size - 1) / 2) * spacing
            let z = (Float(row) - Float(size - 1) / 2) * spacing
            let height = sin(time * 2 + (x + z) * 0.15) * 2
            crate.trs.translation = [x, height, z]
        }
    }

    private func rebuild(size: Int) {
        grid.removeAllChildren()
        crates.removeAll()
        let spacing: Float = 60 / Float(size)
        let palette: [SIMD3<Float>] = [[0.8, 0.5, 0.2], [0.6, 0.3, 0.15], [0.7, 0.6, 0.3]]
        let materials = palette.map { BlinnPhongSceneMaterial.plastic($0, shininess: 16) }
        for row in 0..<size {
            for column in 0..<size {
                let x = (Float(column) - Float(size - 1) / 2) * spacing
                let z = (Float(row) - Float(size - 1) / 2) * spacing
                let trs = Transform3D(translation: [x, 0, z], scale: SIMD3(repeating: spacing * 0.8))
                crates.append(SceneGraph.Node(parent: grid, label: "Crate \(row)-\(column)", trs: trs, content: .mesh(box, material: materials[(row + column) % materials.count])))
            }
        }
        builtSize = size
        hierarchyDidChange()
    }
}
