import GeometryLite3D
import Metal
import SceneSprockets
@testable import SceneSprocketsPhysics
import simd
import SwiftMesh
import Testing

// #38

private func makeFloor(in root: SceneGraph.Node) -> SceneGraph.Node {
    let floor = root.addChild(SceneGraph.Node(label: "Floor", transform: .init(translation: [0, -0.5, 0])))
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
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 5, 0])))
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
    let parent = root.addChild(SceneGraph.Node(transform: .init(scale: [2, 2, 2])))
    let box = parent.addChild(SceneGraph.Node(transform: .init(translation: [0, 3, 0])))
    // 1 local unit is 2 world units, so the box rests with its center 1 above the floor.
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 4)
    #expect(abs(box.worldPosition.y - 1) < 0.05)
    #expect(simd_distance(box.transform.scale, [1, 1, 1]) < 1e-3)
}

@Test
func stepOnlyChangesTransformRevision() throws {
    let root = SceneGraph.Node()
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 5, 0])))
    box.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let graph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: graph)
    physics.step(deltaTime: 1 / 60)
    let before = graph.revision
    physics.step(deltaTime: 1 / 60)
    #expect(graph.revision.structure == before.structure)
    #expect(graph.revision.transform != before.transform)
}

// #416: a scaled mesh shape collides at its scaled size; Jolt scales the triangles instead of copied vertices.
@Test
func scaledMeshFloorCatchesABoxNearItsEdge() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    // A 2 x 2 quad scaled to 20 x 20.
    let floor = root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]), scale: [10, 10, 10]), content: .mesh(MetalMesh(mesh: .quad(extents: [2, 2]), device: device), material: Unlit())))
    floor.physicsBody = .init(type: .static, shape: .mesh)
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [8, 2, 8])))
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 3)
    #expect(abs(box.worldPosition.y - 0.5) < 0.05, "box at \(box.worldPosition)")
}

// #419: a body that has come to rest and gone to sleep does not write its node each step.
@Test
func sleepingBodiesDoNotWriteTheirNodes() throws {
    let root = SceneGraph.Node()
    _ = makeFloor(in: root)
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, 0])))
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let graph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: graph)
    run(physics, seconds: 5)
    let body = try #require(physics.body(of: box))
    #expect(!physics.world.isActive(body))
    let before = graph.revision
    physics.step(deltaTime: 1 / 60)
    #expect(graph.revision == before)
    #expect(abs(box.worldPosition.y - 0.5) < 0.05)
}

// #417: node(of:) finds a body's node through an index, kept in step as bodies are made, rebuilt and removed.
@Test
func nodeOfBodyFollowsTheGraph() throws {
    let root = SceneGraph.Node()
    let a = root.addChild(SceneGraph.Node())
    a.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let b = root.addChild(SceneGraph.Node(transform: .init(translation: [3, 0, 0])))
    b.physicsBody = .init(type: .static, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.sync()
    #expect(physics.node(of: try #require(physics.body(of: a))) === a)
    #expect(physics.node(of: try #require(physics.body(of: b))) === b)

    // Static to dynamic rebuilds the body.
    let oldB = try #require(physics.body(of: b))
    b.physicsBody?.type = .dynamic
    physics.sync()
    let newB = try #require(physics.body(of: b))
    #expect(physics.node(of: newB) === b)
    if newB != oldB {
        #expect(physics.node(of: oldB) == nil)
    }

    let bodyA = try #require(physics.body(of: a))
    a.removeFromParent()
    physics.sync()
    #expect(physics.node(of: bodyA) == nil || physics.node(of: bodyA) === b)
}

@Test
func bodiesFollowTheGraph() throws {
    let root = SceneGraph.Node()
    let ball = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 5, 0])))
    ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.sync()
    #expect(physics.body(of: ball) != nil)
    #expect(physics.world.bodyCount == 1)
    // Hidden: the body is kept but out of the simulation (#424).
    ball.isVisible = false
    physics.sync()
    let body = try #require(physics.body(of: ball))
    #expect(!physics.world.isAdded(body))
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
    let ball = root.addChild(SceneGraph.Node())
    ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root), gravity: .zero)
    physics.setVelocity([3, 0, 0], of: ball)
    run(physics, seconds: 1)
    #expect(abs(ball.worldPosition.x - 3) < 0.1)
}

