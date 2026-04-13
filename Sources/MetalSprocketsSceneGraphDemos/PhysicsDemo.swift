import GeometryLite3D
import Interaction3D
import JoltPhysics
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSceneGraph
import MetalSupport
import SwiftMesh
import MetalSprocketsSceneGraphRenderer
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import SwiftUI

// Jolt physics drives the scene graph each frame.
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
        if deltaTime > 0 {
            simulation.step()
        }
        simulation.syncToSceneGraph()
    }
}

// MARK: - PhysicsSimulation

/// Manages the Jolt physics world and a matching scene graph.
@MainActor
final class PhysicsSimulation {
    let sceneGraph: SceneGraph
    private let world: PhysicsWorld

    // Tracked bodies and their scene nodes
    private var trackedBodies: [(body: BodyID, node: SceneGraph.Node)] = []
    private var ballBody: BodyID?

    private let device: MTLDevice
    private let boxMesh: MetalMesh
    private let sphereMesh: MetalMesh

    private let dt: Float = 1.0 / 60.0

    init() {
        device = _MTLCreateSystemDefaultDevice()
        boxMesh = MetalMesh(mesh: .box(), device: device)
        sphereMesh = MetalMesh(mesh: .sphere(), device: device)

        do {
            world = PhysicsWorld(engine: try JoltEngine())
        } catch {
            fatalError("Failed to initialize Jolt")
        }
        sceneGraph = SceneGraph(root: SceneGraph.Node(label: "Root"))

        buildScene()
    }

    // MARK: - Scene Construction

    private func buildScene() {
        let root = sceneGraph.root
        root.removeAllChildren()
        trackedBodies.removeAll()
        ballBody = nil

        // Camera
        let cameraNode = SceneGraph.Node(
            label: "Camera",
            transform: .translation(0, 5, 18),
            content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))
        )
        addChild(cameraNode, to: root)

        // Lights
        let keyLight = SceneGraph.Node(
            label: "Key Light",
            transform: .translation(5, 8, 5),
            content: .light(Light(type: .point, color: [1, 0.95, 0.9], intensity: 80.0))
        )
        addChild(keyLight, to: root)

        let fillLight = SceneGraph.Node(
            label: "Fill Light",
            transform: .translation(-4, 4, 3),
            content: .light(Light(type: .point, color: [0.4, 0.5, 0.8], intensity: 40.0))
        )
        addChild(fillLight, to: root)

        let backLight = SceneGraph.Node(
            label: "Back Light",
            transform: .translation(0, 5, -5),
            content: .light(Light(type: .point, color: [0.9, 0.9, 1.0], intensity: 30.0))
        )
        addChild(backLight, to: root)

        // Ground plane (physics + visual)
        _ = world.addBody(
            .box(halfExtents: [15, 0.5, 15]),
            position: [0, -0.5, 0],
            motionType: .static,
            restitution: 0.3,
            friction: 0.6
        )
        let groundNode = SceneGraph.Node(
            label: "Ground",
            transform: .translation(0, -0.5, 0) * .scale(15, 0.5, 15),
            content: .mesh(
                boxMesh,
                material: BlinnPhongMaterial(
                    ambient: .color(0.1),
                    diffuse: .color([0.45, 0.45, 0.5]),
                    specular: .color(0.2),
                    shininess: 8
                )
            )
        )
        addChild(groundNode, to: root)
        // Ground is static, no need to track

        // Box stack — pyramid of crates
        let stackColors: [SIMD3<Float>] = [
            [0.8, 0.5, 0.2], // orange
            [0.6, 0.3, 0.15], // brown
            [0.7, 0.6, 0.3], // tan
            [0.5, 0.4, 0.2], // dark tan
        ]

        let rows = 5
        for row in 0..<rows {
            let count = rows - row
            for col in 0..<count {
                let x = Float(col) - Float(count - 1) / 2.0
                let y = Float(row) * 1.02 + 0.5
                let z: Float = 0

                let body = world.addBody(
                    .box(halfExtents: [0.5, 0.5, 0.5]),
                    position: [x, y, z],
                    motionType: .dynamic,
                    restitution: 0.3,
                    friction: 0.4
                )

                let color = stackColors[(row + col) % stackColors.count]
                let node = SceneGraph.Node(
                    label: "Box \(row)-\(col)",
                    content: .mesh(
                        boxMesh,
                        material: BlinnPhongMaterial(
                            ambient: .color(0.08),
                            diffuse: .color(color),
                            specular: .color(0.4),
                            shininess: 16
                        )
                    )
                )
                addChild(node, to: root)
                trackedBodies.append((body, node))
            }
        }

        world.optimizeBroadPhase()
    }

    private func addChild(_ child: SceneGraph.Node, to parent: SceneGraph.Node) {
        parent.addChild(child)
    }

    // MARK: - Simulation

    func step() {
        world.update(deltaTime: dt)
    }

    func syncToSceneGraph() {
        for (body, node) in trackedBodies {
            let pos = world.position(of: body)
            let rot = world.rotation(of: body)
            node.transform = float4x4.translation(pos.x, pos.y, pos.z) * simd_matrix4x4(rot)

            // Scale for the ball (sphere radius 0.4 → visual sphere is unit radius, so scale by 0.4)
            if node.label == "Ball" {
                node.transform = node.transform * .scale(0.4, 0.4, 0.4)
            }
        }
    }

    func launch() {
        // Remove old ball if it exists
        if let oldBall = ballBody {
            if let index = trackedBodies.firstIndex(where: { $0.body == oldBall }) {
                let oldNode = trackedBodies[index].node
                oldNode.removeFromParent()
                trackedBodies.remove(at: index)
            }
            world.removeBody(oldBall)
        }

        let newBall = world.addBody(
            .sphere(radius: 0.4),
            position: [-8, 1.5, 0],
            motionType: .dynamic,
            restitution: 0.5,
            friction: 0.3
        )
        world.setLinearVelocity(of: newBall, to: [30, 8, 0])

        let ballNode = SceneGraph.Node(
            label: "Ball",
            content: .mesh(
                sphereMesh,
                material: BlinnPhongMaterial(
                    ambient: .color(0.08),
                    diffuse: .color([0.9, 0.15, 0.15]),
                    specular: .color(0.8),
                    shininess: 64
                )
            )
        )
        addChild(ballNode, to: sceneGraph.root)
        trackedBodies.append((newBall, ballNode))
        ballBody = newBall
    }

    func reset() {
        // Rebuild everything from scratch
        // (Jolt doesn't easily support repositioning sleeping bodies)
        buildScene()
    }
}


