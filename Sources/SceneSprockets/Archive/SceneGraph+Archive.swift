import Foundation
import GeometryLite3D
import simd

// Codable for the scene graph types, used by SceneArchive. Metal-backed content (textures, environment maps,
// materials) goes through the SceneArchiveContext in the coder's userInfo.

// MARK: - Scene graph

extension SceneGraph: Codable {
    enum ArchiveKeys: String, CodingKey {
        case formatVersion, root, environment, fog, postProcessing
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(SceneArchive.formatVersion, forKey: .formatVersion)
        try container.encode(root, forKey: .root)
        try container.encode(environment, forKey: .environment)
        try container.encodeIfPresent(fog, forKey: .fog)
        try container.encodeIfPresent(postProcessing, forKey: .postProcessing)
    }

    // Called from init(from:), which has to be in the class declaration.
    func decodeArchive(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        let version = try container.decode(Int.self, forKey: .formatVersion)
        guard version <= SceneArchive.formatVersion else {
            throw SceneArchiveError.unsupportedFormatVersion(version)
        }
        root = try container.decode(Node.self, forKey: .root)
        environment = try container.decode(Environment.self, forKey: .environment)
        fog = try container.decodeIfPresent(Fog.self, forKey: .fog)
        postProcessing = try container.decodeIfPresent(PostProcessing.self, forKey: .postProcessing)
    }
}

// MARK: - Nodes

extension SceneGraph.Node: Codable {
    enum ArchiveKeys: String, CodingKey {
        case label, transform, pivot, isVisible, opacity, categoryBitMask, lightCategoryBitMask, renderingOrder
        case subdivisionLevel, actionSpeed, mesh, light, camera, children
    }

    enum MeshKeys: String, CodingKey {
        case shape, materials, castsShadow, receivesShadow
    }

    enum MaterialKeys: String, CodingKey {
        case type, value
    }

