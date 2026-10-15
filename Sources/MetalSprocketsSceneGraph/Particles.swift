import MetalSprocketsParticles
import simd

// Scene integration for MetalSprocketsParticles. Attach a ParticleSystem to a node's `particleSystems`; it emits from
// the node's world transform, and particles live in world space. SceneView advances them with advanceParticles(by:).
// SceneGraphElement draws them after the meshes, as soft camera-facing sprites that test depth but do not write it.
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
