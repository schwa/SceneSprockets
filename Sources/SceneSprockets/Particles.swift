import Metal
import MetalSprockets
import MetalSprocketsParticles
import simd

/// A MetalSprocketsParticles effect at a node. The description is `system`; the GPU state is made on first use.
/// Emitters follow the node's world transform times their own motion. SceneView advances them with
/// advanceParticles(by:); SceneGraphElement simulates them before the scene pass and draws them after the meshes.
///
/// Two sides use it: the thread that edits the scene graph (``system``, ``restart()``, `advanceParticles(by:)`) and the
/// thread that renders it, which alone touches the GPU runtime. ``SceneGraph/presentation()`` hands the edits over as
/// a ``Frame`` (#390). ``runtime()`` and ``time`` belong to the rendering side: when rendering on another thread, as in
/// a visionOS immersive space, do not use them from the editing thread.
public final class SceneParticleSystem {
    /// The MetalSprocketsParticles description of the emitters. Changes apply on the next frame.
    public var system: ParticleSystem {
        didSet { generation += 1 }
    }
    /// The random seed. Two systems with the same description and seed make the same particles.
    public let seed: UInt32
    /// When false, emitters and colliders ignore the node's transform (the node only shows and hides them), for effects
    /// already in world space, such as emitters on a skinned mesh's world-space positions.
    public var usesNodeTransform = true
    /// Seconds simulated, for emitter motion and animated colliders.
    public private(set) var time: Float = 0

    // Editing side.
    private var generation = 0
    private var pendingDeltaTime: Float = 0
    private var worldTransform = matrix_identity_float4x4
    private var isHidden = false
    private var pendingRestart = false

    // Rendering side.
    private var storedRuntime: ParticleSystemRuntime?
    private var appliedGeneration = 0
    private var appliedHidden = false
    // Each emitter's isEmitting from before the node was hidden.
    private var emittingBeforeHidden: [Bool] = []

    /// What one frame hands from the editing side to the rendering side.
    public struct Frame {
        let system: SceneParticleSystem
        let description: ParticleSystem
        let generation: Int
        let deltaTime: Float
        let placement: simd_float4x4
        let isHidden: Bool
        let restarts: Bool

        // Whether any emitter fades into scene geometry (SpriteModule.softness), which needs the scene's depth.
        var isSoft: Bool {
            description.layers.contains { ($0.modules[SpriteModule.self]?.softness ?? 0) > 0 }
        }
    }

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
        try runtime(description: system, generation: generation)
    }

    private func runtime(description: ParticleSystem, generation: Int) throws -> ParticleSystemRuntime {
        if let storedRuntime {
            if appliedGeneration != generation {
                try storedRuntime.apply(description)
                appliedGeneration = generation
            }
            return storedRuntime
        }
        let runtime = try ParticleSystemRuntime(seed: seed)
        runtime.reverseZ = true
        try runtime.load(description)
        storedRuntime = runtime
        appliedGeneration = generation
        return runtime
    }

    // Rendering side: the runtime made by `simulate`, without applying edits.
    var renderRuntime: ParticleSystemRuntime? {
        storedRuntime
    }

    /// Removes every particle and restarts the clock, on the next frame.
    public func restart() {
        pendingDeltaTime = 0
        pendingRestart = true
    }

    func advance(by deltaTime: Float, worldTransform: simd_float4x4, isHidden: Bool) {
        pendingDeltaTime += max(deltaTime, 0)
        self.worldTransform = worldTransform
        self.isHidden = isHidden
    }

    // Editing side: hands this frame's edits to the rendering side. The step is the time advanced since the last frame,
    // capped at ParticleSystemRuntime.maximumStep; the rest is dropped. Not several steps: the runtime reads its
    // live-particle counts back from earlier frames, which breaks when many steps share one frame.
    func makeFrame() -> Frame {
        let deltaTime = min(pendingDeltaTime, ParticleSystemRuntime.maximumStep)
        pendingDeltaTime = 0
        defer { pendingRestart = false }
        return Frame(system: self, description: system, generation: generation, deltaTime: deltaTime, placement: usesNodeTransform ? worldTransform : matrix_identity_float4x4, isHidden: isHidden, restarts: pendingRestart)
    }

    // Rendering side: applies `frame` and simulates one step. Place before the render pass.
    func simulate(_ frame: Frame, view: simd_float4x4) throws -> some Element {
        let runtime = try runtime(description: frame.description, generation: frame.generation)
        if frame.restarts {
            time = 0
            runtime.restart()
        }
        if frame.isHidden != appliedHidden {
            appliedHidden = frame.isHidden
            if frame.isHidden {
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
        time += frame.deltaTime * max(runtime.speedFactor, 0)
        let transforms = frame.description.transforms(at: time).map { frame.placement * $0 }
        let colliders = frame.description.colliders(at: time).map { $0.transformed(by: frame.placement) }
        return try runtime.simulate(deltaTime: frame.deltaTime, colliders: colliders, transforms: transforms, view: view)
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