    public func encode(to encoder: Encoder) throws {
        let context = try encoder.sceneArchive
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(localTransform, forKey: .transform)
        if pivot != .identity {
            try container.encode(pivot.archiveValues, forKey: .pivot)
        }
        if !isVisible {
            try container.encode(isVisible, forKey: .isVisible)
        }
        if opacity != 1 {
            try container.encode(opacity, forKey: .opacity)
        }
        if categoryBitMask != 1 {
            try container.encode(categoryBitMask, forKey: .categoryBitMask)
        }
        if lightCategoryBitMask != .max {
            try container.encode(lightCategoryBitMask, forKey: .lightCategoryBitMask)
        }
        if renderingOrder != 0 {
            try container.encode(renderingOrder, forKey: .renderingOrder)
        }
        if subdivisionLevel != 0 {
            try container.encode(subdivisionLevel, forKey: .subdivisionLevel)
        }
        if actionSpeed != 1 {
            try container.encode(actionSpeed, forKey: .actionSpeed)
        }
        switch content {
        case .empty:
            break
        case let .light(light):
            try container.encode(light, forKey: .light)
        case let .camera(camera):
            try container.encode(camera, forKey: .camera)
        case let .mesh(_, materials, castsShadow, receivesShadow):
            if let shape {
                var mesh = container.nestedContainer(keyedBy: MeshKeys.self, forKey: .mesh)
                try mesh.encode(shape, forKey: .shape)
                try mesh.encode(castsShadow, forKey: .castsShadow)
                try mesh.encode(receivesShadow, forKey: .receivesShadow)
                var list = mesh.nestedUnkeyedContainer(forKey: .materials)
                for material in materials {
                    guard let archivable = material as? any ArchivableMaterial else {
                        context.warn("\(nodeDescription): \(type(of: material)) is not archivable; skipped")
                        continue
                    }
                    var item = list.nestedContainer(keyedBy: MaterialKeys.self)
                    try item.encode(type(of: archivable).archiveTypeName, forKey: .type)
                    try archivable.encode(to: item.superEncoder(forKey: .value))
                }
            } else {
                // glTF references (#157) and generated meshes (#158) come later.
                context.warn("\(nodeDescription): mesh is not a shape; not saved yet (#157, #158)")
            }
        }
        warnAboutUnsavedFeatures(context)
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    // Called from init(from:), which has to be in the class declaration.
    func decodeArchive(from decoder: Decoder) throws {
        let context = try decoder.sceneArchive
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        localTransform = try container.decode(SceneGraph.LocalTransform.self, forKey: .transform)
        if let values = try container.decodeIfPresent([Float].self, forKey: .pivot) {
            pivot = try float4x4(archiveValues: values)
        }
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        opacity = try container.decodeIfPresent(Float.self, forKey: .opacity) ?? 1
        categoryBitMask = try container.decodeIfPresent(UInt.self, forKey: .categoryBitMask) ?? 1
        lightCategoryBitMask = try container.decodeIfPresent(UInt.self, forKey: .lightCategoryBitMask) ?? .max
        renderingOrder = try container.decodeIfPresent(Int.self, forKey: .renderingOrder) ?? 0
        actionSpeed = try container.decodeIfPresent(Float.self, forKey: .actionSpeed) ?? 1
        if let light = try container.decodeIfPresent(Light.self, forKey: .light) {
            content = .light(light)
        } else if let camera = try container.decodeIfPresent(Camera.self, forKey: .camera) {
            content = .camera(camera)
        } else if container.contains(.mesh) {
            let mesh = try container.nestedContainer(keyedBy: MeshKeys.self, forKey: .mesh)
            let shape = try mesh.decode(SceneGraph.Shape.self, forKey: .shape)
            var list = try mesh.nestedUnkeyedContainer(forKey: .materials)
            var materials: [any Material] = []
            while !list.isAtEnd {
                let item = try list.nestedContainer(keyedBy: MaterialKeys.self)
                let name = try item.decode(String.self, forKey: .type)
                guard let materialType = context.materialType(named: name) else {
                    context.warn("\(label ?? "node"): no registered material type \"\(name)\"; skipped")
                    continue
                }
                materials.append(try materialType.init(from: item.superDecoder(forKey: .value)))
            }
            if materials.isEmpty {
                context.warn("\(label ?? "node"): no materials could be read; mesh dropped")
            } else {
                let device = try context.device
                content = .mesh(shape.metalMesh(device: device), materials: materials, castsShadow: try mesh.decode(Bool.self, forKey: .castsShadow), receivesShadow: try mesh.decode(Bool.self, forKey: .receivesShadow))
                shapeStorage = (shape, device)
            }
        }
        // After the content, so subdivision applies to the shape's mesh.
        subdivisionLevel = try container.decodeIfPresent(Int.self, forKey: .subdivisionLevel) ?? 0
        for child in try container.decodeIfPresent([SceneGraph.Node].self, forKey: .children) ?? [] {
            addChild(child)
        }
    }

    private var nodeDescription: String {
        label.map { "\"\($0)\"" } ?? "unnamed node"
    }

    // Later steps of #52.
    private func warnAboutUnsavedFeatures(_ context: SceneArchiveContext) {
        let unsaved: [(String, Bool)] = [
            ("morph targets", !morphTargets.isEmpty),
            ("skin", skin != nil),
            ("constraints", !constraints.isEmpty),
            ("physics body", physicsBody != nil),
            ("particle systems", !particleSystems.isEmpty),
            ("audio players", !audioPlayers.isEmpty),
            ("levels of detail", !levelsOfDetail.isEmpty),
            ("running actions", !runningActions.isEmpty),
        ]
        for (feature, isPresent) in unsaved where isPresent {
            context.warn("\(nodeDescription): \(feature) not saved yet")
        }
    }
}

extension SceneGraph.LocalTransform: Codable {
    enum ArchiveKeys: String, CodingKey {
        case trs, matrix
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        switch self {
        case let .trs(trs):
            try container.encode(trs, forKey: .trs)
        case let .matrix(matrix):
            try container.encode(matrix.archiveValues, forKey: .matrix)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        if let trs = try container.decodeIfPresent(Transform3D.self, forKey: .trs) {
            self = .trs(trs)
        } else {
            self = .matrix(try float4x4(archiveValues: container.decode([Float].self, forKey: .matrix)))
        }
    }
}

extension float4x4 {
    // Column-major, 16 values (simd matrices are not Codable).
    var archiveValues: [Float] {
        [columns.0, columns.1, columns.2, columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    init(archiveValues values: [Float]) throws {
        guard values.count == 16 else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "A matrix needs 16 values, not \(values.count)"))
        }
        self.init(columns: (SIMD4(values[0 ..< 4]), SIMD4(values[4 ..< 8]), SIMD4(values[8 ..< 12]), SIMD4(values[12 ..< 16])))
    }
}

// MARK: - Content

extension Camera: Codable {
    enum ArchiveKeys: String, CodingKey {
        case projection, verticalAngleOfView, halfHeight, depthMode, near, far, categoryBitMask
    }

