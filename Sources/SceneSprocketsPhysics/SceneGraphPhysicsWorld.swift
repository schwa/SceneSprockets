import GeometryLite3D
import JoltPhysics
import os
import SceneSprockets
import simd
import SwiftMesh

/// A Jolt simulation of the nodes in a scene graph that have a `physicsBody`.
///
/// Each ``step(deltaTime:collisionSteps:)`` does these things in order:
///
/// - It adds bodies for new nodes, removes the bodies of removed nodes, and pauses the bodies of hidden nodes.
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
        // Velocities from when the node was hidden: Jolt zeroes them when it takes a body out of the simulation.
        var pausedVelocity: (linear: SIMD3<Float>, angular: SIMD3<Float>)?
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]
    // Nodes already warned about, so a rejected body is reported once, not every step.
    private var warnedNodes: Set<SceneGraph.Node.ID> = []

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
        for entry in entries.values where entry.description.type == .kinematic && world.isAdded(entry.body) {
            let pose = Transform3D(nearestTo: entry.node.worldTransform)
            world.moveKinematic(entry.body, to: pose.translation, rotation: pose.rotation.quaternion, deltaTime: deltaTime)
        }
        world.update(deltaTime: deltaTime, collisionSteps: collisionSteps)
        for entry in entries.values where entry.description.type == .dynamic && world.isAdded(entry.body) {
            var pose = Transform3D(nearestTo: entry.node.worldTransform)
            pose.translation = world.position(of: entry.body)
            pose.rotation = Rotation3D(world.rotation(of: entry.body))
            entry.node.worldTransform = pose.matrix
        }
    }

    /// Adds, removes and rebuilds bodies to match the nodes that have a `physicsBody`.
    ///
    /// Hiding a node (or an ancestor) takes its body out of the simulation without destroying it, so the body keeps its
    /// motion and resumes when the node shows again.
    ///
    /// ``step(deltaTime:collisionSteps:)`` calls this method. Call it yourself to get the body of a new node before
    /// the next step.
    public func sync() {
        var visible: Set<ObjectIdentifier> = []
        sceneGraph.visit { node, _ in
            if node.physicsBody != nil {
                visible.insert(ObjectIdentifier(node))
            }
        }
        var seen: Set<ObjectIdentifier> = []
        sceneGraph.visit(includeHidden: true) { node, _ in
            guard let description = node.physicsBody else {
                return
            }
            let key = ObjectIdentifier(node)
            let isVisible = visible.contains(key)
            seen.insert(key)
            if var entry = entries[key] {
                if entry.description == description {
                    setInWorld(&entry, isVisible)
                    entries[key] = entry
                    return
                }
                destroy(entry)
                entries[key] = nil
            }
            // Hidden nodes get their body when they first show.
            if isVisible, let body = makeBody(for: node, description: description) {
                entries[key] = Entry(node: node, body: body, description: description)
            }
        }
        for (key, entry) in entries where !seen.contains(key) {
            destroy(entry)
            entries[key] = nil
        }
    }

    // Pauses or resumes a body with its node's visibility (#424). A node moved while hidden takes its body along.
    private func setInWorld(_ entry: inout Entry, _ isVisible: Bool) {
        let isAdded = world.isAdded(entry.body)
        if isVisible, !isAdded {
            let pose = Transform3D(nearestTo: entry.node.worldTransform)
            if simd_distance(pose.translation, world.position(of: entry.body)) > 1e-5 {
                world.setPositionAndRotation(of: entry.body, position: pose.translation, rotation: pose.rotation.quaternion, activate: false)
            }
            world.addToWorld(entry.body)
            if let velocity = entry.pausedVelocity {
                world.setLinearVelocity(of: entry.body, to: velocity.linear)
                world.setAngularVelocity(of: entry.body, to: velocity.angular)
                entry.pausedVelocity = nil
            }
        } else if !isVisible, isAdded {
            if entry.description.type == .dynamic {
                entry.pausedVelocity = (world.linearVelocity(of: entry.body), world.angularVelocity(of: entry.body))
            }
            world.removeFromWorld(entry.body)
        }
    }

    private func destroy(_ entry: Entry) {
        if world.isAdded(entry.body) {
            world.removeBody(entry.body)
        } else {
            world.destroyBody(entry.body)
        }
    }

    private static let logger = Logger(subsystem: "io.schwa.SceneSprockets", category: "Physics")

    private func makeBody(for node: SceneGraph.Node, description: SceneGraph.PhysicsBody) -> BodyID? {
        // Jolt supports triangle-mesh shapes only on static and kinematic bodies (#425).
        if description.type == .dynamic, description.shape == .mesh {
            guard warnedNodes.insert(node.id).inserted else {
                return nil
            }
            Self.logger.warning("Node \(node.label ?? "(unlabeled)", privacy: .public) has a dynamic physics body with shape .mesh, which Jolt does not support; it gets no body. Use .convexHull instead.")
            return nil
        }
        let pose = Transform3D(nearestTo: node.worldTransform)
        guard let shape = joltShape(description.shape, node: node, scale: simd_abs(pose.scale)) else {
            return nil
        }
        let motionType: MotionType = switch description.type {
        case .static: .static
        case .dynamic: .dynamic
        case .kinematic: .kinematic
        }
        let body = world.addBody(shape, position: pose.translation, rotation: pose.rotation.quaternion, motionType: motionType, restitution: description.restitution, friction: description.friction)
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
            return Self.spansVolume(points) ? .convexHull(points: points) : nil
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

    // Jolt's hull builder traps unless the points span a volume: not all the same, on one line or on one plane (#426).
    static func spansVolume(_ points: [SIMD3<Float>]) -> Bool {
        guard points.count >= 4, let first = points.first else {
            return false
        }
        let farthest = points.max { simd_distance($0, first) < simd_distance($1, first) } ?? first
        let length = simd_distance(farthest, first)
        let tolerance = max(length * 1e-3, 1e-6)
        guard length > tolerance else {
            return false
        }
        let axis = (farthest - first) / length
        func distanceFromLine(_ point: SIMD3<Float>) -> Float {
            simd_length(simd_cross(point - first, axis))
        }
        let third = points.max { distanceFromLine($0) < distanceFromLine($1) } ?? first
        guard distanceFromLine(third) > tolerance else {
            return false
        }
        let normal = simd_normalize(simd_cross(farthest - first, third - first))
        return points.contains { abs(simd_dot($0 - first, normal)) > tolerance }
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
