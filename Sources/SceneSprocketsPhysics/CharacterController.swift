import GeometryLite3D
import JoltPhysics
import SceneSprockets
import simd

/// Moves a node like a player or NPC instead of a rigid body: it walks at ``desiredVelocity``, slides along walls,
/// climbs low steps, keeps to the floor on slopes and stands on moving platforms (#433). Like RealityKit's
/// `CharacterControllerComponent`. Add one with ``SceneGraphPhysicsWorld/addCharacter(for:height:radius:mass:maxSlopeAngle:)``.
///
/// The node's origin is at the character's feet. Each step writes the node's position; its rotation is left alone, so
/// turn the node yourself.
public final class CharacterController {
    public let node: SceneGraph.Node
    /// The Jolt character, for anything this type does not wrap.
    public let character: VirtualCharacter
    /// The horizontal velocity to walk at, in world units per second. Its vertical part is ignored; gravity and
    /// ``jump(speed:)`` move the character up and down.
    public var desiredVelocity: SIMD3<Float> = .zero
    /// Whether the character climbs steps up to 0.4 units high.
    public var walksStairs = true
    // Vertical speed from gravity and jumps.
    var verticalSpeed: Float = 0

    init(node: SceneGraph.Node, character: VirtualCharacter) {
        self.node = node
        self.character = character
    }

    /// Whether the character stands on ground no steeper than its maximum slope.
    public var isOnGround: Bool {
        character.groundState == .onGround
    }

    /// Launches the character upward, if it stands on ground.
    public func jump(speed: Float) {
        guard isOnGround else {
            return
        }
        verticalSpeed = speed
    }

    func update(deltaTime: Float, gravity: SIMD3<Float>) {
        let up = SIMD3<Float>(0, 1, 0)
        var horizontal = desiredVelocity - simd_dot(desiredVelocity, up) * up
        character.updateGroundVelocity()
        let grounded = isOnGround && verticalSpeed <= 0
        if grounded {
            verticalSpeed = 0
            // Rides on moving platforms.
            horizontal += character.groundVelocity
        } else {
            verticalSpeed += simd_dot(gravity, up) * deltaTime
        }
        let velocity = horizontal + up * verticalSpeed
        // Velocity into a steep contact is cancelled, so the character does not climb slopes it cannot walk up. A step
        // it can climb is such a contact too: cancelling the velocity there stopped stair walking when the character
        // reached the step slowly, so it stood at the step (#625).
        character.linearVelocity = walksStairs && character.canWalkStairs(velocity: velocity) ? velocity : character.cancelVelocityTowardsSteepSlopes(velocity)
        // Sticking to the floor would pull a jumping character back down.
        character.update(deltaTime: deltaTime, stickToFloor: verticalSpeed <= 0, walkStairs: walksStairs)
        var pose = Transform3D(nearestTo: node.worldTransform)
        pose.translation = character.position
        node.worldTransform = pose.matrix
    }
}

public extension SceneGraphPhysicsWorld {
    /// Adds a capsule character controller for `node`, standing at its position with its feet at the node's origin.
    /// Returns nil if `node` already has one. Other bodies see the character through an inner capsule body.
    ///
    /// - Parameters:
    ///   - node: The node the character moves. Give it no `physicsBody`.
    ///   - height: The character's full height.
    ///   - radius: The capsule radius.
    ///   - mass: The mass that pushes other bodies, in kilograms.
    ///   - maxSlopeAngle: The steepest slope the character can walk up, in radians.
    @discardableResult
    func addCharacter(for node: SceneGraph.Node, height: Float = 1.8, radius: Float = 0.3, mass: Float = 70, maxSlopeAngle: Float = .pi / 4) -> CharacterController? {
        guard !characters.contains(where: { $0.node === node }) else {
            return nil
        }
        let capsule = Shape.capsule(halfHeightOfCylinder: max(height / 2 - radius, 0.01), radius: radius)
        // Moved up so the shape's bottom is at the character's position, the node's origin.
        let shape = Shape.rotatedTranslated(capsule, position: [0, height / 2, 0])
        let pose = Transform3D(nearestTo: node.worldTransform)
        let character = world.addVirtualCharacter(shape: shape, position: pose.translation, mass: mass, maxSlopeAngle: maxSlopeAngle, innerBodyShape: shape)
        let controller = CharacterController(node: node, character: character)
        characters.append(controller)
        return controller
    }

    /// Removes a character controller; its node stays where it is.
    func removeCharacter(_ controller: CharacterController) {
        characters.removeAll { $0 === controller }
    }
}
