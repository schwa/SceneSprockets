import GeometryLite3D
import JoltPhysics
import os
import SceneSprockets
import simd
import SwiftMesh
import Synchronization

/// A Jolt simulation of the nodes in a scene graph that have a `physicsBody`.
///
/// Each ``step(deltaTime:collisionSteps:)`` does these things in order:
///
/// - It adds bodies for new nodes, removes the bodies of removed nodes, and pauses the bodies of hidden nodes.
/// - It rebuilds the bodies whose `physicsBody` changed.
/// - It moves kinematic bodies to their nodes.
/// - It advances the simulation.
/// - It writes the world position and orientation of each awake dynamic body to its node. Scale does not change.
///
/// Writing poses changes only the transform revision of the scene graph.
public final class SceneGraphPhysicsWorld {
    /// The scene graph whose nodes the world simulates.
    public let sceneGraph: SceneGraph
    /// The Jolt world, for anything this type does not wrap (constraints, contacts, queries).
    ///
    /// Do not replace its `contactListener`: the world uses it to apply collision masks.
    public let world: PhysicsWorld

    struct Entry {
        var node: SceneGraph.Node
        var body: BodyID
        var description: SceneGraph.PhysicsBody
        // Velocities from when the node was hidden: Jolt zeroes them when it takes a body out of the simulation.
        var pausedVelocity: (linear: SIMD3<Float>, angular: SIMD3<Float>)?
    }

    private(set) var entries: [ObjectIdentifier: Entry] = [:]
    // The key in `entries` of each body, so finding a body's node does not scan every entry (#417).
    private(set) var entryKeysByBody: [BodyID: ObjectIdentifier] = [:]
    // Nodes already warned about, so a rejected body is reported once, not every step.
    private var warnedNodes: Set<SceneGraph.Node.ID> = []
    // Applies collision masks (#412) and records contacts (#423).
    private let contactListener = SceneContactListener()
    // The touching body pairs, with how many sub-shape pairs touch. A pair begins at 1 and ends at 0.
    private var touchingPairs: [SceneContactListener.BodyPair: Int] = [:]
    // Sub-shape contacts Jolt removed because the bodies fell asleep, which it adds again when they wake.
    private var sleptContacts: [SceneContactListener.BodyPair: Int] = [:]

    /// Two nodes' bodies starting or stopping touching.
    public struct Contact {
        /// Whether the bodies started or stopped touching.
        public enum Phase: Sendable, Equatable {
            case began
            case ended
        }

        public var phase: Phase
        public var nodeA: SceneGraph.Node
        public var nodeB: SceneGraph.Node
        /// The world-space contact point, on `nodeA`'s body. Zero for `.ended`.
        public var point: SIMD3<Float>
        /// The world-space contact normal, from `nodeA` toward `nodeB`. Zero for `.ended`.
        public var normal: SIMD3<Float>
        /// How far the bodies overlap. Zero for `.ended`.
        public var penetrationDepth: Float
        /// How hard the bodies hit: the impulse along the normal that the solver is predicted to apply, in newton
        /// seconds, summed over the contact points. Use it to scale impact sounds, damage or particles. Zero for
        /// `.ended` and for triggers.
        public var impulse: Float = 0
        /// For a `.mesh` shape, the submesh of `nodeA`'s mesh that is touched (#429); nil for other shapes and `.ended`.
        public var submeshIndexA: Int?
        /// The same for `nodeB`.
        public var submeshIndexB: Int?
    }

    /// Where a ray first hits a body.
    public struct RayHit {
        public var node: SceneGraph.Node
        /// The world-space hit point.
        public var position: SIMD3<Float>
        /// How far along the ray, from 0 at its origin to 1 at `origin + direction`.
        public var fraction: Float
        /// The node's `SceneGraph.PhysicsBody.surface` tag.
        public var surface: String?
        /// For a `.mesh` shape, the submesh of the node's mesh that is hit; nil for other shapes.
        public var submeshIndex: Int?
    }

