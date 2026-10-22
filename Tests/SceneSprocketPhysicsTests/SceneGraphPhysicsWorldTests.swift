import GeometryLite3D
import Metal
import SceneSprocket
import SceneSprocketPhysics
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

private struct Unlit: SceneSprocket.Material {}

// #125: the slider constraint stops a node at physics bodies and lets it slide along them.
@Test
func sliderConstraintStopsAtWallAndSlides() throws {
    let root = SceneGraph.Node()
    // A wall whose near face is the plane x = 2.
    let wall = SceneGraph.Node(parent: root, label: "Wall", trs: .init(translation: [2.5, 0, 0]))
    wall.physicsBody = .init(type: .static, shape: .box(size: [1, 10, 10]))
    let ignored = SceneGraph.Node(parent: root, label: "Other Category", trs: .init(translation: [-2.5, 0, 0]))
    ignored.physicsBody = .init(type: .static, shape: .box(size: [1, 10, 10]))
    ignored.categoryBitMask = 0b10
    let mover = SceneGraph.Node(parent: root)
    let sceneGraph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
    physics.sync()
    mover.constraints = [physics.sliderConstraint(radius: 0.5, categoryBitMask: 0b01)]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)

    // Straight into the wall: stops with its sphere touching the face.
    mover.trs.translation = [5, 0, 0]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.trs.translation.x - 1.5) < 0.05)

    // Diagonally into the wall: blocked in x, free in z.
    mover.trs.translation = [4, 0, 3]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.trs.translation.x - 1.5) < 0.05)
    #expect(abs(mover.trs.translation.z - 3) < 0.05)

    // Bodies outside the category do not block.
    mover.trs.translation = [-5, 0, 3]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.trs.translation.x + 5) < 0.05)
}

// A scaled, tumbling body must keep its scale: each step writes the body's pose back into the node's transform.
@Test
func decomposingScaledRotationsKeepsScale() {
    var generator = SystemRandomNumberGenerator()
    var worst: (error: Float, rotation: simd_quatf, scale: SIMD3<Float>) = (0, simd_quatf(), .zero)
    for _ in 0..<10_000 {
        let rotation = simd_normalize(simd_quatf(vector: SIMD4<Float>.random(in: -1...1, using: &generator)))
        let pose = Transform3D(translation: [1, 2, 3], rotation: rotation, scale: [0.0625, 0.0625, 0.0625])
        let back = Transform3D(decomposing: pose.matrix)
        let error = simd_distance(back.scale, pose.scale)
        if error > worst.error {
            worst = (error, rotation, back.scale)
        }
    }
    #expect(worst.error < 1e-4, "rotation \(worst.rotation.vector) decomposed to scale \(worst.scale)")
}

// A pose logged from the dice demo. Decomposing its matrix gave a rotation that was not unit length, so the next
// matrix was scaled by its squared length, and the node shrank step after step.
@Test
func decomposedRotationIsUnitLength() {
    let bits: [UInt32] = [0x3f86c96c, 0x3fb5b075, 0x3f1774cd, 0x3f6f0dd7, 0x3ddbc806, 0x3eae95cb, 0x3c7312b4, 0x3d80000b, 0x3d80000c, 0x3d800009]
    let values = bits.map(Float.init(bitPattern:))
    let pose = Transform3D(translation: [values[0], values[1], values[2]], rotation: simd_quatf(vector: [values[3], values[4], values[5], values[6]]), scale: [values[7], values[8], values[9]])
    let once = Transform3D(decomposing: pose.matrix)
    #expect(abs(simd_length(once.rotation.vector) - 1) < 1e-5, "rotation length \(simd_length(once.rotation.vector))")
    // The same rotation, as q or -q (GeometryLite3D #42).
    #expect(abs(abs(simd_dot(once.rotation.vector, pose.rotation.vector)) - 1) < 1e-4, "rotation \(pose.rotation.vector) came back \(once.rotation.vector)")
    let twice = Transform3D(decomposing: once.matrix)
    #expect(simd_distance(twice.scale, pose.scale) < 1e-5, "scale \(pose.scale) came back \(twice.scale)")
}

@Test
func tumblingScaledBodyKeepsItsScale() throws {
    let root = SceneGraph.Node()
    _ = makeFloor(in: root)
    let die = SceneGraph.Node(parent: root, trs: .init(translation: [0, 2, 0], rotation: simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3])), scale: [0.0625, 0.0625, 0.0625]))
    die.physicsBody = .init(type: .dynamic, shape: .box(size: [8, 8, 8]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.setAngularVelocity([12, -9, 15], of: die)
    run(physics, seconds: 3)
    let scale = die.trs.scale
    #expect(simd_distance(scale, [0.0625, 0.0625, 0.0625]) < 1e-4, "scale drifted to \(scale)")
}
