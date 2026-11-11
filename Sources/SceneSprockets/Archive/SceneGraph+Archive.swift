import Foundation
import GeometryLite3D
import SceneSprocketsAudio
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
        try encoder.sceneArchive.encodingRoot = root
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
        try decoder.sceneArchive.resolveConstraints(root: root)
        try decoder.sceneArchive.resolveSkins(root: root)
        environment = try container.decode(Environment.self, forKey: .environment)
        fog = try container.decodeIfPresent(Fog.self, forKey: .fog)
        postProcessing = try container.decodeIfPresent(PostProcessing.self, forKey: .postProcessing)
    }
}

// MARK: - Nodes

extension SceneGraph.Node: Codable {
    enum ArchiveKeys: String, CodingKey {
        case label, transform, pivot, isVisible, isActive, opacity, categoryBitMask, lightCategoryBitMask, renderingOrder
        case subdivisionLevel, actionSpeed, mesh, light, camera, constraints, children, model
        case morphTargets, morphWeights, skin, skinVertices, physicsBody, particleSystems, levelsOfDetail, audioPlayers
    }

    enum MeshKeys: String, CodingKey {
        /// A mesh is a `shape`, or a `file` written by the archive's mesh codec (#158).
        case shape, file, materials, castsShadow, receivesShadow
    }

    enum MaterialKeys: String, CodingKey {
        case type, value
    }

