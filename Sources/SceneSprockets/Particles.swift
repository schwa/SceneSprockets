import Metal
import MetalSprockets
import MetalSprocketsParticles
import simd

/// A MetalSprocketsParticles effect at a node. The description is `system`; the GPU state is made on first use.
/// Emitters follow the node's world transform times their own motion. SceneView advances them with
/// advanceParticles(by:); SceneGraphElement simulates them before the scene pass and draws them after the meshes.
public final class SceneParticleSystem {
    /// The MetalSprocketsParticles description of the emitters. Changes apply on the next update.
    public var system: ParticleSystem {
        didSet { needsApply = true }
    }
    /// The random seed. Two systems with the same description and seed make the same particles.
    public let seed: UInt32
    /// When false, emitters and colliders ignore the node's transform (the node only shows and hides them), for effects
    /// already in world space, such as emitters on a skinned mesh's world-space positions.
    public var usesNodeTransform = true
    /// Seconds simulated, for emitter motion and animated colliders.
    public private(set) var time: Float = 0

    private var storedRuntime: ParticleSystemRuntime?
    private var needsApply = false
    private var pendingDeltaTime: Float = 0
    private var worldTransform = matrix_identity_float4x4
    private var isHidden = false
    // Each emitter's isEmitting from before the node was hidden.
    private var emittingBeforeHidden: [Bool] = []

    /// Creates a particle system for a node.
    ///
    /// - Parameters:
    ///   - system: The description of the emitters.
    ///   - seed: The random seed.
    public init(_ system: ParticleSystem, seed: UInt32 = 0) {
        self.system = system
        self.seed = seed
    }

    /// Returns the GPU runtime of the system, and creates it the first time.
    ///
    /// - Throws: An error if the runtime's buffers or pipelines cannot be created.
    public func runtime() throws -> ParticleSystemRuntime {
        if let storedRuntime {
            if needsApply {
                try storedRuntime.apply(system)
                needsApply = false
            }
            return storedRuntime
        }
        let runtime = try ParticleSystemRuntime(seed: seed)
        runtime.reverseZ = true
        try runtime.load(system)
        storedRuntime = runtime
        needsApply = false
        return runtime
    }

    // Whether any emitter fades into scene geometry (SpriteModule.softness), which needs the scene's depth.
    var isSoft: Bool {
        system.layers.contains { ($0.modules[SpriteModule.self]?.softness ?? 0) > 0 }
    }

    /// Removes every particle and restarts the clock.
    public func restart() {
        time = 0
        pendingDeltaTime = 0
        storedRuntime?.restart()
    }

    func advance(by deltaTime: Float, worldTransform: simd_float4x4, isHidden: Bool) {
        pendingDeltaTime += max(deltaTime, 0)
        self.worldTransform = worldTransform
        guard isHidden != self.isHidden, let runtime = try? runtime() else {
            return
        }
        self.isHidden = isHidden
        if isHidden {
            emittingBeforeHidden = runtime.emitters.map(\.isEmitting)
            for emitter in runtime.emitters {
                emitter.isEmitting = false
            }
        } else {
            for (emitter, wasEmitting) in zip(runtime.emitters, emittingBeforeHidden) {
                emitter.isEmitting = wasEmitting
            }
        }
    }

    // One step by the time advanced since the last call, capped at ParticleSystemRuntime.maximumStep; the rest is
    // dropped. Not several steps: the runtime reads its live-particle counts back from earlier frames, which breaks when
    // many steps share one frame. Place before the render pass.
    func simulate(view: simd_float4x4) throws -> some Element {
        let runtime = try runtime()
        let deltaTime = min(pendingDeltaTime, ParticleSystemRuntime.maximumStep)
        pendingDeltaTime = 0
        time += deltaTime * max(runtime.speedFactor, 0)
        let placement = usesNodeTransform ? worldTransform : matrix_identity_float4x4
        let transforms = system.transforms(at: time).map { placement * $0 }
        let colliders = system.colliders(at: time).map { $0.transformed(by: placement) }
        return try runtime.simulate(deltaTime: deltaTime, colliders: colliders, transforms: transforms, view: view)
    }
}

extension Collider {
    // The collider moved into the space of `transform`: rotation, translation and uniform scale. Non-uniform scale uses
    // the mean of the three axis scales. Signed distance fields move and turn but do not scale.
    func transformed(by transform: simd_float4x4) -> Collider {
        let linear = simd_float3x3(transform.columns.0.xyz, transform.columns.1.xyz, transform.columns.2.xyz)
        let axisScales = SIMD3(simd_length(linear.columns.0), simd_length(linear.columns.1), simd_length(linear.columns.2))
        let scale = (axisScales.x + axisScales.y + axisScales.z) / 3
        let rotation = simd_quatf(simd_float3x3(linear.columns.0 / axisScales.x, linear.columns.1 / axisScales.y, linear.columns.2 / axisScales.z))
        func point(_ point: SIMD3<Float>) -> SIMD3<Float> {
            (transform * SIMD4(point, 1)).xyz
        }
        var result = self
        switch shape {
        case let .plane(normal, distance):
            let unitNormal = simd_normalize(normal)
            let worldNormal = simd_normalize(rotation.act(unitNormal))
            result.shape = .plane(normal: worldNormal, distance: simd_dot(point(unitNormal * distance), worldNormal))
        case let .sphere(center, radius):
            result.shape = .sphere(center: point(center), radius: radius * scale)
        case let .box(center, halfExtents, boxRotation):
            result.shape = .box(center: point(center), halfExtents: halfExtents * scale, rotation: rotation * boxRotation)
        case let .capsule(start, end, radius):
            result.shape = .capsule(start: point(start), end: point(end), radius: radius * scale)
        case let .signedDistanceField(field, center, fieldRotation):
            result.shape = .signedDistanceField(field, center: point(center), rotation: rotation * fieldRotation)
        }
        return result
    }
}

extension SceneGraph {
    /// Advances every particle system in the graph. Systems on hidden nodes keep simulating but stop emitting.
    public func advanceParticles(by deltaTime: Float) {
        var visible = Set<ObjectIdentifier>()
        visit { node, _ in
            if !node.particleSystems.isEmpty {
                visible.insert(ObjectIdentifier(node))
            }
        }
        // Inactive subtrees freeze.
        visitActive { node, worldTransform in
            for system in node.particleSystems {
                system.advance(by: deltaTime, worldTransform: worldTransform, isHidden: !visible.contains(ObjectIdentifier(node)))
            }
        }
    }

    /// Whether any node in the graph has a particle system.
    public var hasParticleSystems: Bool {
        !allParticleSystems().isEmpty
    }

    // Every particle system, hidden or not, each once.
    func allParticleSystems() -> [SceneParticleSystem] {
        var seen = Set<ObjectIdentifier>()
        var systems: [SceneParticleSystem] = []
        visitActive { node, _ in
            for system in node.particleSystems where seen.insert(ObjectIdentifier(system)).inserted {
                systems.append(system)
            }
        }
        return systems
    }

    // Particle systems on visible nodes, for drawing.
    func visibleParticleSystems() -> [SceneParticleSystem] {
        var seen = Set<ObjectIdentifier>()
        var systems: [SceneParticleSystem] = []
        visit { node, _ in
            for system in node.particleSystems where seen.insert(ObjectIdentifier(system)).inserted {
                systems.append(system)
            }
        }
        return systems
    }
}
