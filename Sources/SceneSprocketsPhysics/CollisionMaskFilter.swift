import JoltPhysics
import SceneSprockets
import Synchronization

// Applies PhysicsBody.categoryBitMask and collisionBitMask (#412). Bodies with the default masks are not stored, so
// the table holds only bodies that opted out of some collisions.
final class CollisionMaskFilter: ContactListener {
    private struct Masks {
        var category: UInt32
        var collision: UInt32
    }

    private static let defaultMasks = Masks(category: 1, collision: .max)

    private let masks = Mutex<[BodyID: Masks]>([:])

    func setMasks(of body: BodyID, to description: SceneGraph.PhysicsBody) {
        let value = Masks(category: description.categoryBitMask, collision: description.collisionBitMask)
        masks.withLock { table in
            let isDefault = value.category == Self.defaultMasks.category && value.collision == Self.defaultMasks.collision
            table[body] = isDefault ? nil : value
        }
    }

    func removeMasks(of body: BodyID) {
        masks.withLock { $0[body] = nil }
    }

    func contactValidate(body1: BodyID, body2: BodyID) -> ContactValidation {
        let (first, second) = masks.withLock { table in
            (table[body1] ?? Self.defaultMasks, table[body2] ?? Self.defaultMasks)
        }
        let collides = first.category & second.collision != 0 && second.category & first.collision != 0
        return collides ? .acceptAllContactsForThisBodyPair : .rejectAllContactsForThisBodyPair
    }
}
