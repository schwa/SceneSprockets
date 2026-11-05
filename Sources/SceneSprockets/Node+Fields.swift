import SceneSprocketsAudio
import SwiftECS
import SwiftMesh
import simd

// Node properties stored in the graph's World while the node is in a graph; see Node+Entity.swift. Each has a
// component, a NodeFieldStorage var on Node, a property below and an entry in `worldFields`.

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
