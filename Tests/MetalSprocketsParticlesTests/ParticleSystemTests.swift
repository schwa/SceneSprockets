import MetalSprocketsParticles
import simd
import Testing

// #103: the particle engine works on its own, without a scene graph.
@Test
func particleSystemRunsStandalone() {
    let system = ParticleSystem(seed: 1)
    system.birthRate = 10
    system.speed = 1
    system.spreadAngle = 0
    system.advance(by: 1, emitterTransform: matrix_identity_float4x4)
    #expect(system.particleCount == 10)
    #expect(system.particles.allSatisfy { $0.velocity == [0, 1, 0] })
    #expect(system.instances().count == 10)
}
