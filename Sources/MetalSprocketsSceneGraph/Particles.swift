import simd

extension SceneGraph {
    // A CPU particle emitter, like SCNParticleSystem (a subset). Attach it to a node's `particleSystems`; it emits
    // from the node's world transform, and particles then live in world space. Advance it with
    // `SceneGraph.advanceParticles(by:)` (SceneView does this). SceneGraphElement draws it after the meshes, as
    // soft camera-facing sprites that test depth but do not write it.
    public final class ParticleSystem {
        public enum EmitterShape: Sendable {
            case point
            // Full extents, centered on the node.
            case box(SIMD3<Float>)
            case sphere(radius: Float)
        }

        public enum BlendMode: Sendable {
            // Normal alpha blending.
            case alpha
            // Adds light, for fire and sparks.
            case additive
        }

        // Particles per second.
        public var birthRate: Float = 20
        // Seconds; each particle lives lifetime ± lifetimeRange / 2.
        public var lifetime: Float = 2
        public var lifetimeRange: Float = 0
        public var emitterShape: EmitterShape = .point
        // Emission direction in the node's space, spread by up to `spreadAngle` radians.
        public var direction: SIMD3<Float> = [0, 1, 0]
        public var spreadAngle: Float = 0.3
        public var speed: Float = 1
        public var speedRange: Float = 0
        // World-space acceleration, for example gravity.
        public var acceleration: SIMD3<Float> = .zero
        // Fraction of velocity lost per second.
        public var damping: Float = 0
        // Full width at birth and at death, interpolated over life.
        public var startSize: Float = 0.1
        public var endSize: Float = 0.1
        // Linear RGBA at birth and at death.
        public var startColor: SIMD4<Float> = [1, 1, 1, 1]
        public var endColor: SIMD4<Float> = [1, 1, 1, 0]
        public var blendMode: BlendMode = .alpha
        public var maximumParticleCount = 2_000
        // Stops emitting after this many seconds; nil emits forever. Existing particles finish their lives.
        public var emissionDuration: Float?
        public var isEmitting = true

        struct Particle {
            var position: SIMD3<Float>
            var velocity: SIMD3<Float>
            var age: Float
            var lifetime: Float
        }

        private(set) var particles: [Particle] = []
        private var emissionDebt: Float = 0
        private var elapsed: Float = 0
        private var random: SplitMix64

        // A fixed seed makes emission repeatable (for tests and golden images).
        public init(seed: UInt64 = .random(in: 0 ... .max)) {
            random = SplitMix64(seed: seed)
        }

        public var particleCount: Int {
            particles.count
        }

        // Clears all particles and restarts the emission clock.
        public func reset() {
            particles.removeAll()
            emissionDebt = 0
            elapsed = 0
        }

        func advance(by deltaTime: Float, emitterTransform: simd_float4x4) {
            guard deltaTime > 0 else {
                return
            }
            for index in particles.indices {
                particles[index].age += deltaTime
                particles[index].velocity += acceleration * deltaTime
                particles[index].velocity *= max(1 - damping * deltaTime, 0)
                particles[index].position += particles[index].velocity * deltaTime
            }
            particles.removeAll { $0.age >= $0.lifetime }
            elapsed += deltaTime
            let emitting = isEmitting && (emissionDuration.map { elapsed <= $0 } ?? true)
            guard emitting else {
                emissionDebt = 0
                return
            }
            emissionDebt += birthRate * deltaTime
            let count = Int(emissionDebt)
            emissionDebt -= Float(count)
            for _ in 0..<count where particles.count < maximumParticleCount {
                particles.append(emit(from: emitterTransform))
            }
        }

        private func emit(from transform: simd_float4x4) -> Particle {
            let local: SIMD3<Float> = switch emitterShape {
            case .point:
                .zero
            case .box(let extents):
                SIMD3(random.unit() - 0.5, random.unit() - 0.5, random.unit() - 0.5) * extents
            case .sphere(let radius):
                randomUnitVector() * radius * pow(random.unit(), 1 / 3)
            }
            let world = transform * SIMD4(local, 1)
            let axis = simd_length(direction) > 0 ? simd_normalize(direction) : [0, 1, 0]
            // A random direction within the cone around `axis`.
            let cosine = 1 - random.unit() * (1 - cos(min(spreadAngle, .pi)))
            let sine = sqrt(max(1 - cosine * cosine, 0))
            let angle = random.unit() * 2 * .pi
            let helper: SIMD3<Float> = abs(axis.y) < 0.99 ? [0, 1, 0] : [1, 0, 0]
            let tangent = simd_normalize(simd_cross(axis, helper))
            let bitangent = simd_cross(axis, tangent)
            let localDirection = axis * cosine + (tangent * cos(angle) + bitangent * sin(angle)) * sine
            let worldDirection = simd_normalize((transform * SIMD4(localDirection, 0)).xyz)
            let particleSpeed = speed + (random.unit() - 0.5) * speedRange
            return Particle(
                position: world.xyz,
                velocity: worldDirection * particleSpeed,
                age: 0,
                lifetime: max(lifetime + (random.unit() - 0.5) * lifetimeRange, 0.001)
            )
        }

        private func randomUnitVector() -> SIMD3<Float> {
            let z = random.unit() * 2 - 1
            let angle = random.unit() * 2 * .pi
            let radius = sqrt(max(1 - z * z, 0))
            return SIMD3(radius * cos(angle), radius * sin(angle), z)
        }

        // Size and color at each particle's age.
        func instances() -> [(position: SIMD3<Float>, size: Float, color: SIMD4<Float>)] {
            particles.map { particle in
                let t = min(particle.age / particle.lifetime, 1)
                return (particle.position, startSize + (endSize - startSize) * t, simd_mix(startColor, endColor, SIMD4(repeating: t)))
            }
        }
    }

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
                let wasEmitting = system.isEmitting
                if !visible.contains(ObjectIdentifier(node)) {
                    system.isEmitting = false
                }
                system.advance(by: deltaTime, emitterTransform: worldTransform)
                system.isEmitting = wasEmitting
            }
        }
    }

    // Particle systems on visible nodes, for drawing.
    func visibleParticleSystems() -> [ParticleSystem] {
        var systems: [ParticleSystem] = []
        visit { node, _ in
            systems += node.particleSystems
        }
        return systems
    }
}

// Small, seedable generator.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    // 0..<1.
    mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }
}

private extension SIMD4<Float> {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}