// #415: changing a node's physicsBody updates the same body, so it keeps moving.
@Test
func changingPhysicsBodyKeepsItsMotion() throws {
    let root = SceneGraph.Node()
    let ball = root.addChild(SceneGraph.Node())
    ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root), gravity: .zero)
    physics.setVelocity([3, 0, 0], of: ball)
    let changes: [(inout SceneGraph.PhysicsBody) -> Void] = [
        { $0.friction = 0.9 },
        { $0.restitution = 0.8 },
        { $0.mass = 4 },
        { $0.shape = .box(size: [1, 1, 1]) }
    ]
    for change in changes {
        var description = try #require(ball.physicsBody)
        change(&description)
        ball.physicsBody = description
        physics.step(deltaTime: 1 / 60)
        let velocity = try #require(physics.velocity(of: ball))
        #expect(abs(velocity.x - 3) < 0.01, "after \(description): velocity \(velocity)")
    }
    let body = try #require(physics.body(of: ball))
    #expect(abs(physics.world.friction(of: body) - 0.9) < 1e-5)
    #expect(abs(physics.world.mass(of: body) - 4) < 1e-3)
}

// #424: hiding a node pauses its body; showing it again resumes the same motion.
@Test
func hiddenNodeKeepsItsBodysMotion() throws {
    let root = SceneGraph.Node()
    let ball = root.addChild(SceneGraph.Node())
    ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.5))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root), gravity: .zero)
    physics.setVelocity([3, 0, 0], of: ball)
    let body = try #require(physics.body(of: ball))
    ball.isVisible = false
    run(physics, seconds: 0.5)
    // Paused while hidden: it does not move.
    #expect(abs(ball.worldPosition.x) < 1e-4)
    ball.isVisible = true
    physics.step(deltaTime: 1 / 60)
    #expect(physics.body(of: ball) == body)
    let velocity = try #require(physics.velocity(of: ball))
    #expect(abs(velocity.x - 3) < 0.01, "velocity \(velocity)")
}

@Test
func kinematicBodyFollowsItsNodeAndPushes() throws {
    let root = SceneGraph.Node()
    let pusher = root.addChild(SceneGraph.Node(transform: .init(translation: [-3, 0, 0])))
    pusher.physicsBody = .init(type: .kinematic, shape: .box(size: [1, 1, 1]))
    let box = root.addChild(SceneGraph.Node())
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root), gravity: .zero)
    for _ in 0..<120 {
        pusher.transform.translation.x += 4.0 / 60
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
    let floor = root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])), content: .mesh(MetalMesh(mesh: .quad(extents: [20, 20]), device: device), material: Unlit())))
    floor.physicsBody = .init(type: .static, shape: .mesh)
    // A box whose mesh sits 1 above its origin.
    let mesh = MetalMesh(mesh: Mesh.box(extents: [1, 1, 1]).translated(by: [0, 1, 0]), device: device)
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 4, 0]), content: .mesh(mesh, material: Unlit())))
    box.physicsBody = .init(type: .dynamic, shape: .boundingBox)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 4)
    // The mesh bottom (origin + 0.5) rests on y = 0.
    #expect(abs(box.worldPosition.y + 0.5) < 0.05)
}

private struct Unlit: SceneMaterial {}