    /// The first body that the segment from `origin` to `origin + direction` hits, or nil.
    ///
    /// The method calls ``sync()`` first, so it sees nodes added since the last step.
    public func castRay(from origin: SIMD3<Float>, direction: SIMD3<Float>) -> RayHit? {
        sync()
        guard let hit = world.castRay(origin: origin, direction: direction), let node = node(of: hit.body) else {
            return nil
        }
        return RayHit(node: node, position: hit.position, fraction: hit.fraction, surface: node.physicsBody?.surface, submeshIndex: world.triangleUserData(of: hit.body, at: hit.subShape).map(Int.init))
    }

    /// A body of water (or other fluid): an axis-aligned world-space region whose top face is the surface. Dynamic
    /// bodies in it get buoyancy and drag every step (#436).
    public struct Fluid: Sendable, Equatable {
        /// The fluid's extent; the surface is at `region.max.y`.
        public var region: BoundingBox3D
        /// 1 is neutral, below 1 sinks, above 1 floats: the fluid's density relative to the bodies'.
        public var buoyancy: Float
        /// Slows bodies moving through the fluid.
        public var linearDrag: Float
        /// Slows bodies spinning in the fluid.
        public var angularDrag: Float
        /// The fluid's own velocity, for currents and rivers.
        public var flowVelocity: SIMD3<Float>

        public init(region: BoundingBox3D, buoyancy: Float = 1.5, linearDrag: Float = 0.5, angularDrag: Float = 0.05, flowVelocity: SIMD3<Float> = .zero) {
            self.region = region
            self.buoyancy = buoyancy
            self.linearDrag = linearDrag
            self.angularDrag = angularDrag
            self.flowVelocity = flowVelocity
        }
    }

    /// The fluids that dynamic bodies float in.
    public var fluids: [Fluid] = []

    /// The character controllers added with ``addCharacter(for:height:radius:mass:maxSlopeAngle:)``.
    public internal(set) var characters: [CharacterController] = []

    /// The joints added with ``addJoint(_:between:and:breakingImpulse:)`` that still hold.
    public internal(set) var joints: [PhysicsJoint] = []
    /// Called after a step for each joint that broke because its load went over its `breakingImpulse`. A joint
    /// whose node's body is removed or rebuilt is dropped without calling it.
    public var jointBreakHandler: ((PhysicsJoint) -> Void)?

    /// Called before every sub-step of ``step(deltaTime:collisionSteps:)`` with the sub-step's duration, for forces
    /// that must act all the time, such as wind, magnets or custom fields: Jolt clears forces after each sub-step. Add
    /// them with ``applyForce(_:to:at:)``. While it is set, each sub-step runs as its own Jolt update.
    public var subStepHandler: ((_ physics: SceneGraphPhysicsWorld, _ deltaTime: Float) -> Void)?

    /// Called after each step for every pair of nodes whose bodies started or stopped touching during it, like
    /// SceneKit's `SCNPhysicsContactDelegate`. It runs on the thread that called ``step(deltaTime:collisionSteps:)``.
    /// Triggers report contacts too. A body that is removed or rebuilt reports no `.ended`.
    public var contactHandler: ((Contact) -> Void)?

    /// Creates a physics world for a scene graph.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene graph to simulate.
    ///   - gravity: The acceleration of gravity in world space, in meters per second squared.
    ///   - jobSystem: The threads that run the simulation, for example fewer on low-power devices, or
    ///     `.joltThreadPool(threadCount: 0)` to run on the calling thread. Fixed for the life of the world.
    /// - Throws: An error if the Jolt engine cannot start.
    public init(sceneGraph: SceneGraph, gravity: SIMD3<Float> = [0, -9.81, 0], jobSystem: JobSystemKind = .default) throws {
        self.sceneGraph = sceneGraph
        _ = Self.forwardJoltTraces
        world = PhysicsWorld(engine: try JoltEngine(), gravity: gravity, jobSystem: jobSystem)
        world.contactListener = contactListener
    }

