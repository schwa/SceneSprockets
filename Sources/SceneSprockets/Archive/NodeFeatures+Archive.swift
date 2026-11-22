import AVFAudio
import Foundation
import MetalSprocketsParticles
import SceneSprocketsAudio
import simd
import SwiftMesh

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

// A level of detail's mesh is a file written by the archive's mesh codec, like a node mesh that is not a shape (#182).
// Nil draws nothing.
struct ArchivedLevelOfDetail: Codable {
    var file: String?
    var distance: Float
}

// An audio player's buffer is a CAF file in the package; players that share a buffer share the file (#182). The
// position is not saved: Audio sets it from the node every frame.
struct ArchivedAudioPlayer: Codable {
    var file: String
    var loops: Bool
    var volume: Float
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
        case type, shape, mass, friction, restitution, isTrigger, categoryBitMask, collisionBitMask
        case linearDamping, angularDamping, gravityFactor, allowsSleeping, usesContinuousCollision
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(shape, forKey: .shape)
        try container.encodeIfPresent(mass, forKey: .mass)
        try container.encode(friction, forKey: .friction)
        try container.encode(restitution, forKey: .restitution)
        if isTrigger {
            try container.encode(isTrigger, forKey: .isTrigger)
        }
        if categoryBitMask != 1 {
            try container.encode(categoryBitMask, forKey: .categoryBitMask)
        }
        if collisionBitMask != .max {
            try container.encode(collisionBitMask, forKey: .collisionBitMask)
        }
        let defaults = Self(type: type, shape: shape)
        if linearDamping != defaults.linearDamping {
            try container.encode(linearDamping, forKey: .linearDamping)
        }
        if angularDamping != defaults.angularDamping {
            try container.encode(angularDamping, forKey: .angularDamping)
        }
        if gravityFactor != defaults.gravityFactor {
            try container.encode(gravityFactor, forKey: .gravityFactor)
        }
        if allowsSleeping != defaults.allowsSleeping {
            try container.encode(allowsSleeping, forKey: .allowsSleeping)
        }
        if usesContinuousCollision != defaults.usesContinuousCollision {
            try container.encode(usesContinuousCollision, forKey: .usesContinuousCollision)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        self.init(
            type: try container.decode(BodyType.self, forKey: .type),
            shape: try container.decode(Shape.self, forKey: .shape),
            mass: try container.decodeIfPresent(Float.self, forKey: .mass),
            friction: try container.decodeIfPresent(Float.self, forKey: .friction) ?? 0.5,
            restitution: try container.decodeIfPresent(Float.self, forKey: .restitution) ?? 0,
            linearDamping: try container.decodeIfPresent(Float.self, forKey: .linearDamping) ?? 0.05,
            angularDamping: try container.decodeIfPresent(Float.self, forKey: .angularDamping) ?? 0.05,
            gravityFactor: try container.decodeIfPresent(Float.self, forKey: .gravityFactor) ?? 1,
            allowsSleeping: try container.decodeIfPresent(Bool.self, forKey: .allowsSleeping) ?? true,
            usesContinuousCollision: try container.decodeIfPresent(Bool.self, forKey: .usesContinuousCollision) ?? false,
            isTrigger: try container.decodeIfPresent(Bool.self, forKey: .isTrigger) ?? false,
            categoryBitMask: try container.decodeIfPresent(UInt32.self, forKey: .categoryBitMask) ?? 1,
            collisionBitMask: try container.decodeIfPresent(UInt32.self, forKey: .collisionBitMask) ?? .max
        )
    }
}

extension ArchiveContext {
    // The package path of the mesh's codec file, written once for meshes that share buffers.
    func meshFile(for mesh: MetalMesh, materials: [any SceneMaterial], name: String?, codec: any ArchivableMeshCodec) throws -> String {
        let key = meshKey(mesh)
        if let path = meshFiles[key] {
            return path
        }
        let path = try codec.encode(mesh, materials: materials, name: name, context: self)
        meshFiles[key] = path
        return path
    }

    func mesh(atPath path: String, codec: any ArchivableMeshCodec) throws -> MetalMesh {
        if let mesh = decodedMeshes[path] {
            return mesh
        }
        let mesh = try codec.decode(path: path, context: self)
        decodedMeshes[path] = mesh
        return mesh
    }

    // The package path of the buffer's CAF file, written once for players that share a buffer.
    func audioFile(for buffer: AVAudioPCMBuffer) throws -> String {
        if let path = audioFiles[ObjectIdentifier(buffer)] {
            return path
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: temporary) }
        // Scoped so the file is closed before it is read.
        do {
            let file = try AVAudioFile(forWriting: temporary, settings: buffer.format.settings, commonFormat: buffer.format.commonFormat, interleaved: buffer.format.isInterleaved)
            try file.write(from: buffer)
        }
        let path = newFile(in: "audio", pathExtension: "caf")
        addFile(path, data: try Data(contentsOf: temporary))
        audioFiles[ObjectIdentifier(buffer)] = path
        return path
    }

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
