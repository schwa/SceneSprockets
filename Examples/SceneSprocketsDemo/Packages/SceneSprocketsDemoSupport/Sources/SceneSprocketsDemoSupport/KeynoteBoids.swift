import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftECS
import SwiftMesh

// The keynote's SwiftECS World slide (#307): a flock of cones whose nodes live in the scene graph's World. A SwiftECS
// system reads a velocity component the demo adds to their entities and writes their NodeTransformComponent directly;
// the writes move the nodes.

struct BoidVelocity: Component {
    var value: SIMD3<Float>
}

@MainActor
final class KeynoteBoids {
    // Systems' callbacks cannot read the World, so each step snapshots every boid's position and velocity here first.
    private final class Neighbors {
        var positions: [SIMD3<Float>] = []
        var velocities: [SIMD3<Float>] = []
    }

    private let world: SwiftECS.World
    private let neighbors = Neighbors()
    private let flock: System
    private var nodes: [SceneGraph.Node] = []

    // The box, in the slide's space, that the flock stays in.
    static let lower: SIMD3<Float> = [-5, 0, -3]
    // Below the title.
    static let upper: SIMD3<Float> = [5, 2.6, 2]

    init(sceneGraph: SceneGraph, parent: SceneGraph.Node, count: Int = 120) {
        world = sceneGraph.world
        let mesh = MetalMesh(mesh: .cone(segments: 8, height: 0.32, radius: 0.09), device: demoDevice)
        var generator = SystemRandomNumberGenerator()
        for index in 0..<count {
            let hue = Float(index % 3)
            let color: SIMD3<Float> = hue == 0 ? [0.95, 0.55, 0.3] : hue == 1 ? [0.4, 0.75, 0.95] : [0.95, 0.85, 0.4]
            let position = SIMD3<Float>(.random(in: Self.lower.x...Self.upper.x, using: &generator), .random(in: Self.lower.y...Self.upper.y, using: &generator), .random(in: Self.lower.z...Self.upper.z, using: &generator))
            let node = SceneGraph.Node(parent: parent, label: "Boid \(index)", trs: .init(translation: position), content: .mesh(mesh, material: BlinnPhongSceneMaterial.plastic(color, shininess: 24)))
            let direction = simd_normalize(SIMD3<Float>(.random(in: -1...1, using: &generator), .random(in: -0.3...0.3, using: &generator), .random(in: -1...1, using: &generator)))
            sceneGraph.world[node.id]?.set(BoidVelocity(value: direction * 2))
            nodes.append(node)
        }
        let neighbors = neighbors
        flock = System("flock")
            .query(Write<NodeTransformComponent>(), Write<BoidVelocity>())
            .each { context, transform, velocity in
                let deltaTime = Float(context.deltaTime)
                let position = transform.value.value.trs.translation
                var cohesion = SIMD3<Float>.zero, alignment = SIMD3<Float>.zero, separation = SIMD3<Float>.zero
                var count: Float = 0
                for (other, otherVelocity) in zip(neighbors.positions, neighbors.velocities) {
                    let offset = other - position
                    let distance = simd_length(offset)
                    guard distance > 0, distance < 1.4 else {
                        continue
                    }
                    cohesion += other
                    alignment += otherVelocity
                    if distance < 0.45 {
                        separation -= offset / (distance * distance)
                    }
                    count += 1
                }
                var steering = SIMD3<Float>.zero
                if count > 0 {
                    steering += (cohesion / count - position) * 0.6
                    steering += (alignment / count - velocity.value.value) * 0.8
                    steering += separation * 0.35
                }
                // Turn back toward the box near its walls.
                steering += simd_clamp(Self.lower + 0.6 - position, .zero, SIMD3(repeating: 10)) * 4
                steering -= simd_clamp(position - (Self.upper - 0.6), .zero, SIMD3(repeating: 10)) * 4
                var newVelocity = velocity.value.value + steering * deltaTime
                let speed = simd_length(newVelocity)
                newVelocity *= simd_clamp(speed, 1.6, 3) / max(speed, 1e-4)
                velocity.value.value = newVelocity
                // Cones point along +Y; turn each one to fly along its velocity.
                transform.value.value = .trs(.init(translation: position + newVelocity * deltaTime, rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize(newVelocity))))
            }
    }

    func step(deltaTime: Float) {
        guard deltaTime > 0 else {
            return
        }
        neighbors.positions = []
        neighbors.velocities = []
        for row in world.query(NodeTransformComponent.self, BoidVelocity.self) {
            let (transform, velocity) = row.values
            neighbors.positions.append(transform.value.trs.translation)
            neighbors.velocities.append(velocity.value)
        }
        try? world.run(flock, deltaTime: Double(deltaTime))
    }
}
