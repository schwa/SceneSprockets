import MetalSprocketsParticles
import SceneSprockets
import simd

// Seasonal particles, for looks only. Each view simulates its own copy, so they are not part of the game.
@MainActor
func addAtmosphere(to root: SceneGraph.Node, tree: GrownTree, season: Season, seed: UInt32) {
    var lower = SIMD3<Float>(repeating: .infinity)
    var upper = SIMD3<Float>(repeating: -.infinity)
    for leaf in tree.leaves {
        lower = simd_min(lower, leaf.position)
        upper = simd_max(upper, leaf.position)
    }
    if tree.leaves.isEmpty {
        lower = [-2, 3, -2]
        upper = [2, 6, 2]
    }
    let canopyCenter = (lower + upper) / 2
    let canopySize = simd_max(upper - lower, SIMD3(repeating: 1))
    let leafColors = season.leaves.map { SIMD4<Float>($0, 1) }
    let first = leafColors.first ?? [1, 1, 1, 1]
    let last = leafColors.last ?? first

    var systems: [(String, SIMD3<Float>, ParticleSystem)] = []

    // Leaves or petals drifting down from the canopy and across the meadow.
    let leafRate: Float = switch season.name {
    case "Autumn": 14
    case "Spring": 10
    case "Winter": 2
    default: 3
    }
    let falling = ParticleSystem("Falling Leaves") {
        EmitterDescription("Leaves", sprite: .confetti, capacity: 400) {
            ShapeModule(shape: .box(size: canopySize * [0.9, 0.5, 0.9]))
            RateModule(birthRate: leafRate, warmupDuration: 8)
            LifetimeModule(range: 7...11)
            VelocityModule(velocity: [0.35, -0.1, 0.1], spread: 0.6, speedVariation: 0.5)
            GravityModule(acceleration: [0.05, -0.18, 0])
            DragModule(amount: 0.6)
            RotationModule(angleVariation: .pi, angularSpeed: 2.5, angularSpeedVariation: 2)
            VariationModule(size: 0.04, color: SIMD4((last - first).x, (last - first).y, (last - first).z, 0) * 0.5)
            SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.05, 0.14), .init(0.9, 0.14), .init(1, 0)]))
            ColorOverLifeModule(color: .constant((first + last) / 2))
            SpriteModule(blendMode: .alpha, orientation: .tumbling)
        }
    }
    systems.append(("Falling Leaves", canopyCenter, falling))

    switch season.name {
    case "Winter":
        let snow = ParticleSystem("Snow") {
            EmitterDescription("Flakes", capacity: 3_000) {
                ShapeModule(shape: .box(size: [44, 1, 44]))
                RateModule(birthRate: 160, warmupDuration: 20)
                LifetimeModule(range: 14...18)
                VelocityModule(velocity: [0.15, -0.6, 0], spread: 0.3, speedVariation: 0.3)
                GravityModule(acceleration: .zero)
                DragModule(amount: 0)
                VariationModule(size: 0.03)
                SizeOverLifeModule(curve: .constant(0.09))
                ColorOverLifeModule(color: .constant([1, 1, 1, 0.9]))
                SpriteModule(blendMode: .alpha)
            }
        }
        systems.append(("Snow", [0, canopyCenter.y + canopySize.y, 0], snow))
    case "Summer":
        let motes = ParticleSystem("Fireflies") {
            EmitterDescription("Motes", capacity: 400) {
                ShapeModule(shape: .box(size: [24, 4, 24]))
                RateModule(birthRate: 18, warmupDuration: 10)
                LifetimeModule(range: 4...8)
                VelocityModule(velocity: [0, 0.08, 0], spread: 1, speedVariation: 0.8)
                GravityModule(acceleration: .zero)
                DragModule(amount: 0.2)
                SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.3, 0.12), .init(0.7, 0.12), .init(1, 0)]))
                ColorOverLifeModule(color: .constant([1, 0.85, 0.35, 1]))
                SpriteModule(blendMode: .additive)
            }
        }
        systems.append(("Fireflies", [0, 1.5, 0], motes))
    case "Spring":
        let pollen = ParticleSystem("Pollen") {
            EmitterDescription("Pollen", capacity: 600) {
                ShapeModule(shape: .box(size: [26, 6, 26]))
                RateModule(birthRate: 30, warmupDuration: 10)
                LifetimeModule(range: 5...9)
                VelocityModule(velocity: [0.2, 0.05, 0], spread: 1, speedVariation: 0.6)
                GravityModule(acceleration: .zero)
                DragModule(amount: 0.3)
                SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.3, 0.05), .init(0.7, 0.05), .init(1, 0)]))
                ColorOverLifeModule(color: .constant([1, 0.97, 0.85, 0.8]))
                SpriteModule(blendMode: .additive)
            }
        }
        systems.append(("Pollen", [0, 3, 0], pollen))
    default:
        break
    }

    for (index, (label, position, system)) in systems.enumerated() {
        let node = SceneGraph.Node(parent: root, label: label)
        node.transform = simd_float4x4(translation: position)
        node.particleSystems = [SceneParticleSystem(system, seed: seed &+ UInt32(index))]
    }
}

private extension simd_float4x4 {
    init(translation: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(translation, 1)
    }
}
