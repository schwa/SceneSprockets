import SceneSprocketsAudio
import simd
import SwiftECS
import SwiftMesh

// Components a node in a graph stores in the graph's World. Public so ECS apps can query and write them (#269);
// see SceneGraph.world for what direct writes do.

// ChildOf does not keep an order we can change, so each child stores its index among its siblings. Writing it
// reorders the node's siblings (#273).
public struct SiblingIndexComponent: Component {
    public var index: Int

    public init(index: Int) {
        self.index = index
    }
}

// Finds the node for an entity, so writes made directly to the World can reach it. Its presence also marks the
// entity as a live scene graph node.
// Unowned, not weak: a weak reference moves the node's reference count to a side table, which slows every retain of
// every node (#283). The entity never outlives its node: it is destroyed when the node leaves the graph.
public struct NodeReferenceComponent: Component {
    public internal(set) unowned var node: SceneGraph.Node?

    init(node: SceneGraph.Node) {
        self.node = node
    }
}

// Which graph an entity belongs to, when several share a World (#269).
public struct SceneGraphMembershipComponent: Component {
    public let rootID: EntityID
}

public struct NodeTransformComponent: NodeField {
    public var value: SceneGraph.LocalTransform

    public init(value: SceneGraph.LocalTransform) {
        self.value = value
    }

    static var defaultValue: SceneGraph.LocalTransform { .matrix(.identity) }
    static var revision: NodeFieldRevision { .transform }

    // Only Transaction.animate uses the old value.
    static var needsOldValue: Bool {
        SceneGraph.Transaction.currentIfAny != nil
    }

    static func didChange(_ node: SceneGraph.Node, from oldValue: SceneGraph.LocalTransform) {
        SceneGraph.Transaction.currentIfAny?.recordTransform(of: node, oldValue: oldValue)
        node.bump(revision)
    }
}

public struct NodeContentComponent: NodeField {
    public var value: SceneGraph.Node.Content

    public init(value: SceneGraph.Node.Content) {
        self.value = value
    }

    static var defaultValue: SceneGraph.Node.Content { .empty }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeLabelComponent: NodeField {
    public var value: String?

    public init(value: String?) {
        self.value = value
    }

    static var defaultValue: String? { nil }
    static var revision: NodeFieldRevision { .none }
}

public struct NodeIsVisibleComponent: NodeField {
    public var value: Bool

    public init(value: Bool) {
        self.value = value
    }

    static var defaultValue: Bool { true }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeIsActiveComponent: NodeField {
    public var value: Bool

    public init(value: Bool) {
        self.value = value
    }

    static var defaultValue: Bool { true }
    static var revision: NodeFieldRevision { .structure }
}

// Bumps the transform revision, not the structure one, so fading does not rebuild renderer caches.
public struct NodeOpacityComponent: NodeField {
    public var value: Float

    public init(value: Float) {
        self.value = value
    }

    static var defaultValue: Float { 1 }
    static var revision: NodeFieldRevision { .transform }
}

public struct NodePivotComponent: NodeField {
    public var value: simd_float4x4

    public init(value: simd_float4x4) {
        self.value = value
    }

    static var defaultValue: simd_float4x4 { .identity }
    static var revision: NodeFieldRevision { .transform }
}

public struct NodeCategoryBitMaskComponent: NodeField {
    public var value: UInt

    public init(value: UInt) {
        self.value = value
    }

