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
            /// The convex hull of the node's mesh positions. Positions that do not span a volume (all the same, on one
            /// line or on one plane) give no body.
            case convexHull
            /// The node's triangles. Only static and kinematic bodies can use this shape; a dynamic body with it is not
            /// created, and a warning is logged.
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
        /// How fast linear velocity decays, per second. 0 keeps it; larger values slow the body like drag.
        public var linearDamping: Float
        /// How fast angular velocity decays, per second.
        public var angularDamping: Float
        /// Multiplies gravity for this body; 0 is not affected by gravity, like SceneKit's `isAffectedByGravity`.
        public var gravityFactor: Float
        /// Whether the body may go to sleep when it comes to rest, like SceneKit's `allowsResting`.
        public var allowsSleeping: Bool
        /// Sweeps the body along its motion each step so a fast body does not pass through thin ones, at some cost.
        public var usesContinuousCollision: Bool
        /// A trigger detects overlaps with other bodies but does not collide with them or push them, like a SceneKit
        /// contact-only body.
        public var isTrigger: Bool
        /// The categories the body belongs to, one per bit, like SceneKit's `categoryBitMask`.
        public var categoryBitMask: UInt32
        /// The categories the body collides with. Two bodies collide only when each one's category is in the other's
        /// collision mask. Bodies that do not collide also do not report contacts.
        public var collisionBitMask: UInt32

        /// Creates a physics body description.
        ///
        /// - Parameters:
        ///   - type: How the simulation moves the body.
        ///   - shape: The collision shape.
        ///   - mass: The mass in kilograms, or `nil` for the shape's volume at the density of water.
        ///   - friction: The friction coefficient.
        ///   - restitution: The bounciness, from 0 (no bounce) to 1 (full bounce).
        ///   - linearDamping: How fast linear velocity decays, per second.
        ///   - angularDamping: How fast angular velocity decays, per second.
        ///   - gravityFactor: Multiplies gravity for this body; 0 ignores gravity.
        ///   - allowsSleeping: Whether the body may sleep at rest.
        ///   - usesContinuousCollision: Whether a fast body is swept so it does not tunnel through thin bodies.
        ///   - isTrigger: Whether the body only detects overlaps instead of colliding.
        ///   - categoryBitMask: The categories the body belongs to.
        ///   - collisionBitMask: The categories the body collides with. The default is all of them.
        public init(type: BodyType, shape: Shape, mass: Float? = nil, friction: Float = 0.5, restitution: Float = 0, linearDamping: Float = 0.05, angularDamping: Float = 0.05, gravityFactor: Float = 1, allowsSleeping: Bool = true, usesContinuousCollision: Bool = false, isTrigger: Bool = false, categoryBitMask: UInt32 = 1, collisionBitMask: UInt32 = .max) {
            self.type = type
            self.shape = shape
            self.mass = mass
            self.friction = friction
            self.restitution = restitution
            self.linearDamping = linearDamping
            self.angularDamping = angularDamping
            self.gravityFactor = gravityFactor
            self.allowsSleeping = allowsSleeping
            self.usesContinuousCollision = usesContinuousCollision
            self.isTrigger = isTrigger
            self.categoryBitMask = categoryBitMask
            self.collisionBitMask = collisionBitMask
        }
    }
}
