import SceneSprocketsAudio
import SwiftECS
import SwiftMesh
import simd

// Node properties stored in the graph's World while the node is in a graph; see Node+Entity.swift. Each has a
// component, a NodeFieldStorage var on Node, a property below and an entry in `worldFields`.

struct NodeTransformComponent: NodeField {
    var value: SceneGraph.LocalTransform
    static var defaultValue: SceneGraph.LocalTransform { .matrix(.identity) }
    static var revision: NodeFieldRevision { .transform }

    static func didChange(_ node: SceneGraph.Node, from oldValue: SceneGraph.LocalTransform) {
        SceneGraph.Transaction.current?.recordTransform(of: node, oldValue: oldValue)
        node.bump(revision)
    }
}

struct NodeContentComponent: NodeField {
    var value: SceneGraph.Node.Content
    static var defaultValue: SceneGraph.Node.Content { .empty }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeLabelComponent: NodeField {
    var value: String?
    static var defaultValue: String? { nil }
    static var revision: NodeFieldRevision { .none }
}

struct NodeIsVisibleComponent: NodeField {
    var value: Bool
    static var defaultValue: Bool { true }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeIsActiveComponent: NodeField {
    var value: Bool
    static var defaultValue: Bool { true }
    static var revision: NodeFieldRevision { .structure }
}

// Bumps the transform revision, not the structure one, so fading does not rebuild renderer caches.
struct NodeOpacityComponent: NodeField {
    var value: Float
    static var defaultValue: Float { 1 }
    static var revision: NodeFieldRevision { .transform }
}

struct NodePivotComponent: NodeField {
    var value: simd_float4x4
    static var defaultValue: simd_float4x4 { .identity }
    static var revision: NodeFieldRevision { .transform }
}

struct NodeCategoryBitMaskComponent: NodeField {
    var value: UInt
    static var defaultValue: UInt { 1 }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeLightCategoryBitMaskComponent: NodeField {
    var value: UInt
    static var defaultValue: UInt { .max }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeRenderingOrderComponent: NodeField {
    var value: Int
    static var defaultValue: Int { 0 }
    static var revision: NodeFieldRevision { .structure }
}

struct NodePhysicsBodyComponent: NodeField {
    var value: SceneGraph.PhysicsBody?
    static var defaultValue: SceneGraph.PhysicsBody? { nil }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeLevelsOfDetailComponent: NodeField {
    var value: [SceneGraph.LevelOfDetail]
    static var defaultValue: [SceneGraph.LevelOfDetail] { [] }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeParticleSystemsComponent: NodeField {
    var value: [SceneParticleSystem]
    static var defaultValue: [SceneParticleSystem] { [] }
    static var revision: NodeFieldRevision { .none }
}

struct NodeAudioPlayersComponent: NodeField {
    var value: [AudioPlayer]
    static var defaultValue: [AudioPlayer] { [] }
    static var revision: NodeFieldRevision { .none }
}

struct NodeSkinComponent: NodeField {
    var value: SceneGraph.Skin?
    static var defaultValue: SceneGraph.Skin? { nil }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeSkinVerticesComponent: NodeField {
    var value: [SceneGraph.SkinVertex]
    static var defaultValue: [SceneGraph.SkinVertex] { [] }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeMorphTargetsComponent: NodeField {
    var value: [SceneGraph.MorphTarget]
    static var defaultValue: [SceneGraph.MorphTarget] { [] }
    static var revision: NodeFieldRevision { .structure }
}

struct NodeMorphWeightsComponent: NodeField {
    var value: [Float]
    static var defaultValue: [Float] { [] }
    static var revision: NodeFieldRevision { .transform }

    static func didChange(_ node: SceneGraph.Node, from oldValue: [Float]) {
        SceneGraph.Transaction.current?.recordMorphWeights(of: node, oldValue: oldValue)
        node.bump(revision)
    }
}

// RunningAction is a class, so this array changes only when an action starts or ends, not every frame.
struct NodeRunningActionsComponent: NodeField {
    var value: [SceneGraph.Node.RunningAction]
    static var defaultValue: [SceneGraph.Node.RunningAction] { [] }
    static var revision: NodeFieldRevision { .none }
}

struct NodeActionSpeedComponent: NodeField {
    var value: Float
    static var defaultValue: Float { 1 }
    static var revision: NodeFieldRevision { .none }
}

// Replacing constraints resets their acceleration smoothing, however the change is made.
struct NodeConstraintsComponent: NodeField {
    var value: [SceneGraph.Constraint]
    static var defaultValue: [SceneGraph.Constraint] { [] }
    static var revision: NodeFieldRevision { .none }

    static func didChange(_ node: SceneGraph.Node, from oldValue: [SceneGraph.Constraint]) {
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
struct NodeSubdivisionLevelComponent: NodeField {
    var value: Int
    static var defaultValue: Int { 0 }
    static var revision: NodeFieldRevision { .none }

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

extension SceneGraph.Node {
    static let worldFields: [NodeFieldSlot] = [
        NodeFieldSlot(\.localTransform, \.localTransformStorage),
        NodeFieldSlot(\.content, \.contentStorage),
        NodeFieldSlot(\.label, \.labelStorage),
        NodeFieldSlot(\.isVisible, \.isVisibleStorage),
        NodeFieldSlot(\.isActive, \.isActiveStorage),
        NodeFieldSlot(\.opacity, \.opacityStorage),
        NodeFieldSlot(\.pivot, \.pivotStorage),
        NodeFieldSlot(\.categoryBitMask, \.categoryBitMaskStorage),
        NodeFieldSlot(\.lightCategoryBitMask, \.lightCategoryBitMaskStorage),
        NodeFieldSlot(\.renderingOrder, \.renderingOrderStorage),
        NodeFieldSlot(\.physicsBody, \.physicsBodyStorage),
        NodeFieldSlot(\.levelsOfDetail, \.levelsOfDetailStorage),
        NodeFieldSlot(\.particleSystems, \.particleSystemsStorage),
        NodeFieldSlot(\.audioPlayers, \.audioPlayersStorage),
        NodeFieldSlot(\.skin, \.skinStorage),
        NodeFieldSlot(\.skinVertices, \.skinVerticesStorage),
        NodeFieldSlot(\.morphTargets, \.morphTargetsStorage),
        NodeFieldSlot(\.morphWeights, \.morphWeightsStorage),
        NodeFieldSlot(\.runningActions, \.runningActionsStorage),
        NodeFieldSlot(\.actionSpeed, \.actionSpeedStorage),
        NodeFieldSlot(\.constraints, \.constraintsStorage),
        NodeFieldSlot(\.accelerationStates, \.accelerationStatesStorage),
        NodeFieldSlot(\.subdivisionLevel, \.subdivisionLevelStorage),
        NodeFieldSlot(\.subdivisionBase, \.subdivisionBaseStorage)
    ]

    public var localTransform: SceneGraph.LocalTransform {
        get { getField(\.localTransform, \.localTransformStorage) }
        set { setField(\.localTransform, \.localTransformStorage, newValue) }
    }

    public var content: Content {
        get { getField(\.content, \.contentStorage) }
        set { setField(\.content, \.contentStorage, newValue) }
    }

    public var label: String? {
        get { getField(\.label, \.labelStorage) }
        set { setField(\.label, \.labelStorage, newValue) }
    }

    // False hides this node and its subtree from traversal, rendering and bounds.
    public var isVisible: Bool {
        get { getField(\.isVisible, \.isVisibleStorage) }
        set { setField(\.isVisible, \.isVisibleStorage, newValue) }
    }

    // False is hidden and also stops this subtree's actions, constraints, particles and physics, like Unity's
    // GameObject.SetActive(false). Hidden-but-active nodes keep animating (#196).
    public var isActive: Bool {
        get { getField(\.isActive, \.isActiveStorage) }
        set { setField(\.isActive, \.isActiveStorage, newValue) }
    }

    // 0 is invisible, 1 opaque; multiplies with the ancestors' opacity, like SCNNode.opacity. Applied by materials
    // with appliesNodeOpacity (Blinn-Phong, ShaderMaterial, PBR).
    public var opacity: Float {
        get { getField(\.opacity, \.opacityStorage) }
        set { setField(\.opacity, \.opacityStorage, newValue) }
    }

    // The point position, rotation and scale apply around, like SCNNode.pivot: content and children are drawn
    // at transform * pivot.inverse. Identity by default.
    public var pivot: simd_float4x4 {
        get { getField(\.pivot, \.pivotStorage) }
        set { setField(\.pivot, \.pivotStorage, newValue) }
    }

    // Matched against camera, light and hit-test masks, like SCNNode.categoryBitMask. Not inherited by children.
    public var categoryBitMask: UInt {
        get { getField(\.categoryBitMask, \.categoryBitMaskStorage) }
        set { setField(\.categoryBitMask, \.categoryBitMaskStorage, newValue) }
    }

    // For light nodes: lights only meshes whose categoryBitMask shares a bit with this, like
    // SCNLight.categoryBitMask.
    public var lightCategoryBitMask: UInt {
        get { getField(\.lightCategoryBitMask, \.lightCategoryBitMaskStorage) }
        set { setField(\.lightCategoryBitMask, \.lightCategoryBitMaskStorage, newValue) }
    }

    // Simulated by SceneSprocketsPhysics when set.
    public var physicsBody: SceneGraph.PhysicsBody? {
        get { getField(\.physicsBody, \.physicsBodyStorage) }
        set { setField(\.physicsBody, \.physicsBodyStorage, newValue) }
    }

    // Simpler meshes for distant cameras; see LevelOfDetail. Order does not matter.
    public var levelsOfDetail: [SceneGraph.LevelOfDetail] {
        get { getField(\.levelsOfDetail, \.levelsOfDetailStorage) }
        set { setField(\.levelsOfDetail, \.levelsOfDetailStorage, newValue) }
    }

    // Particle effects at this node; see SceneParticleSystem. Shared, not copied, by clone().
    public var particleSystems: [SceneParticleSystem] {
        get { getField(\.particleSystems, \.particleSystemsStorage) }
        set { setField(\.particleSystems, \.particleSystemsStorage, newValue) }
    }

    // Sounds that play from this node; see SceneAudio. Not copied by clone().
    public var audioPlayers: [AudioPlayer] {
        get { getField(\.audioPlayers, \.audioPlayersStorage) }
        set { setField(\.audioPlayers, \.audioPlayersStorage, newValue) }
    }

    // Skinned meshes are placed by their joints, not by this node's transform.
    public var skin: SceneGraph.Skin? {
        get { getField(\.skin, \.skinStorage) }
        set { setField(\.skin, \.skinStorage, newValue) }
    }

    // Per-vertex joint influences for this node's mesh; indexed like its vertices.
    public var skinVertices: [SceneGraph.SkinVertex] {
        get { getField(\.skinVertices, \.skinVerticesStorage) }
        set { setField(\.skinVertices, \.skinVerticesStorage, newValue) }
    }

    // Blend shapes for this node's mesh (MetalMesh cannot carry them). Weighted by morphWeights.
    public var morphTargets: [SceneGraph.MorphTarget] {
        get { getField(\.morphTargets, \.morphTargetsStorage) }
        set { setField(\.morphTargets, \.morphTargetsStorage, newValue) }
    }

    // Morph target weights for this node's mesh; animated like transforms.
    public var morphWeights: [Float] {
        get { getField(\.morphWeights, \.morphWeightsStorage) }
        set { setField(\.morphWeights, \.morphWeightsStorage, newValue) }
    }

    var runningActions: [RunningAction] {
        get { getField(\.runningActions, \.runningActionsStorage) }
        set { setField(\.runningActions, \.runningActionsStorage, newValue) }
    }

    // Multiplies the time this node's actions advance by; 0 pauses them. Not inherited by children.
    public var actionSpeed: Float {
        get { getField(\.actionSpeed, \.actionSpeedStorage) }
        set { setField(\.actionSpeed, \.actionSpeedStorage, newValue) }
    }

    // Applied in order by SceneGraph.applyConstraints(pointOfView:deltaTime:).
    public var constraints: [SceneGraph.Constraint] {
        get { getField(\.constraints, \.constraintsStorage) }
        set { setField(\.constraints, \.constraintsStorage, newValue) }
    }

    // Smoothed position and velocity of each acceleration constraint, by index in `constraints`.
    var accelerationStates: [Int: AccelerationState] {
        get { getField(\.accelerationStates, \.accelerationStatesStorage) }
        set { setField(\.accelerationStates, \.accelerationStatesStorage, newValue) }
    }

    // Loop-subdivides this node's mesh, like SCNGeometry.subdivisionLevel; 0 restores the original. Triangle
    // meshes only. Setting `shape` rebuilds and subdivides again.
    public var subdivisionLevel: Int {
        get { getField(\.subdivisionLevel, \.subdivisionLevelStorage) }
        set { setField(\.subdivisionLevel, \.subdivisionLevelStorage, newValue) }
    }

    var subdivisionBase: MetalMesh? {
        get { getField(\.subdivisionBase, \.subdivisionBaseStorage) }
        set { setField(\.subdivisionBase, \.subdivisionBaseStorage, newValue) }
    }

    // Lower values draw first, like SCNNode.renderingOrder. Within one value, each renderer keeps its own order
    // (for example PBR draws opaque before blended).
    public var renderingOrder: Int {
        get { getField(\.renderingOrder, \.renderingOrderStorage) }
        set { setField(\.renderingOrder, \.renderingOrderStorage, newValue) }
    }
}