    static var defaultValue: UInt { 1 }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeLightCategoryBitMaskComponent: NodeField {
    public var value: UInt

    public init(value: UInt) {
        self.value = value
    }

    static var defaultValue: UInt { .max }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeRenderingOrderComponent: NodeField {
    public var value: Int

    public init(value: Int) {
        self.value = value
    }

    static var defaultValue: Int { 0 }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodePhysicsBodyComponent: NodeField {
    public var value: SceneGraph.PhysicsBody?

    public init(value: SceneGraph.PhysicsBody?) {
        self.value = value
    }

    static var defaultValue: SceneGraph.PhysicsBody? { nil }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeLevelsOfDetailComponent: NodeField {
    public var value: [SceneGraph.LevelOfDetail]

    public init(value: [SceneGraph.LevelOfDetail]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.LevelOfDetail] { [] }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeParticleSystemsComponent: NodeField {
    public var value: [SceneParticleSystem]

    public init(value: [SceneParticleSystem]) {
        self.value = value
    }

    static var defaultValue: [SceneParticleSystem] { [] }
    static var revision: NodeFieldRevision { .none }
}

public struct NodeAudioPlayersComponent: NodeField {
    public var value: [AudioPlayer]

    public init(value: [AudioPlayer]) {
        self.value = value
    }

    static var defaultValue: [AudioPlayer] { [] }
    static var revision: NodeFieldRevision { .none }
}

public struct NodeSkinComponent: NodeField {
    public var value: SceneGraph.Skin?

    public init(value: SceneGraph.Skin?) {
        self.value = value
    }

    static var defaultValue: SceneGraph.Skin? { nil }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeSkinVerticesComponent: NodeField {
    public var value: [SceneGraph.SkinVertex]

    public init(value: [SceneGraph.SkinVertex]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.SkinVertex] { [] }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeMorphTargetsComponent: NodeField {
    public var value: [SceneGraph.MorphTarget]

    public init(value: [SceneGraph.MorphTarget]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.MorphTarget] { [] }
    static var revision: NodeFieldRevision { .structure }
}

public struct NodeMorphWeightsComponent: NodeField {
    public var value: [Float]

    public init(value: [Float]) {
        self.value = value
    }

    static var defaultValue: [Float] { [] }
    static var revision: NodeFieldRevision { .transform }

    static var needsOldValue: Bool {
        SceneGraph.Transaction.currentIfAny != nil
    }

    static func didChange(_ node: SceneGraph.Node, from oldValue: [Float]) {
        SceneGraph.Transaction.currentIfAny?.recordMorphWeights(of: node, oldValue: oldValue)
        node.bump(revision)
    }
}

// RunningAction is a class, so this array changes only when an action starts or ends, not every frame.
struct NodeRunningActionsComponent: NodeField {
    var value: [SceneGraph.Node.RunningAction]
    static var defaultValue: [SceneGraph.Node.RunningAction] { [] }
    static var revision: NodeFieldRevision { .none }
}

public struct NodeActionSpeedComponent: NodeField {
    public var value: Float

    public init(value: Float) {
        self.value = value
    }

    static var defaultValue: Float { 1 }
    static var revision: NodeFieldRevision { .none }
}

// Replacing constraints resets their acceleration smoothing, however the change is made.
public struct NodeConstraintsComponent: NodeField {
    public var value: [SceneGraph.Constraint]

    public init(value: [SceneGraph.Constraint]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.Constraint] { [] }
    static var revision: NodeFieldRevision { .none }

    static func didChange(_ node: SceneGraph.Node, from _: [SceneGraph.Constraint]) {
        node.accelerationStates = [:]
    }

    static func didChangeInWorld(_ node: SceneGraph.Node) {
        node.accelerationStates = [:]
    }
}

struct NodeAccelerationStatesComponent: NodeField {
    var value: [Int: AccelerationState]
    static var defaultValue: [Int: AccelerationState] { [:] }
    static var revision: NodeFieldRevision { .none }
}

// Changing the level rebuilds `content` from `subdivisionBase`, however the change is made.
public struct NodeSubdivisionLevelComponent: NodeField {
    public var value: Int

    public init(value: Int) {
        self.value = value
    }

    static var defaultValue: Int { 0 }
    static var revision: NodeFieldRevision { .none }

    static var needsOldValue: Bool {
        true
    }

    static func didChange(_ node: SceneGraph.Node, from oldValue: Int) {
        if node.subdivisionLevel != oldValue {
            node.applySubdivision()
        }
    }

    static func didChangeInWorld(_ node: SceneGraph.Node) {
        node.applySubdivision()
    }
}

struct NodeSubdivisionBaseComponent: NodeField {
    var value: MetalMesh?
    static var defaultValue: MetalMesh? { nil }
    static var revision: NodeFieldRevision { .none }
}
