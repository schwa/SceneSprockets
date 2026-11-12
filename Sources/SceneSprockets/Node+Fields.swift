import GeometryLite3D
import SceneSprocketsAudio
import simd
import SwiftECS
import SwiftMesh

// Node properties stored in the graph's World while the node is in a graph; see Node+Entity.swift. Each has a
// component, a NodeFieldStorage var on Node, a property below and an entry in `worldFields`.

// Made once: a key path literal passed to access(keyPath:) or withMutation(keyPath:) is instantiated through the
// runtime on every call (#283).
private enum FieldKeyPaths {
    static let transform = \SceneGraph.Node.transform
    static let content = \SceneGraph.Node.content
    static let label = \SceneGraph.Node.label
    static let isVisible = \SceneGraph.Node.isVisible
    static let isActive = \SceneGraph.Node.isActive
    static let opacity = \SceneGraph.Node.opacity
    static let pivot = \SceneGraph.Node.pivot
    static let categoryBitMask = \SceneGraph.Node.categoryBitMask
    static let lightCategoryBitMask = \SceneGraph.Node.lightCategoryBitMask
    static let physicsBody = \SceneGraph.Node.physicsBody
    static let levelsOfDetail = \SceneGraph.Node.levelsOfDetail
    static let particleSystems = \SceneGraph.Node.particleSystems
    static let audioPlayers = \SceneGraph.Node.audioPlayers
    static let text = \SceneGraph.Node.text
    static let skin = \SceneGraph.Node.skin
    static let skinVertices = \SceneGraph.Node.skinVertices
    static let morphTargets = \SceneGraph.Node.morphTargets
    static let morphWeights = \SceneGraph.Node.morphWeights
    static let runningActions = \SceneGraph.Node.runningActions
    static let actionSpeed = \SceneGraph.Node.actionSpeed
    static let constraints = \SceneGraph.Node.constraints
    static let accelerationStates = \SceneGraph.Node.accelerationStates
    static let subdivisionLevel = \SceneGraph.Node.subdivisionLevel
    static let subdivisionBase = \SceneGraph.Node.subdivisionBase
    static let renderingOrder = \SceneGraph.Node.renderingOrder
}

extension SceneGraph.Node {
    // Every component attach() gives a node's entity: the three below, then one per world field.
    static let entityComponentTypes: [ComponentType] = [
        ComponentType(SiblingIndexComponent.self),
        ComponentType(NodeReferenceComponent.self),
        ComponentType(MembershipComponent.self)
    ] + worldFields.map(\.componentType)