    /// The acceleration of gravity in world space, in meters per second squared.
    public var gravity: SIMD3<Float> {
        get { world.gravity }
        set { world.gravity = newValue }
    }

    /// World-wide solver and sleep settings: solver iterations (`velocitySteps`, `positionSteps`), `baumgarte`,
    /// `penetrationSlop`, `timeBeforeSleep`, `allowSleeping` and so on. Raise the iterations for tall stacks and
    /// joint chains.
    public var settings: PhysicsSettings {
        get { world.settings }
        set { world.settings = newValue }
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

    /// Whether the node's body is awake (simulated each step). Nil if the node has no body in the simulation.
    public func isAwake(_ node: SceneGraph.Node) -> Bool? {
        sync()
        guard let body = body(of: node), world.isAdded(body) else {
            return nil
        }
        return world.isActive(body)
    }

    /// Wakes the node's body, so it moves again under gravity and contacts.
    public func wake(_ node: SceneGraph.Node) {
        sync()
        if let body = body(of: node), world.isAdded(body) {
            world.activate(body)
        }
    }

    /// Puts the node's body to sleep until something touches it or it is woken.
    public func sleep(_ node: SceneGraph.Node) {
        sync()
        if let body = body(of: node), world.isAdded(body) {
            world.deactivate(body)
        }
    }

    /// Wakes every moving body whose bounds overlap a world-space box, for example after an explosion or when a
    /// part of a level becomes active.
    public func wakeBodies(in bounds: BoundingBox3D) {
        sync()
        world.activateBodies(inBoxFrom: bounds.min, to: bounds.max)
    }

    /// Adds a force, in newtons, to the node's body for the next sub-step, at its center of mass or at a world-space
    /// point. Call it from ``subStepHandler`` to keep it acting; Jolt clears forces after every sub-step.
    public func applyForce(_ force: SIMD3<Float>, to node: SceneGraph.Node, at point: SIMD3<Float>? = nil) {
        if let body = body(of: node), world.isAdded(body) {
            world.addForce(to: body, force: force, at: point)
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
        if let subStepHandler {
            // One update per sub-step, so forces added before each one act on it; Jolt clears forces after every
            // update (#420). Fluids join in, so buoyancy also acts per sub-step.
            let steps = max(collisionSteps, 1)
            let subStep = deltaTime / Float(steps)
            for _ in 0..<steps {
                applyFluids(deltaTime: subStep)
                subStepHandler(self, subStep)
                world.update(deltaTime: subStep, collisionSteps: 1)
            }
        } else {
            applyFluids(deltaTime: deltaTime)
            world.update(deltaTime: deltaTime, collisionSteps: collisionSteps)
        }
        // Sleeping bodies do not move; writing their nodes would only bump the transform revision (#419).
        for entry in entries.values where entry.description.type == .dynamic && world.isAdded(entry.body) && world.isActive(entry.body) {
            var pose = Transform3D(nearestTo: entry.node.worldTransform)
            pose.translation = world.position(of: entry.body)
            pose.rotation = Rotation3D(world.rotation(of: entry.body))
            entry.node.worldTransform = pose.matrix
        }
        // After the bodies move, so characters stand on platforms where they are now.
        let gravity = world.gravity
        for character in characters {
            character.update(deltaTime: deltaTime, gravity: gravity)
        }
        reportContacts()
        breakOverloadedJoints()
    }

    // Buoyancy and drag for awake dynamic bodies whose bounds overlap a fluid. Jolt computes the submerged part.
    private func applyFluids(deltaTime: Float) {
        guard !fluids.isEmpty else {
            return
        }
        let gravity = world.gravity
        for entry in entries.values where entry.description.type == .dynamic && world.isAdded(entry.body) && world.isActive(entry.body) {
            guard let bounds = world.readBody(entry.body, { $0.worldSpaceBounds }) else {
                continue
            }
            for fluid in fluids where all(bounds.min .<= fluid.region.max) && all(bounds.max .>= fluid.region.min) {
                // A point on the surface above the body.
                var surface = simd_clamp((bounds.min + bounds.max) / 2, fluid.region.min, fluid.region.max)
                surface.y = fluid.region.max.y
                world.applyBuoyancyImpulse(to: entry.body, surfacePosition: surface, surfaceNormal: [0, 1, 0], buoyancy: fluid.buoyancy, linearDrag: fluid.linearDrag, angularDrag: fluid.angularDrag, fluidVelocity: fluid.flowVelocity, gravity: gravity, deltaTime: deltaTime)
            }
        }
    }

    /// The nodes whose bodies touch the body of `node` after the last step.
    public func contacts(of node: SceneGraph.Node) -> [SceneGraph.Node] {
        guard let body = body(of: node) else {
            return []
        }
        return touchingPairs.keys.compactMap { pair in
            guard pair.contains(body) else {
                return nil
            }
            return self.node(of: pair.first == body ? pair.second : pair.first)
        }
    }

    // Turns the sub-shape contacts Jolt reported during the step into per-node-pair began and ended events.
    private func reportContacts() {
        for event in contactListener.takeEvents() {
            switch event {
            case let .added(pair, point, normal, penetrationDepth, impulse, subShapes):
                if let slept = sleptContacts[pair] {
                    // The pair woke up still touching.
                    sleptContacts[pair] = slept > 1 ? slept - 1 : nil
                    continue
                }
                let count = touchingPairs[pair, default: 0]
                touchingPairs[pair] = count + 1
                if count == 0, let nodeA = node(of: pair.first), let nodeB = node(of: pair.second) {
                    // Looked up here, on the caller's thread: Jolt's body interface is not safe inside its callbacks.
                    let submeshA = world.triangleUserData(of: pair.first, at: subShapes.0).map(Int.init)
                    let submeshB = world.triangleUserData(of: pair.second, at: subShapes.1).map(Int.init)
                    contactHandler?(Contact(phase: .began, nodeA: nodeA, nodeB: nodeB, point: point, normal: normal, penetrationDepth: penetrationDepth, impulse: impulse, submeshIndexA: submeshA, submeshIndexB: submeshB))
                }
            case let .removed(pair):
                guard let count = touchingPairs[pair] else {
                    continue
                }
                // Jolt removes the contacts of bodies that fall asleep and adds them again when they wake. They still
                // touch, so neither is reported.
                if !world.isActive(pair.first), !world.isActive(pair.second), entryKeysByBody[pair.first] != nil, entryKeysByBody[pair.second] != nil {
                    sleptContacts[pair, default: 0] += 1
                    continue
                }
                touchingPairs[pair] = count > 1 ? count - 1 : nil
                if count == 1 {
                    reportEnded(pair)
                }
            }
        }
        // A pair that woke without Jolt adding its contacts again no longer touches.
        for (pair, slept) in sleptContacts where world.isActive(pair.first) || world.isActive(pair.second) {
            sleptContacts[pair] = nil
            guard let count = touchingPairs[pair] else {
                continue
            }
            touchingPairs[pair] = count > slept ? count - slept : nil
            if count <= slept {
                reportEnded(pair)
            }
        }
    }

    private func reportEnded(_ pair: SceneContactListener.BodyPair) {
        if let nodeA = node(of: pair.first), let nodeB = node(of: pair.second) {
            contactHandler?(Contact(phase: .ended, nodeA: nodeA, nodeB: nodeB, point: .zero, normal: .zero, penetrationDepth: 0))
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
                if entry.description != description, update(entry, to: description) {
                    entry.description = description
                }
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
                entryKeysByBody[body] = key
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

    // Changes the existing body to match `description`, so it keeps its motion and contacts (#415). False when the
    // body has to be rebuilt instead.
    private func update(_ entry: Entry, to description: SceneGraph.PhysicsBody) -> Bool {
        let old = entry.description
        // A body created static cannot become moving, and a static body has no motion to keep.
        guard old.type == description.type || (old.type != .static && description.type != .static) else {
            return false
        }
        // A mass that goes back to nil needs the shape's own mass, which only a new body computes.
        guard description.mass != nil || old.mass == nil else {
            return false
        }
        // Changing to a shape the body type cannot use, or to or from shapes with their own rules (planes, height
        // fields, empty), rebuilds the body.
        guard description.shape.allowedTypes.contains(description.type), description.shape.allowedTypes == old.shape.allowedTypes else {
            return false
        }
        // Jolt sets these only when it creates a body.
        guard description.allowsSleeping == old.allowsSleeping, description.allowedMotion == old.allowedMotion else {
            return false
        }
        let body = entry.body
        if description.shape != old.shape {
            let scale = simd_abs(Transform3D(nearestTo: entry.node.worldTransform).scale)
            guard let shape = joltShape(description.shape, node: entry.node, scale: scale) else {
                return false
            }
            world.setShape(of: body, to: shape, activate: world.isAdded(body))
        }
        if description.type != old.type {
            world.setMotionType(of: body, to: description.type == .dynamic ? .dynamic : .kinematic, activate: world.isAdded(body))
        }
        if description.friction != old.friction {
            world.setFriction(of: body, to: description.friction)
        }
        if description.restitution != old.restitution {
            world.setRestitution(of: body, to: description.restitution)
        }
        if description.linearDamping != old.linearDamping {
            world.setLinearDamping(of: body, to: description.linearDamping)
        }
        if description.angularDamping != old.angularDamping {
            world.setAngularDamping(of: body, to: description.angularDamping)
        }
        if description.gravityFactor != old.gravityFactor {
            world.setGravityFactor(of: body, to: description.gravityFactor)
            if world.isAdded(body) {
                world.activate(body)
            }
        }
        if description.usesContinuousCollision != old.usesContinuousCollision {
            world.setMotionQuality(of: body, to: description.usesContinuousCollision ? .linearCast : .discrete)
        }
        let masksChanged = description.categoryBitMask != old.categoryBitMask || description.collisionBitMask != old.collisionBitMask
        if masksChanged {
            contactListener.setMasks(of: body, to: description)
            // Contacts already found are kept without being validated again.
            world.invalidateContactCache(of: body)
        }
        if description.isTrigger != old.isTrigger {
            world.setIsSensor(body, to: description.isTrigger)
        }
        if masksChanged || description.isTrigger != old.isTrigger {
            // Bodies resting on it are asleep and would stay put; wake them so they react to the change.
            if let bounds = world.readBody(body, { $0.worldSpaceBounds }) {
                world.activateBodies(inBoxFrom: bounds.min, to: bounds.max)
            }
        }
        // A new shape recomputed the mass, so set it again.
        if description.type == .dynamic, let mass = description.mass, mass != old.mass || description.shape != old.shape {
            world.setMass(of: body, to: mass)
        }
        return true
    }

    private func destroy(_ entry: Entry) {
        detachJoints(using: entry.body)
        entryKeysByBody[entry.body] = nil
        contactListener.removeMasks(of: entry.body)
        touchingPairs = touchingPairs.filter { !$0.key.contains(entry.body) }
        sleptContacts = sleptContacts.filter { !$0.key.contains(entry.body) }
        if world.isAdded(entry.body) {
            world.removeBody(entry.body)
        } else {
            world.destroyBody(entry.body)
        }
    }

    // Jolt needs at least one degree of freedom; empty counts as all.
    private static func degreesOfFreedom(_ axes: SceneGraph.PhysicsBody.Axes) -> AllowedDegreesOfFreedom {
        let pairs: [(SceneGraph.PhysicsBody.Axes, AllowedDegreesOfFreedom)] = [
            (.translationX, .translationX), (.translationY, .translationY), (.translationZ, .translationZ),
            (.rotationX, .rotationX), (.rotationY, .rotationY), (.rotationZ, .rotationZ)
        ]
        let result = pairs.reduce(into: AllowedDegreesOfFreedom()) { result, pair in
            if axes.contains(pair.0) {
                result.insert(pair.1)
            }
        }
        return result.isEmpty ? .all : result
    }

    private static let logger = Logger(subsystem: "io.schwa.SceneSprockets", category: "Physics")

    // Sends Jolt's trace messages, which print to stdout by default, to unified logging (#422). Installed once; the
    // handler is process-wide.
    private static let forwardJoltTraces: Void = JoltEngine.setTraceHandler { message in
        logger.info("Jolt: \(message, privacy: .public)")
    }

    private func makeBody(for node: SceneGraph.Node, description: SceneGraph.PhysicsBody) -> BodyID? {
        // Jolt supports mesh and height field shapes only on static and kinematic bodies, planes only on static ones
        // (#425, #428).
        guard description.shape.allowedTypes.contains(description.type) else {
            guard warnedNodes.insert(node.id).inserted else {
                return nil
            }
            Self.logger.warning("Node \(node.label ?? "(unlabeled)", privacy: .public) has a \(String(describing: description.type), privacy: .public) physics body with a shape Jolt does not support for that body type; it gets no body. Use .convexHull for moving meshes.")
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
        var options = BodyOptions.default
        options.linearDamping = description.linearDamping
        options.angularDamping = description.angularDamping
        options.gravityFactor = description.gravityFactor
        options.allowSleeping = description.allowsSleeping
        options.motionQuality = description.usesContinuousCollision ? .linearCast : .discrete
        options.allowedDegreesOfFreedom = Self.degreesOfFreedom(description.allowedMotion)
        let body = world.addBody(shape, position: pose.translation, rotation: pose.rotation.quaternion, motionType: motionType, restitution: description.restitution, friction: description.friction, options: options)
        if description.type == .dynamic, let mass = description.mass {
            world.setMass(of: body, to: mass)
        }
        if description.isTrigger {
            world.setIsSensor(body, to: true)
        }
        contactListener.setMasks(of: body, to: description)
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
            return simd_length(center) < 1e-6 ? boxShape : .rotatedTranslated(boxShape, position: center)
        case .convexHull:
            let points = meshPositions(node).map { $0 * scale }
            return Self.spansVolume(points) ? .convexHull(points: points) : nil
        case let .heightField(samples, sampleCount, spacing):
            // Jolt needs whole blocks of 2 samples and one sample per grid point.
            guard sampleCount >= 2, sampleCount.isMultiple(of: 2), samples.count == sampleCount * sampleCount else {
                return nil
            }
            let half = Float(sampleCount - 1) * spacing / 2
            return .heightField(samples: samples, sampleCount: sampleCount, offset: [-half * scale.x, 0, -half * scale.z], scale: [spacing * scale.x, scale.y, spacing * scale.z])
        case .plane:
            // In body space; the body's rotation turns it.
            return .plane()
        case let .taperedCylinder(height, topRadius, bottomRadius):
            let radial = max(scale.x, scale.z)
            // Jolt keeps a convex radius inside the smaller end.
            let convexRadius = min(0.05, min(topRadius, bottomRadius) * radial)
            return .taperedCylinder(halfHeight: height * scale.y / 2, topRadius: topRadius * radial, bottomRadius: bottomRadius * radial, convexRadius: convexRadius)
        case .empty:
            return .empty()
        case .mesh:
            guard case let .mesh(mesh, _, _, _) = node.content else {
                return nil
            }
            let triangleSubmeshes = mesh.submeshes.enumerated().filter { $0.element.primitiveType == .triangle }
            let indices = triangleSubmeshes.flatMap(\.element.indices)
            guard !indices.isEmpty else {
                return nil
            }
            // Each triangle remembers its submesh, so hits and contacts can report it (#429).
            var options = MeshOptions()
            options.triangleUserData = triangleSubmeshes.flatMap { index, submesh in
                Array(repeating: UInt32(index), count: submesh.indices.count / 3)
            }
            // Jolt scales triangle meshes exactly, so the vertices are not copied to scale them (#416).
            let shape = Shape.mesh(vertices: mesh.positions(), indices: indices, options: options)
            return scale == .one ? shape : .scaled(shape, scale: scale)
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
