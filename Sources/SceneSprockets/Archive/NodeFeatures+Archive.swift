import Foundation
import MetalSprocketsParticles
import simd

// Morph targets, skins, physics bodies and particle systems in scene.json (#162). Skin joints are stored as
// child-index paths from the root, like constraint targets, and resolved once the whole tree is read.

struct ArchivedSkin: Codable {
    var joints: [[Int]]
    var inverseBindMatrices: [[Float]]
}

struct ArchivedParticleSystem: Codable {
    var system: ParticleSystem
    var seed: UInt32
    // Nil means true.
    var usesNodeTransform: Bool?
}

extension SceneGraph.MorphTarget: Codable {
    enum ArchiveKeys: String, CodingKey {
        case name, positionDeltas, normalDeltas, tangentDeltas
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encodeIfPresent(name, forKey: .name)
        if !positionDeltas.isEmpty {
            try container.encode(positionDeltas, forKey: .positionDeltas)
        }
        if !normalDeltas.isEmpty {
            try container.encode(normalDeltas, forKey: .normalDeltas)
        }
        if !tangentDeltas.isEmpty {
            try container.encode(tangentDeltas, forKey: .tangentDeltas)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        self.init(
            name: try container.decodeIfPresent(String.self, forKey: .name),
            positionDeltas: try container.decodeIfPresent([SIMD3<Float>].self, forKey: .positionDeltas) ?? [],
            normalDeltas: try container.decodeIfPresent([SIMD3<Float>].self, forKey: .normalDeltas) ?? [],
            tangentDeltas: try container.decodeIfPresent([SIMD3<Float>].self, forKey: .tangentDeltas) ?? []
        )
    }
}

extension SceneGraph.SkinVertex: Codable {
    enum ArchiveKeys: String, CodingKey {
        case joints, weights
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(joints, forKey: .joints)
        try container.encode(weights, forKey: .weights)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        self.init(joints: try container.decode(SIMD4<UInt16>.self, forKey: .joints), weights: try container.decode(SIMD4<Float>.self, forKey: .weights))
    }
}

extension SceneGraph.PhysicsBody.BodyType: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .static:
            try container.encode("static")
        case .dynamic:
            try container.encode("dynamic")
        case .kinematic:
            try container.encode("kinematic")
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let name = try container.decode(String.self)
        switch name {
        case "static":
            self = .static
        case "dynamic":
            self = .dynamic
        case "kinematic":
            self = .kinematic
        default:
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unknown physics body type \"\(name)\"")
        }
    }
}

extension SceneGraph.PhysicsBody: Codable {
    enum ArchiveKeys: String, CodingKey {
        case type, shape, mass, friction, restitution
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(shape, forKey: .shape)
        try container.encodeIfPresent(mass, forKey: .mass)
        try container.encode(friction, forKey: .friction)
        try container.encode(restitution, forKey: .restitution)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        self.init(
            type: try container.decode(BodyType.self, forKey: .type),
            shape: try container.decode(Shape.self, forKey: .shape),
            mass: try container.decodeIfPresent(Float.self, forKey: .mass),
            friction: try container.decodeIfPresent(Float.self, forKey: .friction) ?? 0.5,
            restitution: try container.decodeIfPresent(Float.self, forKey: .restitution) ?? 0
        )
    }
}

extension SceneArchiveContext {
    func resolveSkins(root: SceneGraph.Node) throws {
        for (node, archived) in pendingSkins {
            let joints = archived.joints.compactMap { root.archiveNode(at: $0) }
            guard joints.count == archived.joints.count else {
                warn("\(node.label ?? "node"): skin refers to a missing node; skipped")
                continue
            }
            let matrices = try archived.inverseBindMatrices.map { try float4x4(archiveValues: $0) }
            node.skin = SceneGraph.Skin(joints: joints, inverseBindMatrices: matrices)
        }
        pendingSkins = []
    }
}
