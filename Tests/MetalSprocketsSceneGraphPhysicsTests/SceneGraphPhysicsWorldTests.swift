import Metal
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphPhysics
import SwiftMesh
import Testing
import simd

// #38

private func makeFloor(in root: SceneGraph.Node) -> SceneGraph.Node {
    let floor = SceneGraph.Node(parent: root, label: "Floor", trs: .init(translation: [0, -0.5, 0]))
    floor.physicsBody = .init(type: .static, shape: .box(size: [20, 1, 20]))
    return floor
}

private func run(_ physics: SceneGraphPhysicsWorld, seconds: Float) {
    for _ in 0..<Int(seconds * 60) {
        physics.step(deltaTime: 1 / 60)
    }
}

@Test
func dynamicBoxFallsAndRestsOnStaticFloor() throws {
    let root = SceneGraph.Node()
    _ = makeFloor(in: root)
    let box = SceneGraph.Node(parent: root, trs: .init(translation: [0, 5, 0]))
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.step(deltaTime: 1 / 60)
    #expect(box.worldPosition.y < 5)
    run(physics, seconds: 4)
    #expect(abs(box.worldPosition.y - 0.5) < 0.05)
    #expect(abs(box.worldPosition.x) < 0.05)
}

@Test
func dynamicNodeUnderScaledParentKeepsItsScale() throws {
    let root = SceneGraph.Node()
    _ = makeFloor(in: root)
    let parent = SceneGraph.Node(parent: root, trs: .init(scale: [2, 2, 2]))
    let box = SceneGraph.Node(parent: parent, trs: .init(translation: [0, 3, 0]))
    // 1 local unit is 2 world units, so the box rests with its center 1 above the floor.
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 4)
    #expect(abs(box.worldPosition.y - 1) < 0.05)
    #expect(simd_distance(box.trs.scale, [1, 1, 1]) < 1e-3)
}

@Test
func stepOnlyChangesTransformRevision() throws {
    let root = SceneGraph.Node()
    let box = SceneGraph.Node(parent: root, trs: .init(translation: [0, 5, 0]))
    box.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let graph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: graph)
    physics.step(deltaTime: 1 / 60)
    let before = graph.revision
    physics.step(deltaTime: 1 / 60)
    #expect(graph.revision.structure == before.structure)
    #expect(graph.revision.transform != before.transform)
}

@Test
func bodiesFollowTheGraph() throws {
    let root = SceneGraph.Node()
    let ball = SceneGraph.Node(parent: root, trs: .init(translation: [0, 5, 0]))
    ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.sync()
    #expect(physics.body(of: ball) != nil)
    #expect(physics.world.bodyCount == 1)
    ball.isVisible = false
    physics.sync()
    #expect(physics.body(of: ball) == nil)
    ball.isVisible = true
    ball.removeFromParent()
    physics.sync()
    #expect(physics.world.bodyCount == 0)
    root.addChild(ball)
    ball.physicsBody = nil
    physics.sync()
    #expect(physics.world.bodyCount == 0)
}

@Test
func velocityLaunchesANode() throws {
    let root = SceneGraph.Node()
    let ball = SceneGraph.Node(parent: root)
    ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root), gravity: .zero)
    physics.setVelocity([3, 0, 0], of: ball)
    run(physics, seconds: 1)
    #expect(abs(ball.worldPosition.x - 3) < 0.1)
}

@Test
func kinematicBodyFollowsItsNodeAndPushes() throws {
    let root = SceneGraph.Node()
    let pusher = SceneGraph.Node(parent: root, trs: .init(translation: [-3, 0, 0]))
    pusher.physicsBody = .init(type: .kinematic, shape: .box(size: [1, 1, 1]))
    let box = SceneGraph.Node(parent: root)
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root), gravity: .zero)
    for _ in 0..<120 {
        pusher.trs.translation.x += 4.0 / 60
        physics.step(deltaTime: 1 / 60)
    }
    let pusherBody = try #require(physics.body(of: pusher))
    #expect(abs(physics.world.position(of: pusherBody).x - pusher.worldPosition.x) < 0.1)
    #expect(box.worldPosition.x > 4)
}

@Test
func boundingBoxAndMeshShapesComeFromTheMesh() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    // A floor made from a plane mesh's triangles.
    let floor = SceneGraph.Node(parent: root, trs: .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])), content: .mesh(MetalMesh(mesh: .quad(extents: [20, 20]), device: device), material: Unlit()))
    floor.physicsBody = .init(type: .static, shape: .mesh)
    // A box whose mesh sits 1 above its origin.
    let mesh = MetalMesh(mesh: Mesh.box(extents: [1, 1, 1]).translated(by: [0, 1, 0]), device: device)
    let box = SceneGraph.Node(parent: root, trs: .init(translation: [0, 4, 0]), content: .mesh(mesh, material: Unlit()))
    box.physicsBody = .init(type: .dynamic, shape: .boundingBox)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 4)
    // The mesh bottom (origin + 0.5) rests on y = 0.
    #expect(abs(box.worldPosition.y + 0.5) < 0.05)
}

private struct Unlit: MetalSprocketsSceneGraph.Material {}