// #426: points that do not span a volume cannot make a convex hull; Jolt's hull builder trapped on them.
@Test
func degenerateConvexHullGetsNoBody() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func mesh(_ positions: [SIMD3<Float>]) -> MetalMesh {
        MetalMesh(device: device, attributes: [.positions(positions)], submeshes: [MetalMesh.SubmeshIndices(label: "Points", indices: positions.indices.map { UInt32($0) }, primitiveType: .point)], label: "Degenerate")
    }
    let cases: [[SIMD3<Float>]] = [
        Array(repeating: [1, 2, 3], count: 6),
        (0..<6).map { [Float($0), Float($0) * 2, 0] },
        [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [0.5, 0.5, 0]]
    ]
    let root = SceneGraph.Node()
    let nodes = cases.map { positions in
        let node = root.addChild(SceneGraph.Node(content: .mesh(mesh(positions), material: Unlit())))
        node.physicsBody = .init(type: .dynamic, shape: .convexHull)
        return node
    }
    let solid = root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: Mesh.box(extents: [1, 1, 1]), device: device), material: Unlit())))
    solid.physicsBody = .init(type: .dynamic, shape: .convexHull)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.sync()
    for node in nodes {
        #expect(physics.body(of: node) == nil)
    }
    #expect(physics.body(of: solid) != nil)
}

// #425: Jolt supports triangle-mesh shapes only on static and kinematic bodies.
@Test
func dynamicMeshShapeGetsNoBody() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    let mesh = MetalMesh(mesh: Mesh.box(extents: [1, 1, 1]), device: device)
    let dynamic = root.addChild(SceneGraph.Node(content: .mesh(mesh, material: Unlit())))
    dynamic.physicsBody = .init(type: .dynamic, shape: .mesh)
    let kinematic = root.addChild(SceneGraph.Node(content: .mesh(mesh, material: Unlit())))
    kinematic.physicsBody = .init(type: .kinematic, shape: .mesh)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.sync()
    #expect(physics.body(of: dynamic) == nil)
    #expect(physics.body(of: kinematic) != nil)
}

// #125: the slider constraint stops a node at physics bodies and lets it slide along them.
@Test
func sliderConstraintStopsAtWallAndSlides() throws {
    let root = SceneGraph.Node()
    // A wall whose near face is the plane x = 2.
    let wall = root.addChild(SceneGraph.Node(label: "Wall", transform: .init(translation: [2.5, 0, 0])))
    wall.physicsBody = .init(type: .static, shape: .box(size: [1, 10, 10]))
    let ignored = root.addChild(SceneGraph.Node(label: "Other Category", transform: .init(translation: [-2.5, 0, 0])))
    ignored.physicsBody = .init(type: .static, shape: .box(size: [1, 10, 10]))
    ignored.categoryBitMask = 0b10
    let mover = root.addChild(SceneGraph.Node())
    let sceneGraph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
    physics.sync()
    mover.constraints = [physics.sliderConstraint(radius: 0.5, categoryBitMask: 0b01)]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)

    // Straight into the wall: stops with its sphere touching the face.
    mover.transform.translation = [5, 0, 0]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.transform.translation.x - 1.5) < 0.05)

    // Diagonally into the wall: blocked in x, free in z.
    mover.transform.translation = [4, 0, 3]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.transform.translation.x - 1.5) < 0.05)
    #expect(abs(mover.transform.translation.z - 3) < 0.05)

    // Bodies outside the category do not block.
    mover.transform.translation = [-5, 0, 3]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.transform.translation.x + 5) < 0.05)
}