    static let worldFields: [NodeFieldSlot] = [
        NodeFieldSlot(\.transform, \.transformStorage),
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
        NodeFieldSlot(\.text, \.textStorage),
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

    /// The node's transform relative to its parent. Does not include ``pivot``.
    ///
    /// Read and write its parts through it: `transform.translation`, `transform.rotation` (`.quaternion` or `.euler`),
    /// `transform.scale` and `transform.matrix`. It stores a matrix or translation, rotation and scale; editing a part
    /// keeps that storage kind.
    public var transform: Transform3D {
        get { getField(FieldKeyPaths.transform, \.transformStorage) }
        set { setField(FieldKeyPaths.transform, \.transformStorage, newValue) }
    }

    /// What the node shows: nothing, a mesh, a light or a camera.
    public var content: Content {
        get { getField(FieldKeyPaths.content, \.contentStorage) }
        set { setField(FieldKeyPaths.content, \.contentStorage, newValue) }
    }

    /// A name for the node, for debugging, outlines and archives.
    public var label: String? {
        get { getField(FieldKeyPaths.label, \.labelStorage) }
        set { setField(FieldKeyPaths.label, \.labelStorage, newValue) }
    }

    /// False hides this node and its subtree from traversal, rendering and bounds.
    public var isVisible: Bool {
        get { getField(FieldKeyPaths.isVisible, \.isVisibleStorage) }
        set { setField(FieldKeyPaths.isVisible, \.isVisibleStorage, newValue) }
    }

    /// False is hidden and also stops this subtree's actions, constraints, particles and physics, like Unity's
    /// GameObject.SetActive(false). Hidden-but-active nodes keep animating (#196).
    public var isActive: Bool {
        get { getField(FieldKeyPaths.isActive, \.isActiveStorage) }
        set { setField(FieldKeyPaths.isActive, \.isActiveStorage, newValue) }
    }

    /// 0 is invisible, 1 opaque; multiplies with the ancestors' opacity, like SCNNode.opacity. Applied by materials
    /// with appliesNodeOpacity (Blinn-Phong, ShaderMaterial, PBR).
    public var opacity: Float {
        get { getField(FieldKeyPaths.opacity, \.opacityStorage) }
        set { setField(FieldKeyPaths.opacity, \.opacityStorage, newValue) }
    }

    /// The point position, rotation and scale apply around, like SCNNode.pivot: content and children are drawn
    /// at transform * pivot.inverse. Identity by default.
    public var pivot: simd_float4x4 {
        get { getField(FieldKeyPaths.pivot, \.pivotStorage) }
        set { setField(FieldKeyPaths.pivot, \.pivotStorage, newValue) }
    }

    /// Matched against camera, light and hit-test masks, like SCNNode.categoryBitMask. Not inherited by children.
    public var categoryBitMask: UInt {
        get { getField(FieldKeyPaths.categoryBitMask, \.categoryBitMaskStorage) }
        set { setField(FieldKeyPaths.categoryBitMask, \.categoryBitMaskStorage, newValue) }
    }

    /// For light nodes: lights only meshes whose categoryBitMask shares a bit with this, like
    /// SCNLight.categoryBitMask.
    public var lightCategoryBitMask: UInt {
        get { getField(FieldKeyPaths.lightCategoryBitMask, \.lightCategoryBitMaskStorage) }
        set { setField(FieldKeyPaths.lightCategoryBitMask, \.lightCategoryBitMaskStorage, newValue) }
    }

    /// Simulated by SceneSprocketsPhysics when set.
    public var physicsBody: SceneGraph.PhysicsBody? {
        get { getField(FieldKeyPaths.physicsBody, \.physicsBodyStorage) }
        set { setField(FieldKeyPaths.physicsBody, \.physicsBodyStorage, newValue) }
    }

    /// Simpler meshes for distant cameras; see LevelOfDetail. Order does not matter.
    public var levelsOfDetail: [SceneGraph.LevelOfDetail] {
        get { getField(FieldKeyPaths.levelsOfDetail, \.levelsOfDetailStorage) }
        set { setField(FieldKeyPaths.levelsOfDetail, \.levelsOfDetailStorage, newValue) }
    }

    /// Particle effects at this node; see SceneParticleSystem. Shared, not copied, by clone().
    public var particleSystems: [SceneParticleSystem] {
        get { getField(FieldKeyPaths.particleSystems, \.particleSystemsStorage) }
        set { setField(FieldKeyPaths.particleSystems, \.particleSystemsStorage, newValue) }
    }

    /// Flat text at this node; see SceneText.
    public var text: SceneText? {
        get { getField(FieldKeyPaths.text, \.textStorage) }
        set { setField(FieldKeyPaths.text, \.textStorage, newValue) }
    }

    /// Sounds that play from this node; see Audio. Not copied by clone().
    public var audioPlayers: [AudioPlayer] {
        get { getField(FieldKeyPaths.audioPlayers, \.audioPlayersStorage) }
        set { setField(FieldKeyPaths.audioPlayers, \.audioPlayersStorage, newValue) }
    }

    /// Skinned meshes are placed by their joints, not by this node's transform.
    public var skin: SceneGraph.Skin? {
        get { getField(FieldKeyPaths.skin, \.skinStorage) }
        set { setField(FieldKeyPaths.skin, \.skinStorage, newValue) }
    }

    /// Per-vertex joint influences for this node's mesh; indexed like its vertices.
    public var skinVertices: [SceneGraph.SkinVertex] {
        get { getField(FieldKeyPaths.skinVertices, \.skinVerticesStorage) }
        set { setField(FieldKeyPaths.skinVertices, \.skinVerticesStorage, newValue) }
    }

    /// Blend shapes for this node's mesh (MetalMesh cannot carry them). Weighted by morphWeights.
    public var morphTargets: [SceneGraph.MorphTarget] {
        get { getField(FieldKeyPaths.morphTargets, \.morphTargetsStorage) }
        set { setField(FieldKeyPaths.morphTargets, \.morphTargetsStorage, newValue) }
    }

    /// Morph target weights for this node's mesh; animated like transforms.
    public var morphWeights: [Float] {
        get { getField(FieldKeyPaths.morphWeights, \.morphWeightsStorage) }
        set { setField(FieldKeyPaths.morphWeights, \.morphWeightsStorage, newValue) }
    }

    var runningActions: [RunningAction] {
        get { getField(FieldKeyPaths.runningActions, \.runningActionsStorage) }
        set { setField(FieldKeyPaths.runningActions, \.runningActionsStorage, newValue) }
    }

    /// Multiplies the time this node's actions advance by; 0 pauses them. Not inherited by children.
    public var actionSpeed: Float {
        get { getField(FieldKeyPaths.actionSpeed, \.actionSpeedStorage) }
        set { setField(FieldKeyPaths.actionSpeed, \.actionSpeedStorage, newValue) }
    }

    /// Applied in order by SceneGraph.applyConstraints(pointOfView:deltaTime:).
    public var constraints: [SceneGraph.Constraint] {
        get { getField(FieldKeyPaths.constraints, \.constraintsStorage) }
        set { setField(FieldKeyPaths.constraints, \.constraintsStorage, newValue) }
    }

    // Smoothed position and velocity of each acceleration constraint, by index in `constraints`.
    var accelerationStates: [Int: AccelerationState] {
        get { getField(FieldKeyPaths.accelerationStates, \.accelerationStatesStorage) }
        set { setField(FieldKeyPaths.accelerationStates, \.accelerationStatesStorage, newValue) }
    }

    /// Loop-subdivides this node's mesh, like SCNGeometry.subdivisionLevel; 0 restores the original. Triangle
    /// meshes only. Setting `shape` rebuilds and subdivides again.
    public var subdivisionLevel: Int {
        get { getField(FieldKeyPaths.subdivisionLevel, \.subdivisionLevelStorage) }
        set { setField(FieldKeyPaths.subdivisionLevel, \.subdivisionLevelStorage, newValue) }
    }

    var subdivisionBase: MetalMesh? {
        get { getField(FieldKeyPaths.subdivisionBase, \.subdivisionBaseStorage) }
        set { setField(FieldKeyPaths.subdivisionBase, \.subdivisionBaseStorage, newValue) }
    }

    /// Lower values draw first, like SCNNode.renderingOrder. Within one value, each renderer keeps its own order
    /// (for example PBR draws opaque before blended).
    public var renderingOrder: Int {
        get { getField(FieldKeyPaths.renderingOrder, \.renderingOrderStorage) }
        set { setField(FieldKeyPaths.renderingOrder, \.renderingOrderStorage, newValue) }
    }
}
