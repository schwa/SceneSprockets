import GeometryLite3D
import Metal
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphBlinnPhong
import MetalSprocketsSceneGraphPhysics
import MetalSupport
import SwiftMesh
import simd

// Nodes with physics bodies, simulated by SceneGraphPhysicsWorld (Jolt) each frame.
final class PhysicsDemo: DemoScene {
    private let simulation: PhysicsSimulation

    init() {
        let simulation = PhysicsSimulation()
        self.simulation = simulation
        super.init(sceneGraph: simulation.sceneGraph, cameraMatrix: .camera(eye: [0, 5, 18], target: [0, 2, 0]))
        actions = [
            DemoAction("Launch", systemImage: "arrow.right.circle.fill") { [weak self] in
                self?.simulation.launch()
                self?.hierarchyDidChange()
            },
            DemoAction("Reset", systemImage: "arrow.counterclockwise") { [weak self] in
                self?.simulation.reset()
                self?.hierarchyDidChange()
            },
        ]
    }

    override func update(time: Float, deltaTime: Float) {
        simulation.physics.step(deltaTime: min(deltaTime, 1.0 / 30.0))
    }
}

@MainActor
final class PhysicsSimulation {
    let sceneGraph = SceneGraph(root: SceneGraph.Node(label: "Root"))
    private(set) var physics: SceneGraphPhysicsWorld
    private var ball: SceneGraph.Node?
    private let boxMesh: MetalMesh
    private let sphereMesh: MetalMesh

    init() {
        let device = _MTLCreateSystemDefaultDevice()
        boxMesh = MetalMesh(mesh: .box(), device: device)
        sphereMesh = MetalMesh(mesh: .sphere(), device: device)
        do {
            physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
        } catch {
            fatalError("Failed to initialize Jolt: \(error)")
        }
        buildScene()
    }

    private func buildScene() {
        let root = sceneGraph.root
        root.removeAllChildren()
        ball = nil

        _ = SceneGraph.Node(parent: root, label: "Camera", transform: .translation(0, 5, 18), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
        _ = SceneGraph.Node(parent: root, label: "Key Light", transform: .translation(5, 8, 5), content: .light(Light(type: .point, color: [1, 0.95, 0.9], intensity: 80)))
        _ = SceneGraph.Node(parent: root, label: "Fill Light", transform: .translation(-4, 4, 3), content: .light(Light(type: .point, color: [0.4, 0.5, 0.8], intensity: 40)))
        _ = SceneGraph.Node(parent: root, label: "Back Light", transform: .translation(0, 5, -5), content: .light(Light(type: .point, color: [0.9, 0.9, 1], intensity: 30)))

        // The unit box mesh is scaled to 30 x 1 x 30; the body uses the node's mesh bounds, so it scales too.
        let ground = SceneGraph.Node(parent: root, label: "Ground", trs: .init(translation: [0, -0.5, 0], scale: [30, 1, 30]), content: .mesh(boxMesh, material: BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.45, 0.45, 0.5]), specular: .color(0.2), shininess: 8)))
        ground.physicsBody = .init(type: .static, shape: .boundingBox, friction: 0.6, restitution: 0.3)

        let stackColors: [SIMD3<Float>] = [[0.8, 0.5, 0.2], [0.6, 0.3, 0.15], [0.7, 0.6, 0.3], [0.5, 0.4, 0.2]]
        let rows = 5
        for row in 0..<rows {
            let count = rows - row
            for column in 0..<count {
                let position = SIMD3<Float>(Float(column) - Float(count - 1) / 2, Float(row) * 1.02 + 0.5, 0)
                let material = BlinnPhongSceneMaterial(ambient: .color(0.08), diffuse: .color(stackColors[(row + column) % stackColors.count]), specular: .color(0.4), shininess: 16)
                let box = SceneGraph.Node(parent: root, label: "Box \(row)-\(column)", trs: .init(translation: position), content: .mesh(boxMesh, material: material))
                box.physicsBody = .init(type: .dynamic, shape: .boundingBox, friction: 0.4, restitution: 0.3)
            }
        }
        physics.sync()
        physics.world.optimizeBroadPhase()
    }

    func launch() {
        ball?.removeFromParent()
        let material = BlinnPhongSceneMaterial(ambient: .color(0.08), diffuse: .color([0.9, 0.15, 0.15]), specular: .color(0.8), shininess: 64)
        // The unit sphere mesh has radius 0.5; scaled by 0.8 it is 0.4.
        let newBall = SceneGraph.Node(parent: sceneGraph.root, label: "Ball", trs: .init(translation: [-8, 1.5, 0], scale: [0.8, 0.8, 0.8]), content: .mesh(sphereMesh, material: material))
        newBall.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5), friction: 0.3, restitution: 0.5)
        physics.setVelocity([30, 8, 0], of: newBall)
        ball = newBall
    }

    // A fresh world: Jolt keeps sleeping bodies where they are, so rebuilding is simpler than repositioning.
    func reset() {
        do {
            physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
        } catch {
            fatalError("Failed to initialize Jolt: \(error)")
        }
        buildScene()
    }
}
