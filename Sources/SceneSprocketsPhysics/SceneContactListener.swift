import JoltPhysics
import SceneSprockets
import Synchronization

// SceneGraphPhysicsWorld's Jolt contact listener. It applies PhysicsBody.categoryBitMask and collisionBitMask (#412)
// and records contacts for SceneGraphPhysicsWorld to report after the step (#423). Jolt calls it from its worker
// threads, so all state is behind locks.
final class SceneContactListener: ContactListener {
    private struct Masks {
        var category: UInt32
        var collision: UInt32
    }

    // What Jolt reported during a step. Jolt reports each touching pair of sub-shapes, so one body pair can be added
    // or removed several times.
    enum Event {
        // `subShapes` are the parts of the pair's first and second bodies that touch.
        case added(BodyPair, point: SIMD3<Float>, normal: SIMD3<Float>, penetrationDepth: Float, impulse: Float, subShapes: (SubShapeID, SubShapeID))
        case removed(BodyPair)
    }

    struct BodyPair: Hashable {
        var first: BodyID
        var second: BodyID

        init(_ body1: BodyID, _ body2: BodyID) {
            (first, second) = body1.rawValue < body2.rawValue ? (body1, body2) : (body2, body1)
        }

        func contains(_ body: BodyID) -> Bool {
            first == body || second == body
        }
    }

    private static let defaultMasks = Masks(category: 1, collision: .max)

    // Only bodies that opted out of some collisions; the rest use the default masks.
    private let masks = Mutex<[BodyID: Masks]>([:])
    private let events = Mutex<[Event]>([])

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

    // The events since the last call, in the order Jolt reported them.
    func takeEvents() -> [Event] {
        events.withLock { events in
            defer { events.removeAll(keepingCapacity: true) }
            return events
        }
    }

    func contactValidate(body1: BodyID, body2: BodyID) -> ContactValidation {
        let (first, second) = masks.withLock { table in
            (table[body1] ?? Self.defaultMasks, table[body2] ?? Self.defaultMasks)
        }
        let collides = first.category & second.collision != 0 && second.category & first.collision != 0
        return collides ? .acceptAllContactsForThisBodyPair : .rejectAllContactsForThisBodyPair
    }

    func contactAdded(_ contact: Contact, settings: inout ContactSettings) {
        let points = contact.pointsOn1
        let point = points.isEmpty ? .zero : points.reduce(.zero, +) / Float(points.count)
        let pair = BodyPair(contact.body1, contact.body2)
        // Jolt's normal points from body1 to body2; keep it pointing from the pair's first body to its second.
        let normal = pair.first == contact.body1 ? contact.normal : -contact.normal
        // The impulse the solver will apply along the normal, summed over the contact points (#430). Only valid inside
        // this callback. Sensors do not push.
        let impulse = settings.isSensor ? 0 : contact.estimateResponse(friction: settings.combinedFriction, restitution: settings.combinedRestitution).impulses.reduce(0) { $0 + $1.contact }
        let subShapes = pair.first == contact.body1 ? (contact.subShapeID1, contact.subShapeID2) : (contact.subShapeID2, contact.subShapeID1)
        let event = Event.added(pair, point: point, normal: normal, penetrationDepth: contact.penetrationDepth, impulse: impulse, subShapes: subShapes)
        events.withLock { $0.append(event) }
    }

    func contactRemoved(body1: BodyID, body2: BodyID) {
        events.withLock { $0.append(.removed(BodyPair(body1, body2))) }
    }
}