// #418: the sweep skips the node's own bodies and its descendants'; they do not block it.
@Test
func sliderConstraintIgnoresItsOwnBodies() throws {
    let root = SceneGraph.Node()
    let mover = root.addChild(SceneGraph.Node())
    mover.physicsBody = .init(type: .kinematic, shape: .box(size: [1, 1, 1]))
    let child = mover.addChild(SceneGraph.Node(transform: .init(translation: [1, 0, 0])))
    child.physicsBody = .init(type: .kinematic, shape: .box(size: [1, 1, 1]))
    let wall = root.addChild(SceneGraph.Node(transform: .init(translation: [6.5, 0, 0])))
    wall.physicsBody = .init(type: .static, shape: .box(size: [1, 10, 10]))
    let sceneGraph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
    physics.sync()
    mover.constraints = [physics.sliderConstraint(radius: 0.5)]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    // Through its own child's box, then up to the wall's face at x = 6.
    mover.transform.translation = [10, 0, 0]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(abs(mover.transform.translation.x - 5.5) < 0.05, "at \(mover.transform.translation)")
}

// #427: the slider constraint drops what it stored for nodes that no longer exist.
@Test
func sliderConstraintForgetsRemovedNodes() throws {
    let root = SceneGraph.Node()
    let sceneGraph = SceneGraph(root: root)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
    let state = SliderState()
    let constraint = physics.sliderConstraint(radius: 0.5, state: state)
    // Kept alive, so no new node reuses a removed node's address.
    var removed: [SceneGraph.Node] = []
    for _ in 0..<5 {
        let node = root.addChild(SceneGraph.Node())
        node.constraints = [constraint]
        sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
        node.removeFromParent()
        removed.append(node)
    }
    let survivor = root.addChild(SceneGraph.Node())
    survivor.constraints = [constraint]
    sceneGraph.applyConstraints(pointOfView: matrix_identity_float4x4)
    #expect(state.positions.count == 1)
}

// A scaled, tumbling body must keep its scale: each step writes the body's pose back into the node's transform.
@Test
func decomposingScaledRotationsKeepsScale() {
    var generator = SystemRandomNumberGenerator()
    var worst: (error: Float, rotation: simd_quatf, scale: SIMD3<Float>) = (0, simd_quatf(), .zero)
    for _ in 0..<10_000 {
        let rotation = simd_normalize(simd_quatf(vector: SIMD4<Float>.random(in: -1...1, using: &generator)))
        let pose = Transform3D(translation: [1, 2, 3], rotation: rotation, scale: [0.0625, 0.0625, 0.0625])
        let back = Transform3D(nearestTo: pose.matrix)
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
    let once = Transform3D(nearestTo: pose.matrix)
    #expect(abs(simd_length(once.rotation.quaternion.vector) - 1) < 1e-5, "rotation length \(simd_length(once.rotation.quaternion.vector))")
    // The same rotation, as q or -q (GeometryLite3D #42).
    #expect(abs(abs(simd_dot(once.rotation.quaternion.vector, pose.rotation.quaternion.vector)) - 1) < 1e-4, "rotation \(pose.rotation.quaternion.vector) came back \(once.rotation.quaternion.vector)")
    let twice = Transform3D(nearestTo: once.matrix)
    #expect(simd_distance(twice.scale, pose.scale) < 1e-5, "scale \(pose.scale) came back \(twice.scale)")
}

@Test
func tumblingScaledBodyKeepsItsScale() throws {
    let root = SceneGraph.Node()
    _ = makeFloor(in: root)
    let die = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, 0], rotation: simd_quatf(angle: 0.7, axis: simd_normalize([1, 2, 3])), scale: [0.0625, 0.0625, 0.0625])))
    die.physicsBody = .init(type: .dynamic, shape: .box(size: [8, 8, 8]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    physics.setAngularVelocity([12, -9, 15], of: die)
    run(physics, seconds: 3)
    let scale = die.transform.scale
    #expect(simd_distance(scale, [0.0625, 0.0625, 0.0625]) < 1e-4, "scale drifted to \(scale)")
}

// #411: a trigger body detects overlaps but does not block other bodies.
@Test
func dynamicBoxFallsThroughTriggerFloor() throws {
    let root = SceneGraph.Node()
    let floor = makeFloor(in: root)
    floor.physicsBody?.isTrigger = true
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, 0])))
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 2)
    #expect(box.worldPosition.y < -2, "box at \(box.worldPosition)")
}

