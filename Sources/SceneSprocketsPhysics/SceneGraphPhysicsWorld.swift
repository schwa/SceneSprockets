import GeometryLite3D
import JoltPhysics
import SceneSprockets
import simd
import SwiftMesh

/// A Jolt simulation of the nodes in a scene graph that have a `physicsBody`.
///
/// Each ``step(deltaTime:collisionSteps:)`` does these things in order:
///
/// - It adds bodies for new nodes, and removes the bodies of removed or hidden nodes.
/// - It rebuilds the bodies whose `physicsBody` changed.
/// - It moves kinematic bodies to their nodes.
/// - It advances the simulation.
/// - It writes the world position and orientation of each dynamic body to its node. Scale does not change.
///
/// Writing poses changes only the transform revision of the scene graph.
public final class SceneGraphPhysicsWorld {
    /// The scene graph whose nodes the world simulates.
    public let sceneGraph: SceneGraph
    /// The Jolt world, for anything this type does not wrap (constraints, contacts, queries).
    public let world: PhysicsWorld

    struct Entry {
        var node: SceneGraph.Node
        var body: BodyID
        var description: SceneGraph.PhysicsBody
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]

    /// Creates a physics world for a scene graph.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene graph to simulate.
    ///   - gravity: The acceleration of gravity in world space, in meters per second squared.
    /// - Throws: An error if the Jolt engine cannot start.
    public init(sceneGraph: SceneGraph, gravity: SIMD3<Float> = [0, -9.81, 0]) throws {
        self.sceneGraph = sceneGraph
        world = PhysicsWorld(engine: try JoltEngine(), gravity: gravity)
    }

    /// The acceleration of gravity in world space, in meters per second squared.
    public var gravity: SIMD3<Float> {
        get { world.gravity }
        set { world.gravity = newValue }
    }

    /// The Jolt body of `node`, once a step or sync has created it.
    public func body(of node: SceneGraph.Node) -> BodyID? {
        entries[ObjectIdentifier(node)]?.body
    }

    /// Returns the linear velocity of the node's body, or `nil` if the node has no body yet.
    public func velocity(of node: SceneGraph.Node) -> SIMD3<Float>? {
        body(of: node).map { world.linearVelocity(of: $0) }
    }

    /// Sets the linear velocity of the node's body, in world units per second.
    ///
    /// The method calls ``sync()`` first, so it works for a node that was added after the last step.
    public func setVelocity(_ velocity: SIMD3<Float>, of node: SceneGraph.Node) {
        sync()
        if let body = body(of: node) {
            world.setLinearVelocity(of: body, to: velocity)
        }
    }

    /// Sets the angular velocity of the node's body, in radians per second about each world axis.
    ///
    /// The method calls ``sync()`` first, like ``setVelocity(_:of:)``.
    public func setAngularVelocity(_ velocity: SIMD3<Float>, of node: SceneGraph.Node) {
        sync()
        if let body = body(of: node) {
            world.setAngularVelocity(of: body, to: velocity)
        }
    }

    /// Adds an impulse to the node's body at its center of mass.
    ///
    /// The method calls ``sync()`` first, like ``setVelocity(_:of:)``.
    public func applyImpulse(_ impulse: SIMD3<Float>, to node: SceneGraph.Node) {
        sync()
        if let body = body(of: node) {
            world.addImpulse(to: body, impulse: impulse)
        }
    }

    /// Advances the simulation and writes the new poses to the nodes.
    ///
    /// - Parameters:
    ///   - deltaTime: The time to advance, in seconds. A value of zero or less does nothing.
    ///   - collisionSteps: The number of collision steps in this update. Use more steps for fast or small bodies.
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

    /// Adds, removes and rebuilds bodies to match the visible nodes that have a `physicsBody`.
    ///
    /// ``step(deltaTime:collisionSteps:)`` calls this method. Call it yourself to get the body of a new node before
    /// the next step.
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