    public func encode(to encoder: Encoder) throws {
        let context = try encoder.sceneArchive
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encode(ArchivedTransform(transform), forKey: .transform)
        if pivot != .identity {
            try container.encode(pivot.archiveValues, forKey: .pivot)
        }
        if !isVisible {
            try container.encode(isVisible, forKey: .isVisible)
        }
        if !isActive {
            try container.encode(isActive, forKey: .isActive)
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
        // A loaded model: its file stands for the node's content and subtree (#157).
        if let modelSource, context.modelLoader != nil {
            try container.encode(context.addModel(modelSource), forKey: .model)
            return
        }
        switch content {
        case .empty:
            break
        case let .light(light):
            try container.encode(light, forKey: .light)
        case let .camera(camera):
            try container.encode(camera, forKey: .camera)
        case let .mesh(metalMesh, materials, castsShadow, receivesShadow):
            if shape == nil, context.meshCodec == nil {
                context.warn("\(nodeDescription): mesh is not a shape and the archive has no mesh codec; not saved (#158)")
            } else {
                var mesh = container.nestedContainer(keyedBy: MeshKeys.self, forKey: .mesh)
                if let shape {
                    try mesh.encode(shape, forKey: .shape)
                } else if let codec = context.meshCodec {
                    if metalMesh.morphTargets != nil || metalMesh.skin != nil {
                        context.warn("\(nodeDescription): the mesh's morph targets and skin are not saved")
                    }
                    // Nodes that share a mesh share its file.
                    try mesh.encode(context.meshFile(for: metalMesh, materials: materials, name: label, codec: codec), forKey: .file)
                }
                try mesh.encode(castsShadow, forKey: .castsShadow)
                try mesh.encode(receivesShadow, forKey: .receivesShadow)
                var list = mesh.nestedUnkeyedContainer(forKey: .materials)
                for material in materials {
                    guard let archivable = material as? any ArchivableMaterial else {
                        context.warn("\(nodeDescription): \(type(of: material)) is not archivable; skipped")
                        continue
                    }
                    if let problem = archivable.archiveProblem(context: context) {
                        context.warn("\(nodeDescription): \(problem); skipped")
                        continue
                    }
                    var item = list.nestedContainer(keyedBy: MaterialKeys.self)
                    try item.encode(type(of: archivable).archiveTypeName, forKey: .type)
                    try archivable.encode(to: item.superEncoder(forKey: .value))
                }
            }
        }
        warnAboutUnsavedFeatures(context)
        try encodeConstraints(into: &container, context: context)
        try encodeNodeFeatures(into: &container, context: context)
        if !children.isEmpty {
            try container.encode(children, forKey: .children)
        }
    }

    // Called from init(from:), which has to be in the class declaration.
    func decodeArchive(from decoder: Decoder) throws {
        let context = try decoder.sceneArchive
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        transform = try container.decode(ArchivedTransform.self, forKey: .transform).transform
        if let values = try container.decodeIfPresent([Float].self, forKey: .pivot) {
            pivot = try float4x4(archiveValues: values)
        }
        isVisible = try container.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        opacity = try container.decodeIfPresent(Float.self, forKey: .opacity) ?? 1
        categoryBitMask = try container.decodeIfPresent(UInt.self, forKey: .categoryBitMask) ?? 1
        lightCategoryBitMask = try container.decodeIfPresent(UInt.self, forKey: .lightCategoryBitMask) ?? .max
        renderingOrder = try container.decodeIfPresent(Int.self, forKey: .renderingOrder) ?? 0
        actionSpeed = try container.decodeIfPresent(Float.self, forKey: .actionSpeed) ?? 1
        if let path = try container.decodeIfPresent(String.self, forKey: .model) {
            guard let loader = context.modelLoader else {
                context.warn("\(label ?? "node"): no model loader to read \(path); model dropped")
                return
            }
            let loaded = try loader.load(context.url(forPath: path), context: context)
            for warning in loaded.warnings {
                context.warn("\(label ?? "node"): \(warning)")
            }
            content = loaded.node.content
            for child in loaded.node.children {
                addChild(child)
            }
            modelSource = try context.modelSource(atPath: path)
            return
        }
        if let light = try container.decodeIfPresent(Light.self, forKey: .light) {
            content = .light(light)
        } else if let camera = try container.decodeIfPresent(Camera.self, forKey: .camera) {
            content = .camera(camera)
        } else if container.contains(.mesh) {
            let mesh = try container.nestedContainer(keyedBy: MeshKeys.self, forKey: .mesh)
            let shape = try mesh.decodeIfPresent(SceneGraph.Shape.self, forKey: .shape)
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
                let castsShadow = try mesh.decode(Bool.self, forKey: .castsShadow)
                let receivesShadow = try mesh.decode(Bool.self, forKey: .receivesShadow)
                if let shape {
                    content = .mesh(shape.metalMesh(), materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
                    shapeStorage = shape
                } else if let path = try mesh.decodeIfPresent(String.self, forKey: .file) {
                    if let codec = context.meshCodec {
                        // Nodes that shared a mesh share it again.
                        content = .mesh(try context.mesh(atPath: path, codec: codec), materials: materials, castsShadow: castsShadow, receivesShadow: receivesShadow)
                    } else {
                        context.warn("\(label ?? "node"): no mesh codec to read \(path); mesh dropped")
                    }
                }
            }
        }
        if let constraints = try container.decodeIfPresent([ArchivedConstraint].self, forKey: .constraints) {
            context.pendingConstraints.append((self, constraints))
        }
        morphTargets = try container.decodeIfPresent([SceneGraph.MorphTarget].self, forKey: .morphTargets) ?? []
        morphWeights = try container.decodeIfPresent([Float].self, forKey: .morphWeights) ?? []
        if let skin = try container.decodeIfPresent(ArchivedSkin.self, forKey: .skin) {
            context.pendingSkins.append((self, skin))
        }
        skinVertices = try container.decodeIfPresent([SceneGraph.SkinVertex].self, forKey: .skinVertices) ?? []
        physicsBody = try container.decodeIfPresent(SceneGraph.PhysicsBody.self, forKey: .physicsBody)
        particleSystems = try (container.decodeIfPresent([ArchivedParticleSystem].self, forKey: .particleSystems) ?? []).map {
            let system = SceneParticleSystem($0.system, seed: $0.seed)
            system.usesNodeTransform = $0.usesNodeTransform ?? true
            return system
        }
        if let levels = try container.decodeIfPresent([ArchivedLevelOfDetail].self, forKey: .levelsOfDetail) {
            levelsOfDetail = try decodeLevelsOfDetail(levels, context: context)
        }
        audioPlayers = try (container.decodeIfPresent([ArchivedAudioPlayer].self, forKey: .audioPlayers) ?? []).map {
            try AudioPlayer(url: context.url(forPath: $0.file), loops: $0.loops, volume: $0.volume)
        }
        // After the content, so subdivision applies to the shape's mesh.
        subdivisionLevel = try container.decodeIfPresent(Int.self, forKey: .subdivisionLevel) ?? 0
        for child in try container.decodeIfPresent([SceneGraph.Node].self, forKey: .children) ?? [] {
            addChild(child)
        }
    }

    private func encodeConstraints(into container: inout KeyedEncodingContainer<ArchiveKeys>, context: SceneArchiveContext) throws {
        guard !constraints.isEmpty else {
            return
        }
        var root = self
        while let parent = root.parent {
            root = parent
        }
        root = context.encodingRoot ?? root
        var archived: [ArchivedConstraint] = []
        for constraint in constraints {
            if let item = ArchivedConstraint(constraint, root: root) {
                archived.append(item)
            } else if case .transform = constraint.kind {
                context.warn("\(nodeDescription): transform constraints are closures and cannot be saved; skipped")
            } else {
                context.warn("\(nodeDescription): constraint refers to a node outside the scene; skipped")
            }
        }
        if !archived.isEmpty {
            try container.encode(archived, forKey: .constraints)
        }
    }

    private func encodeNodeFeatures(into container: inout KeyedEncodingContainer<ArchiveKeys>, context: SceneArchiveContext) throws {
        if !morphTargets.isEmpty {
            try container.encode(morphTargets, forKey: .morphTargets)
        }
        if !morphWeights.isEmpty {
            try container.encode(morphWeights, forKey: .morphWeights)
        }
        if let skin {
            let root = context.encodingRoot ?? self
            let paths = skin.joints.map { $0.archivePath(from: root) }
            if paths.contains(where: { $0 == nil }) {
                context.warn("\(nodeDescription): skin joint outside the scene; skin skipped")
            } else {
                try container.encode(ArchivedSkin(joints: paths.compactMap(\.self), inverseBindMatrices: skin.inverseBindMatrices.map(\.archiveValues)), forKey: .skin)
            }
        }
        if !skinVertices.isEmpty {
            try container.encode(skinVertices, forKey: .skinVertices)
        }
        try container.encodeIfPresent(physicsBody, forKey: .physicsBody)
        if !particleSystems.isEmpty {
            let archived = particleSystems.map {
                ArchivedParticleSystem(system: $0.system, seed: $0.seed, usesNodeTransform: $0.usesNodeTransform ? nil : false)
            }
            try container.encode(archived, forKey: .particleSystems)
        }
        try encodeLevelsOfDetail(into: &container, context: context)
        if !audioPlayers.isEmpty {
            let archived = try audioPlayers.map {
                ArchivedAudioPlayer(file: try context.audioFile(for: $0.buffer), loops: $0.loops, volume: $0.volume)
            }
            try container.encode(archived, forKey: .audioPlayers)
        }
    }

    private func encodeLevelsOfDetail(into container: inout KeyedEncodingContainer<ArchiveKeys>, context: SceneArchiveContext) throws {
        guard !levelsOfDetail.isEmpty else {
            return
        }
        guard let codec = context.meshCodec else {
            context.warn("\(nodeDescription): the archive has no mesh codec; levels of detail not saved")
            return
        }
        let materials: [any Material] = if case let .mesh(_, materials, _, _) = content { materials } else { [] }
        let archived = try levelsOfDetail.map { level in
            ArchivedLevelOfDetail(file: try level.mesh.map { try context.meshFile(for: $0, materials: materials, name: label, codec: codec) }, distance: level.distance)
        }
        try container.encode(archived, forKey: .levelsOfDetail)
    }

    private func decodeLevelsOfDetail(_ levels: [ArchivedLevelOfDetail], context: SceneArchiveContext) throws -> [SceneGraph.LevelOfDetail] {
        guard let codec = context.meshCodec else {
            if levels.contains(where: { $0.file != nil }) {
                context.warn("\(label ?? "node"): no mesh codec to read levels of detail; dropped")
                return []
            }
            return levels.map { SceneGraph.LevelOfDetail(mesh: nil, distance: $0.distance) }
        }
        return try levels.map { level in
            SceneGraph.LevelOfDetail(mesh: try level.file.map { try context.mesh(atPath: $0, codec: codec) }, distance: level.distance)
        }
    }

    private var nodeDescription: String {
        label.map { "\"\($0)\"" } ?? "unnamed node"
    }

    // Later steps of #52.
    private func warnAboutUnsavedFeatures(_ context: SceneArchiveContext) {
        let unsaved: [(String, Bool)] = [
            ("running actions", !runningActions.isEmpty)
        ]
        for (feature, isPresent) in unsaved where isPresent {
            context.warn("\(nodeDescription): \(feature) not saved yet")
        }
    }
}

// A node's transform in an archive: {"trs": translation, rotation, scale} or {"matrix": 16 floats}. The format predates
// Transform3D's matrix storage, so old and new archives read the same way.
struct ArchivedTransform: Codable {
    var transform: Transform3D

    init(_ transform: Transform3D) {
        self.transform = transform
    }

    enum ArchiveKeys: String, CodingKey {
        case trs, matrix
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: ArchiveKeys.self)
        switch transform.storage {
        case .components:
            try container.encode(transform, forKey: .trs)
        case let .matrix(matrix):
            try container.encode(matrix.archiveValues, forKey: .matrix)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: ArchiveKeys.self)
        if let trs = try container.decodeIfPresent(Transform3D.self, forKey: .trs) {
            transform = trs
        } else {
            transform = Transform3D(storing: try float4x4(archiveValues: container.decode([Float].self, forKey: .matrix)))
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
