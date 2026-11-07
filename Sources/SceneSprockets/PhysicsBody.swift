import simd

extension SceneGraph {
    /// How a node takes part in a physics simulation, like SCNPhysicsBody. A description only: the
    /// SceneSprocketsPhysics target turns it into a simulated body.
    public struct PhysicsBody: Sendable, Equatable {
        /// How the simulation moves a body.
        public enum BodyType: Sendable, Equatable {
            /// The body never moves. Other bodies collide with it.
            case `static`
            /// The simulation moves the body, and writes its node's transform each step.
            case dynamic
            /// The node moves the body, for example with actions, animation or code. The body pushes dynamic bodies.
            case kinematic
        }

        /// The collision shape of a body.
        ///
        /// Sizes are in the node's local space. The simulation applies the node's world scale when it creates the body.
        public enum Shape: Sendable, Equatable, Codable {
            /// A box with a size.
            case box(size: SIMD3<Float>)
            /// A sphere with a radius.
            case sphere(radius: Float)
            /// A capsule along local Y. The height includes the caps.
            case capsule(height: Float, radius: Float)
            /// A cylinder along local Y.
            case cylinder(height: Float, radius: Float)
            /// The bounding box of the node's mesh.
            case boundingBox
            /// The convex hull of the node's mesh positions.
            case convexHull
            /// The node's triangles. Only static and kinematic bodies can use this shape.
            case mesh
        }

        /// How the simulation moves the body.
        public var type: BodyType
        /// The collision shape.
        public var shape: Shape
        /// Nil uses the shape's volume at density 1000 (water).
        public var mass: Float?
        /// The friction coefficient. 0 slides without friction.
        public var friction: Float
        /// 0 does not bounce, 1 bounces fully.
        public var restitution: Float

        /// Creates a physics body description.
        ///
        /// - Parameters:
        ///   - type: How the simulation moves the body.
        ///   - shape: The collision shape.
        ///   - mass: The mass in kilograms, or `nil` for the shape's volume at the density of water.
        ///   - friction: The friction coefficient.
        ///   - restitution: The bounciness, from 0 (no bounce) to 1 (full bounce).
        public init(type: BodyType, shape: Shape, mass: Float? = nil, friction: Float = 0.5, restitution: Float = 0) {
            self.type = type
            self.shape = shape
            self.mass = mass
            self.friction = friction
            self.restitution = restitution
        }
    }
}
