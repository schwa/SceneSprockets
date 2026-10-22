import GeometryLite3D
import JoltPhysics
import SceneSprocket
import SwiftMesh
import simd

// Simulates the scene graph's nodes that have a physicsBody, with Jolt. Each step adds bodies for new nodes,
// removes bodies for removed or hidden nodes, rebuilds bodies whose description changed, moves kinematic bodies to
// their nodes, advances the simulation and writes dynamic bodies' poses back to their nodes (world position and
// orientation; scale is kept). Writing only changes the transform revision.
public final class SceneGraphPhysicsWorld {
    public let sceneGraph: SceneGraph
    // The Jolt world, for anything this type does not wrap (constraints, contacts, queries).
    public let world: PhysicsWorld

    struct Entry {
        var node: SceneGraph.Node
        var body: BodyID
        var description: SceneGraph.PhysicsBody
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]

    public init(sceneGraph: SceneGraph, gravity: SIMD3<Float> = [0, -9.81, 0]) throws {
        self.sceneGraph = sceneGraph
        world = PhysicsWorld(engine: try JoltEngine(), gravity: gravity)
    }

    public var gravity: SIMD3<Float> {
        get { world.gravity }
        set { world.gravity = newValue }
    }

    // The Jolt body of `node`, once a step or sync has created it.
    public func body(of node: SceneGraph.Node) -> BodyID? {
        entries[ObjectIdentifier(node)]?.body
    }

    public func velocity(of node: SceneGraph.Node) -> SIMD3<Float>? {
        body(of: node).map { world.linearVelocity(of: $0) }
    }

    // Syncs first, so it works on a node added since the last step.
    public func setVelocity(_ velocity: SIMD3<Float>, of node: SceneGraph.Node) {
        sync()
        if let body = body(of: node) {
            world.setLinearVelocity(of: body, to: velocity)
        }
    }

    // Radians per second about each world axis. Syncs first, like setVelocity.
    public func setAngularVelocity(_ velocity: SIMD3<Float>, of node: SceneGraph.Node) {
        sync()
        if let body = body(of: node) {
            world.setAngularVelocity(of: body, to: velocity)
        }
    }

    public func applyImpulse(_ impulse: SIMD3<Float>, to node: SceneGraph.Node) {
        sync()
        if let body = body(of: node) {
            world.addImpulse(to: body, impulse: impulse)
        }
    }

    public func step(deltaTime: Float, collisionSteps: Int = 1) {
        guard deltaTime > 0 else {
            return
        }
        sync()
        for entry in entries.values where entry.description.type == .kinematic {
            let pose = Transform3D(decomposing: entry.node.worldTransform)
            world.moveKinematic(entry.body, to: pose.translation, rotation: pose.rotation, deltaTime: deltaTime)
        }
        world.update(deltaTime: deltaTime, collisionSteps: collisionSteps)
        for entry in entries.values where entry.description.type == .dynamic {
            var pose = Transform3D(decomposing: entry.node.worldTransform)
            pose.translation = world.position(of: entry.body)
            pose.rotation = world.rotation(of: entry.body)
            entry.node.worldTransform = pose.matrix
        }
    }

    // Matches bodies to the graph's visible nodes with a physicsBody. `step` calls it.
    public func sync() {
        var seen: Set<ObjectIdentifier> = []
        sceneGraph.visit { node, _ in
            guard let description = node.physicsBody else {
                return
            }
            let key = ObjectIdentifier(node)
            seen.insert(key)
            if let entry = entries[key] {
                guard entry.description != description else {
                    return
                }
                world.removeBody(entry.body)
                entries[key] = nil
            }
            if let body = makeBody(for: node, description: description) {
                entries[key] = Entry(node: node, body: body, description: description)
            }
        }
        for (key, entry) in entries where !seen.contains(key) {
            world.removeBody(entry.body)
            entries[key] = nil
        }
    }

    private func makeBody(for node: SceneGraph.Node, description: SceneGraph.PhysicsBody) -> BodyID? {
        let pose = Transform3D(decomposing: node.worldTransform)
        guard let shape = joltShape(description.shape, node: node, scale: simd_abs(pose.scale)) else {
            return nil
        }
        let motionType: MotionType = switch description.type {
        case .static: .static
        case .dynamic: .dynamic
        case .kinematic: .kinematic
        }
        let body = world.addBody(shape, position: pose.translation, rotation: pose.rotation, motionType: motionType, restitution: description.restitution, friction: description.friction)
        if description.type == .dynamic, let mass = description.mass {
            world.setMass(of: body, to: mass)
        }
        return body
    }

    // Nil when the shape needs a mesh and the node has none (or none usable).
    private func joltShape(_ shape: SceneGraph.PhysicsBody.Shape, node: SceneGraph.Node, scale: SIMD3<Float>) -> Shape? {
        switch shape {
        case .box(let size):
            return box(halfExtents: size * scale / 2)
        case .sphere(let radius):
            return .sphere(radius: radius * scale.max())
        case let .capsule(height, radius):
            let scaledRadius = radius * max(scale.x, scale.z)
            return .capsule(halfHeightOfCylinder: max(height * scale.y / 2 - scaledRadius, 0.001), radius: scaledRadius)
        case let .cylinder(height, radius):
            return .cylinder(halfHeight: height * scale.y / 2, radius: radius * max(scale.x, scale.z))
        case .boundingBox:
            guard let bounds = node.meshBounds else {
                return nil
            }
            let center = bounds.center * scale
            let boxShape = box(halfExtents: bounds.size * scale / 2)
            return simd_length(center) < 1e-6 ? boxShape : .compound([CompoundChild(boxShape, position: center)])
        case .convexHull:
            let points = meshPositions(node).map { $0 * scale }
            return points.count >= 4 ? .convexHull(points: points) : nil
        case .mesh:
            guard case let .mesh(mesh, _, _, _) = node.content else {
                return nil
            }
            let indices = mesh.submeshes.filter { $0.primitiveType == .triangle }.flatMap(\.indices)
            guard !indices.isEmpty else {
                return nil
            }
            return .mesh(vertices: mesh.positions().map { $0 * scale }, indices: indices)
        }
    }

    // Jolt boxes need half extents larger than the convex radius.
    private func box(halfExtents: SIMD3<Float>) -> Shape {
        let convexRadius = min(0.05, halfExtents.min() * 0.5)
        return .box(halfExtents: simd_max(halfExtents, SIMD3(repeating: 1e-3)), convexRadius: convexRadius)
    }

    private func meshPositions(_ node: SceneGraph.Node) -> [SIMD3<Float>] {
        guard case let .mesh(mesh, _, _, _) = node.content else {
            return []
        }
        return mesh.positions()
    }
}
