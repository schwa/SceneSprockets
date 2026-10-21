import Metal
import MetalSprockets
import MetalSprocketsParticles
import simd

// A MetalSprocketsParticles effect at a node. The description is `system`; the GPU state is made on first use.
// Emitters follow the node's world transform times their own motion. SceneView advances them with
// advanceParticles(by:); SceneGraphElement simulates them before the scene pass and draws them after the meshes.
public final class SceneParticleSystem {
    public var system: ParticleSystem {
        didSet { needsApply = true }
    }
    public let seed: UInt32
    // Seconds simulated, for emitter motion and animated colliders.
    public private(set) var time: Float = 0

    private var storedRuntime: ParticleSystemRuntime?
    private var needsApply = false
    private var pendingDeltaTime: Float = 0
    private var worldTransform = matrix_identity_float4x4
    private var isHidden = false
    // Each emitter's isEmitting from before the node was hidden.
    private var emittingBeforeHidden: [Bool] = []

    public init(_ system: ParticleSystem, seed: UInt32 = 0) {
        self.system = system
        self.seed = seed
    }

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

    // Removes every particle and restarts the clock.
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

    // Steps by the time advanced since the last call. Place before the render pass.
    func simulate(view: simd_float4x4) throws -> some Element {
        let runtime = try runtime()
        let deltaTime = pendingDeltaTime
        pendingDeltaTime = 0
        time += deltaTime * runtime.speedFactor
        let transforms = system.transforms(at: time).map { worldTransform * $0 }
        return try runtime.simulate(deltaTime: deltaTime, colliders: system.colliders(at: time), transforms: transforms, view: view)
    }
}

extension SceneGraph {
    // Advances every particle system in the graph. Systems on hidden nodes keep simulating but stop emitting.
    public func advanceParticles(by deltaTime: Float) {
        var visible = Set<ObjectIdentifier>()
        visit { node, _ in
            if !node.particleSystems.isEmpty {
                visible.insert(ObjectIdentifier(node))
            }
        }
        visit(includeHidden: true) { node, worldTransform in
            for system in node.particleSystems {
                system.advance(by: deltaTime, worldTransform: worldTransform, isHidden: !visible.contains(ObjectIdentifier(node)))
            }
        }
    }

    // Every particle system, hidden or not, each once.
    func allParticleSystems() -> [SceneParticleSystem] {
        var seen = Set<ObjectIdentifier>()
        var systems: [SceneParticleSystem] = []
        visit(includeHidden: true) { node, _ in
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
