import SceneSprocketsAudio
import SwiftECS
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
        NodeFieldSlot(\.audioPlayers, \.audioPlayersStorage)
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

    // Lower values draw first, like SCNNode.renderingOrder. Within one value, each renderer keeps its own order
    // (for example PBR draws opaque before blended).
    public var renderingOrder: Int {
        get { getField(\.renderingOrder, \.renderingOrderStorage) }
        set { setField(\.renderingOrder, \.renderingOrderStorage, newValue) }
    }
}
