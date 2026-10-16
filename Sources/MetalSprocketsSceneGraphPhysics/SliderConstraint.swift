import GeometryLite3D
import JoltPhysics
import MetalSprocketsSceneGraph
import simd

extension SceneGraphPhysicsWorld {
    // The node of a Jolt body, if this world created it.
    public func node(of body: BodyID) -> SceneGraph.Node? {
        entries.values.first { $0.body == body }?.node
    }

    // Keeps a node from moving into physics bodies, like SCNSliderConstraint. The node is a sphere of `radius`. Each
    // time constraints run, it sweeps from where the constraint last left it to where it is now; at a body whose
    // node is in `categoryBitMask` it stops and slides along the surface. Bodies of the node itself and its
    // descendants are ignored. Call sync() or step(deltaTime:) first so the bodies exist.
    public func sliderConstraint(radius: Float, categoryBitMask: UInt = .max) -> SceneGraph.Constraint {
        let state = SliderState()
        return .transform { [weak self] node, world in
            guard let self else {
                return world
            }
            let key = ObjectIdentifier(node)
            guard let start = state.positions[key] else {
                state.positions[key] = world.translation
                return world
            }
            let position = slide(from: start, to: world.translation, radius: radius, node: node, categoryBitMask: categoryBitMask)
            state.positions[key] = position
            var result = world
            result.translation = position
            return result
        }
    }

    private func slide(from start: SIMD3<Float>, to goal: SIMD3<Float>, radius: Float, node: SceneGraph.Node, categoryBitMask: UInt) -> SIMD3<Float> {
        let skin: Float = 1e-3
        var position = start
        var target = goal
        // Three passes: hit one surface, slide, maybe hit a second (a corner), slide again.
        for _ in 0..<3 {
            let motion = target - position
            guard simd_length(motion) > 1e-6 else {
                break
            }
            let hit = world.castShapeAll(.sphere(radius: radius), position: position, direction: motion).first { hit in
                // Moving away from (or along) a surface it already touches is fine.
                guard simd_dot(hit.normal, motion) < 0 else {
                    return false
                }
                guard let other = self.node(of: hit.body) else {
                    return false
                }
                return other.categoryBitMask & categoryBitMask != 0 && other !== node && !node.isAncestor(of: other)
            }
            guard let hit else {
                position = target
                break
            }
            position += motion * hit.fraction + hit.normal * skin
            let remaining = target - position
            target = position + remaining - hit.normal * simd_dot(remaining, hit.normal)
        }
        return position
    }
}

private final class SliderState {
    var positions: [ObjectIdentifier: SIMD3<Float>] = [:]
}
