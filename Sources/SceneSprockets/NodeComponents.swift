import GeometryLite3D
import SceneSprocketsAudio
import simd
import SwiftECS
import SwiftMesh

// Components a node in a graph stores in the graph's World. Public so ECS apps can query and write them (#269);
// see SceneGraph.world for what direct writes do.

/// The position of a node among its siblings.
///
/// SwiftECS's `ChildOf` relationship has no order, so each child stores its index among its siblings. Writing the
/// index in ``SceneGraph/world`` moves the node among its siblings.
public struct SiblingIndexComponent: Component {
    /// The position of the node among its siblings, from 0.
    public var index: Int

    /// Creates the component with an index.
    public init(index: Int) {
        self.index = index
    }
}

/// The node of an entity in ``SceneGraph/world``.
///
/// Writes made directly to the world use this component to find the node. The component also marks the entity as a
/// node of a scene graph. The reference is unowned, because the entity never lives longer than its node: the world
/// destroys the entity when the node leaves the graph.
public struct NodeReferenceComponent: Component {
    /// The node of the entity.
    public internal(set) unowned var node: SceneGraph.Node?

    init(node: SceneGraph.Node) {
        self.node = node
    }
}

/// The scene graph of an entity, when several scene graphs share one world.
public struct MembershipComponent: Component {
    /// The entity of the root node of the scene graph that the entity belongs to.
    public let rootID: EntityID
}

/// The component that stores ``SceneGraph/Node/transform`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeTransformComponent: NodeField {
    /// The node's local transform.
    public var value: Transform3D

    /// Creates the component with a value.
    public init(value: Transform3D) {
        self.value = value
    }

    static var defaultValue: Transform3D { .identity }
    static var revision: NodeFieldRevision { .transform }

    // Only Transaction.animate uses the old value.
    static var needsOldValue: Bool {
        SceneGraph.Transaction.currentIfAny != nil
    }

    static func didChange(_ node: SceneGraph.Node, from oldValue: Transform3D) {
        SceneGraph.Transaction.currentIfAny?.recordTransform(of: node, oldValue: oldValue)
        node.bump(revision)
    }
}

/// The component that stores ``SceneGraph/Node/content`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeContentComponent: NodeField {
    /// The value of ``SceneGraph/Node/content``.
    public var value: SceneGraph.Node.Content

    /// Creates the component with a value.
    public init(value: SceneGraph.Node.Content) {
        self.value = value
    }

    static var defaultValue: SceneGraph.Node.Content { .empty }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/label`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeLabelComponent: NodeField {
    /// The value of ``SceneGraph/Node/label``.
    public var value: String?

    /// Creates the component with a value.
    public init(value: String?) {
        self.value = value
    }

    static var defaultValue: String? { nil }
    static var revision: NodeFieldRevision { .none }
}

/// The component that stores ``SceneGraph/Node/isVisible`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeIsVisibleComponent: NodeField {
    /// The value of ``SceneGraph/Node/isVisible``.
    public var value: Bool

    /// Creates the component with a value.
    public init(value: Bool) {
        self.value = value
    }

    static var defaultValue: Bool { true }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/isActive`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeIsActiveComponent: NodeField {
    /// The value of ``SceneGraph/Node/isActive``.
    public var value: Bool

    /// Creates the component with a value.
    public init(value: Bool) {
        self.value = value
    }

    static var defaultValue: Bool { true }
    static var revision: NodeFieldRevision { .structure }
}

/// Bumps the transform revision, not the structure one, so fading does not rebuild renderer caches.
/// The component that stores ``SceneGraph/Node/opacity`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeOpacityComponent: NodeField {
    /// The value of ``SceneGraph/Node/opacity``.
    public var value: Float

    /// Creates the component with a value.
    public init(value: Float) {
        self.value = value
    }

    static var defaultValue: Float { 1 }
    static var revision: NodeFieldRevision { .transform }
}

/// The component that stores ``SceneGraph/Node/pivot`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodePivotComponent: NodeField {
    /// The value of ``SceneGraph/Node/pivot``.
    public var value: simd_float4x4

    /// Creates the component with a value.
    public init(value: simd_float4x4) {
        self.value = value
    }

    static var defaultValue: simd_float4x4 { .identity }
    static var revision: NodeFieldRevision { .transform }
}