// #412: bodies collide only when each body's category is in the other's collision mask.
@Test
func collisionMasksChooseWhichBodiesCollide() throws {
    let root = SceneGraph.Node()
    let floor = makeFloor(in: root)
    floor.physicsBody?.categoryBitMask = 0b10
    // Collides with the floor.
    let solid = root.addChild(SceneGraph.Node(transform: .init(translation: [-3, 2, 0])))
    solid.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    // Its mask leaves out the floor's category, so it falls through.
    let ghost = root.addChild(SceneGraph.Node(transform: .init(translation: [3, 2, 0])))
    ghost.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]), collisionBitMask: 0b01)
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 2)
    #expect(abs(solid.worldPosition.y - 0.5) < 0.05, "solid at \(solid.worldPosition)")
    #expect(ghost.worldPosition.y < -2, "ghost at \(ghost.worldPosition)")
    // Changing the mask of an existing body takes effect: the floor now leaves out the solid box's category.
    floor.physicsBody?.collisionBitMask = 0
    run(physics, seconds: 2)
    #expect(solid.worldPosition.y < -2, "solid at \(solid.worldPosition)")
}

// #423: contacts are reported once when two nodes start touching and once when they stop, after the step.
@Test
func contactsReportBeginAndEndByNode() throws {
    let root = SceneGraph.Node()
    let floor = makeFloor(in: root)
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, 0])))
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    var events: [SceneGraphPhysicsWorld.Contact] = []
    physics.contactHandler = { events.append($0) }
    run(physics, seconds: 2)
    // Landing can bounce, so a pair may begin and end more than once, but phases alternate.
    let phases = events.map(\.phase)
    #expect(phases.first == .began)
    #expect(phases.last == .began)
    #expect(zip(phases, phases.dropFirst()).allSatisfy { $0 != $1 }, "\(phases)")
    #expect(events.allSatisfy { Set([ObjectIdentifier($0.nodeA), ObjectIdentifier($0.nodeB)]) == Set([ObjectIdentifier(floor), ObjectIdentifier(box)]) })
    #expect(physics.contacts(of: box).map(ObjectIdentifier.init) == [ObjectIdentifier(floor)])
    // Asleep: Jolt removed the contact and adds it again on waking; neither is reported.
    #expect(!physics.world.isActive(try #require(physics.body(of: box))))
    events.removeAll()
    physics.setVelocity([0, 8, 0], of: box)
    run(physics, seconds: 0.25)
    #expect(events.map(\.phase) == [.ended], "\(events.map(\.phase))")
    #expect(physics.contacts(of: box).isEmpty)
}

// #421: solver and sleep settings can be read and changed.
@Test
func solverAndSleepSettingsAreTunable() throws {
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: SceneGraph.Node()))
    var settings = physics.settings
    settings.velocitySteps = 20
    settings.positionSteps = 5
    settings.timeBeforeSleep = 2
    settings.allowSleeping = false
    physics.settings = settings
    #expect(physics.settings == settings)
    #expect(physics.world.settings.velocitySteps == 20)
}

// #411: turning a body into a trigger after it was created lets bodies pass through it.
@Test
func floorBecomesTriggerAfterCreation() throws {
    let root = SceneGraph.Node()
    let floor = makeFloor(in: root)
    let box = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 2, 0])))
    box.physicsBody = .init(type: .dynamic, shape: .box(size: [1, 1, 1]))
    let physics = try SceneGraphPhysicsWorld(sceneGraph: SceneGraph(root: root))
    run(physics, seconds: 2)
    #expect(abs(box.worldPosition.y - 0.5) < 0.05)
    floor.physicsBody?.isTrigger = true
    run(physics, seconds: 2)
    #expect(box.worldPosition.y < -2, "box at \(box.worldPosition)")
}
