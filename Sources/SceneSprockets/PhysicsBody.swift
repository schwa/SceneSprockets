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

        /// The axes a body can move along and rotate about, like SceneKit's `velocityFactor` and
        /// `angularVelocityFactor` set to 0 or 1 per axis.
        public struct Axes: OptionSet, Sendable, Hashable, Codable {
            public let rawValue: UInt8

            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }

            public static let translationX = Self(rawValue: 1 << 0)
            public static let translationY = Self(rawValue: 1 << 1)
            public static let translationZ = Self(rawValue: 1 << 2)
            public static let rotationX = Self(rawValue: 1 << 3)
            public static let rotationY = Self(rawValue: 1 << 4)
            public static let rotationZ = Self(rawValue: 1 << 5)
            /// Moves freely but never rotates, for example an upright character.
            public static let translation: Self = [.translationX, .translationY, .translationZ]
            public static let rotation: Self = [.rotationX, .rotationY, .rotationZ]
            /// Stays in the XY plane and rotates only about Z, for 2D-style scenes.
            public static let plane2D: Self = [.translationX, .translationY, .rotationZ]
            public static let all: Self = [.translation, .rotation]
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
            /// Terrain: a square grid of heights, `sampleCount` by `sampleCount`, row by row along +Z, `spacing` apart and
            /// centered on the node in X and Z. `sampleCount` must be even. Static and kinematic bodies only, like `.mesh`.
            case heightField(samples: [Float], sampleCount: Int, spacing: Float = 1)
            /// A ground plane through the node's origin, facing the node's +Y, solid below. Static bodies only.
            case plane
            /// A cylinder along local Y whose top and bottom radii differ; a cone when one radius is near 0.
            case taperedCylinder(height: Float, topRadius: Float, bottomRadius: Float)
            /// No collision geometry, for a body that only exists to be jointed or moved. Give dynamic ones a `mass`.
            case empty

            /// The body types that can use the shape: meshes and height fields are static or kinematic, planes static.
            public var allowedTypes: [BodyType] {
                switch self {
                case .mesh, .heightField: [.static, .kinematic]
                case .plane: [.static]
                default: [.static, .dynamic, .kinematic]
                }
            }
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
        /// The axes a dynamic body can move along and rotate about. Empty counts as `.all`.
        public var allowedMotion: Axes
        /// A tag for the body's surface, such as "grass" or "metal", that ray hits and contacts report, for example to
        /// pick footstep sounds. Mesh shapes also report which submesh was hit.
        public var surface: String?
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
        ///   - allowedMotion: The axes a dynamic body can move along and rotate about.
        ///   - surface: A tag for the body's surface that ray hits and contacts report.
        ///   - isTrigger: Whether the body only detects overlaps instead of colliding.
        ///   - categoryBitMask: The categories the body belongs to.
        ///   - collisionBitMask: The categories the body collides with. The default is all of them.
        public init(type: BodyType, shape: Shape, mass: Float? = nil, friction: Float = 0.5, restitution: Float = 0, linearDamping: Float = 0.05, angularDamping: Float = 0.05, gravityFactor: Float = 1, allowsSleeping: Bool = true, usesContinuousCollision: Bool = false, allowedMotion: Axes = .all, surface: String? = nil, isTrigger: Bool = false, categoryBitMask: UInt32 = 1, collisionBitMask: UInt32 = .max) {
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
            self.allowedMotion = allowedMotion
            self.surface = surface
            self.isTrigger = isTrigger
            self.categoryBitMask = categoryBitMask
            self.collisionBitMask = collisionBitMask
        }
    }
}