    enum ProjectionKind: String, Codable {
        case perspective, orthographic
    }

    enum DepthModeKind: String, Codable {
        case standard, reversed, reversedInfinite
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        // The two projections have separate DepthMode enums with the same cases.
        let depth: (kind: DepthModeKind, near: Float, far: Float?)
        switch projection {
        case let perspective as PerspectiveProjection:
            try container.encode(ProjectionKind.perspective, forKey: .projection)
            try container.encode(perspective.verticalAngleOfView.radians, forKey: .verticalAngleOfView)
            depth = switch perspective.depthMode {
            case let .standard(zClip): (.standard, zClip.lowerBound, zClip.upperBound)
            case let .reversed(zClip): (.reversed, zClip.lowerBound, zClip.upperBound)
            case let .reversedInfinite(zNear): (.reversedInfinite, zNear, nil)
            }
        case let orthographic as OrthographicProjection:
            try container.encode(ProjectionKind.orthographic, forKey: .projection)
            try container.encode(orthographic.halfHeight, forKey: .halfHeight)
            depth = switch orthographic.depthMode {
            case let .standard(zClip): (.standard, zClip.lowerBound, zClip.upperBound)
            case let .reversed(zClip): (.reversed, zClip.lowerBound, zClip.upperBound)
            }
        default:
            throw EncodingError.invalidValue(projection, .init(codingPath: encoder.codingPath, debugDescription: "Unsupported projection \(type(of: projection))"))
        }
        try container.encode(depth.kind, forKey: .depthMode)
        try container.encode(depth.near, forKey: .near)
        try container.encodeIfPresent(depth.far, forKey: .far)
        if categoryBitMask != .max {
            try container.encode(categoryBitMask, forKey: .categoryBitMask)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        let near = try container.decode(Float.self, forKey: .near)
        let kind = try container.decode(DepthModeKind.self, forKey: .depthMode)
        let far = try container.decodeIfPresent(Float.self, forKey: .far) ?? .infinity
        let projection: any ProjectionProtocol
        switch try container.decode(ProjectionKind.self, forKey: .projection) {
        case .perspective:
            let depthMode: PerspectiveProjection.DepthMode = switch kind {
            case .standard: .standard(zClip: near ... far)
            case .reversed: .reversed(zClip: near ... far)
            case .reversedInfinite: .reversedInfinite(zNear: near)
            }
            projection = PerspectiveProjection(verticalAngleOfView: .radians(try container.decode(Float.self, forKey: .verticalAngleOfView)), depthMode: depthMode)
        case .orthographic:
            let depthMode: OrthographicProjection.DepthMode = kind == .standard ? .standard(zClip: near ... far) : .reversed(zClip: near ... far)
            projection = OrthographicProjection(halfHeight: try container.decode(Float.self, forKey: .halfHeight), depthMode: depthMode)
        }
        self.init(projection: projection, categoryBitMask: try container.decodeIfPresent(UInt.self, forKey: .categoryBitMask) ?? .max)
    }
}

// MARK: - Scene settings

extension SceneGraph.Environment: Codable {
    enum ArchiveKeys: String, CodingKey {
        case background, map, mapType, intensity, rotation
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encode(background, forKey: .background)
        try container.encode(intensity, forKey: .intensity)
        try container.encode(rotation, forKey: .rotation)
        guard let map else {
            return
        }
        guard let archivable = map as? any ArchivableEnvironmentMap else {
            try encoder.sceneArchive.warn("Environment map \(type(of: map)) is not archivable; skipped")
            return
        }
        try container.encode(type(of: archivable).archiveTypeName, forKey: .mapType)
        try archivable.encode(to: container.superEncoder(forKey: .map))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        var map: (any EnvironmentMap)?
        if let name = try container.decodeIfPresent(String.self, forKey: .mapType) {
            let context = try decoder.sceneArchive
            if let mapType = context.environmentMapType(named: name) {
                map = try mapType.decodeEnvironmentMap(from: container.superDecoder(forKey: .map))
            } else {
                context.warn("No registered environment map type \"\(name)\"; skipped")
            }
        }
        self.init(background: try container.decode(Background.self, forKey: .background), map: map, intensity: try container.decode(Float.self, forKey: .intensity), rotation: try container.decode(Float.self, forKey: .rotation))
    }
}
