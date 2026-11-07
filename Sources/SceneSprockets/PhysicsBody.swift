import simd

extension SceneGraph {
    /// How a node takes part in a physics simulation, like SCNPhysicsBody. A description only: the
    /// SceneSprocketsPhysics target turns it into a simulated body.
    public struct PhysicsBody: Sendable, Equatable {
        public enum BodyType: Sendable, Equatable {
            // Never moves; other bodies collide with it.
            case `static`
            // Moved by the simulation; its node's transform is written each step.
            case dynamic
            // Moved by its node (actions, animation, code); pushes dynamic bodies.
            case kinematic
        }

        /// Sizes are in the node's local space; the node's world scale is applied when the body is created.
        public enum Shape: Sendable, Equatable, Codable {
            case box(size: SIMD3<Float>)
            case sphere(radius: Float)
            // Along local Y. `height` includes the caps.
            case capsule(height: Float, radius: Float)
            // Along local Y.
            case cylinder(height: Float, radius: Float)
            // The node's mesh bounds (Node.meshBounds).
            case boundingBox
            // Convex hull of the node's mesh positions.
            case convexHull
            // The node's triangles. Static and kinematic bodies only.
            case mesh
        }

        public var type: BodyType
        public var shape: Shape
        /// Nil uses the shape's volume at density 1000 (water).
        public var mass: Float?
        public var friction: Float
        /// 0 does not bounce, 1 bounces fully.
        public var restitution: Float

        public init(type: BodyType, shape: Shape, mass: Float? = nil, friction: Float = 0.5, restitution: Float = 0) {
            self.type = type
            self.shape = shape
            self.mass = mass
            self.friction = friction
            self.restitution = restitution
        }
    }
}