/// The component that stores ``SceneGraph/Node/categoryBitMask`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeCategoryBitMaskComponent: NodeField {
    /// The value of ``SceneGraph/Node/categoryBitMask``.
    public var value: UInt

    /// Creates the component with a value.
    public init(value: UInt) {
        self.value = value
    }

    static var defaultValue: UInt { 1 }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/lightCategoryBitMask`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeLightCategoryBitMaskComponent: NodeField {
    /// The value of ``SceneGraph/Node/lightCategoryBitMask``.
    public var value: UInt

    /// Creates the component with a value.
    public init(value: UInt) {
        self.value = value
    }

    static var defaultValue: UInt { .max }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/renderingOrder`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeRenderingOrderComponent: NodeField {
    /// The value of ``SceneGraph/Node/renderingOrder``.
    public var value: Int

    /// Creates the component with a value.
    public init(value: Int) {
        self.value = value
    }

    static var defaultValue: Int { 0 }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/physicsBody`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodePhysicsBodyComponent: NodeField {
    /// The value of ``SceneGraph/Node/physicsBody``.
    public var value: SceneGraph.PhysicsBody?

    /// Creates the component with a value.
    public init(value: SceneGraph.PhysicsBody?) {
        self.value = value
    }

    static var defaultValue: SceneGraph.PhysicsBody? { nil }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/levelsOfDetail`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeLevelsOfDetailComponent: NodeField {
    /// The value of ``SceneGraph/Node/levelsOfDetail``.
    public var value: [SceneGraph.LevelOfDetail]

    /// Creates the component with a value.
    public init(value: [SceneGraph.LevelOfDetail]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.LevelOfDetail] { [] }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/particleSystems`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeParticleSystemsComponent: NodeField {
    /// The value of ``SceneGraph/Node/particleSystems``.
    public var value: [SceneParticleSystem]

    /// Creates the component with a value.
    public init(value: [SceneParticleSystem]) {
        self.value = value
    }

    static var defaultValue: [SceneParticleSystem] { [] }
    // Structure: the presentation snapshot lists the systems (#387).
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/text`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeTextComponent: NodeField {
    /// The value of ``SceneGraph/Node/text``.
    public var value: SceneText?

    /// Creates the component with a value.
    public init(value: SceneText?) {
        self.value = value
    }

    static var defaultValue: SceneText? { nil }
    // Structure: the presentation snapshot holds the text (#387).
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/audioPlayers`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeAudioPlayersComponent: NodeField {
    /// The value of ``SceneGraph/Node/audioPlayers``.
    public var value: [AudioPlayer]

    /// Creates the component with a value.
    public init(value: [AudioPlayer]) {
        self.value = value
    }

    static var defaultValue: [AudioPlayer] { [] }
    static var revision: NodeFieldRevision { .none }
}

/// The component that stores ``SceneGraph/Node/skin`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeSkinComponent: NodeField {
    /// The value of ``SceneGraph/Node/skin``.
    public var value: SceneGraph.Skin?

    /// Creates the component with a value.
    public init(value: SceneGraph.Skin?) {
        self.value = value
    }

    static var defaultValue: SceneGraph.Skin? { nil }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/skinVertices`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeSkinVerticesComponent: NodeField {
    /// The value of ``SceneGraph/Node/skinVertices``.
    public var value: [SceneGraph.SkinVertex]

    /// Creates the component with a value.
    public init(value: [SceneGraph.SkinVertex]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.SkinVertex] { [] }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/morphTargets`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeMorphTargetsComponent: NodeField {
    /// The value of ``SceneGraph/Node/morphTargets``.
    public var value: [SceneGraph.MorphTarget]

    /// Creates the component with a value.
    public init(value: [SceneGraph.MorphTarget]) {
        self.value = value
    }

    static var defaultValue: [SceneGraph.MorphTarget] { [] }
    static var revision: NodeFieldRevision { .structure }
}

/// The component that stores ``SceneGraph/Node/morphWeights`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeMorphWeightsComponent: NodeField {
    /// The value of ``SceneGraph/Node/morphWeights``.
    public var value: [Float]

    /// Creates the component with a value.
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

/// The component that stores ``SceneGraph/Node/actionSpeed`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeActionSpeedComponent: NodeField {
    /// The value of ``SceneGraph/Node/actionSpeed``.
    public var value: Float

    /// Creates the component with a value.
    public init(value: Float) {
        self.value = value
    }

    static var defaultValue: Float { 1 }
    static var revision: NodeFieldRevision { .none }
}

/// Replacing constraints resets their acceleration smoothing, however the change is made.
/// The component that stores ``SceneGraph/Node/constraints`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeConstraintsComponent: NodeField {
    /// The value of ``SceneGraph/Node/constraints``.
    public var value: [SceneGraph.Constraint]

    /// Creates the component with a value.
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

/// Changing the level rebuilds `content` from `subdivisionBase`, however the change is made.
/// The component that stores ``SceneGraph/Node/subdivisionLevel`` for a node in ``SceneGraph/world``.
///
/// Writing it in the world changes the node. See <doc:WorkingWithTheWorld>.
public struct NodeSubdivisionLevelComponent: NodeField {
    /// The value of ``SceneGraph/Node/subdivisionLevel``.
    public var value: Int

    /// Creates the component with a value.
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
