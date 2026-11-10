import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSupport
import SceneSprockets
import SceneSprocketsShaders
import simd
import SwiftMesh

/// A Blinn-Phong surface with ambient, diffuse, specular and emission terms.
///
/// Each term is a color, or a texture tinted by a color. The renderer's ambient light lights the ambient term. If a
/// mesh has vertex colors, the first color set multiplies the ambient, diffuse and opacity terms.
public struct BlinnPhongSceneMaterial: SceneSprockets.Material, SamplesShadowsInShader {
    /// Where a term of the material gets its color.
    public enum Source {
        /// A color in linear RGB.
        case color(SIMD3<Float>)
        /// A texture, sampled at the mesh's first texture coordinates and multiplied by `tint`.
        ///
        /// A `nil` sampler uses linear filtering with repeat. The sampler is a descriptor, not a sampler state, so that
        /// `SceneArchive` can save it.
        case texture(MTLTexture, sampler: MTLSamplerDescriptor? = nil, tint: SIMD3<Float> = .one)

        /// A grey color with the same value in red, green and blue.
        public static func color(_ grey: Float) -> Self {
            .color(SIMD3(repeating: grey))
        }

        /// A color texture loaded from an image file with `MaterialTexture`.
        ///
        /// - Parameters:
        ///   - url: The image file.
        ///   - tint: A color that multiplies the texture.
        /// - Returns: The texture source.
        /// - Throws: An error if the image cannot be loaded.
        public static func texture(contentsOf url: URL, tint: SIMD3<Float> = .one) throws -> Self {
            .texture(try MaterialTexture.load(contentsOf: url), tint: tint)
        }
    }

    /// The color that the ambient light lights.
    public var ambient: Source
    /// The color that the lights scatter in all directions.
    public var diffuse: Source
    /// The color of the highlights.
    public var specular: Source
    /// The specular exponent. Higher values make smaller, sharper highlights.
    public var shininess: Float
    /// The opacity, from 0 (invisible) to 1 (opaque).
    ///
    /// Below 1, the material blends over what is behind it and does not write depth. Transparent meshes draw after
    /// opaque meshes with the same rendering order, farthest first.
    public var opacity: Float
    /// Whether the diffuse texture's alpha multiplies ``opacity``. If true, the material is transparent.
    public var usesDiffuseTextureAlpha: Bool
    /// The color that the material adds without lighting, like `SCNMaterial.emission`.
    public var emission: Source
    /// A tangent-space normal map, with +Y up as in glTF, sampled at the first texture coordinates.
    ///
    /// Meshes do not need tangents.
    public var normalMap: MTLTexture?
    /// The faces to cull. Counter-clockwise triangles are front faces. `.none` draws both sides.
    public var cullMode: MTLCullMode
    /// The depth, color mask, blend and fill settings for the draw.
    public var renderState: MaterialRenderState

    /// Creates a Blinn-Phong material.
    ///
    /// - Parameters:
    ///   - ambient: The color that the ambient light lights.
    ///   - diffuse: The color that the lights scatter in all directions.
    ///   - specular: The color of the highlights.
    ///   - shininess: The specular exponent.
    ///   - opacity: The opacity, from 0 to 1.
    ///   - usesDiffuseTextureAlpha: Whether the diffuse texture's alpha multiplies the opacity.
    ///   - emission: The color that the material adds without lighting.
    ///   - normalMap: A tangent-space normal map.
    ///   - cullMode: The faces to cull.
    ///   - renderState: The depth, color mask, blend and fill settings for the draw.
    public init(ambient: Source, diffuse: Source, specular: Source, shininess: Float, opacity: Float = 1, usesDiffuseTextureAlpha: Bool = false, emission: Source = .color(0), normalMap: MTLTexture? = nil, cullMode: MTLCullMode = .none, renderState: MaterialRenderState = .init()) {
        self.ambient = ambient
        self.diffuse = diffuse
        self.specular = specular
        self.shininess = shininess
        self.opacity = opacity
        self.usesDiffuseTextureAlpha = usesDiffuseTextureAlpha
        self.emission = emission
        self.normalMap = normalMap
        self.cullMode = cullMode
        self.renderState = renderState
    }

    public var isTransparent: Bool {
        opacity < 1 || usesDiffuseTextureAlpha || renderState.blendsWithBackground
    }

    public var appliesNodeOpacity: Bool {
        true
    }
}

/// The renderer that draws every mesh with a ``BlinnPhongSceneMaterial``.
///
/// The renderer draws repeated meshes with automatic instancing. Copies share one cache, so a SwiftUI view can
/// re-create the renderer each update. The type is `Equatable` so that `SceneView` can find an unchanged renderer
/// list.
public struct BlinnPhongMaterialRenderer: SceneGraphMaterialRenderer, Equatable {
    /// The color of the ambient light, in linear RGB. It lights the ambient term of each material.
    public var ambientLightColor: SIMD3<Float>
    // Shared by copies of the renderer, so SwiftUI re-creating the struct keeps the cache.
    private let batchPlans = BatchPlanCache()

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ambientLightColor == rhs.ambientLightColor && lhs.batchPlans === rhs.batchPlans
    }

    /// Creates a Blinn-Phong renderer.
    ///
    /// - Parameter ambientLightColor: The color of the ambient light, in linear RGB.
    public init(ambientLightColor: SIMD3<Float> = [0.15, 0.15, 0.2]) {
        self.ambientLightColor = ambientLightColor
    }

    public var materialType: any SceneSprockets.Material.Type {
        BlinnPhongSceneMaterial.self
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        // The shader works in camera-relative space (#253): the camera is at the origin, and lights and model
        // matrices are shifted by the camera position in Double.
        let lights = blinnPhongLights(context.lights, shadowSlices: context.shadow == nil ? [] : context.lightShadowSlices).map { light in
            var light = light
            light.position = cameraRelative(light.position, to: cameraPosition)
            return light
        }
        let frame = BlinnPhongFrame(viewProjection: context.projectionMatrix * context.viewMatrix.rotationOnlyView, cameraPosition: .zero, ambientLightColor: ambientLightColor, lightCount: Int32(lights.count), materialChannel: context.materialChannel?.rawValue ?? 0)
        // An empty array cannot be bound; the shader reads none of it when lightCount is 0.
        let lightValues = lights.isEmpty ? [BlinnPhongLight()] : lights
        // The shader has no morph or skin inputs, so those meshes are deformed on the CPU. They skip culling because
        // their node bounds do not cover the deformation.
        // SceneGraphElement batches opaque and transparent entries apart, transparent ones sorted farthest first.
        let isTransparent = entries.first?.isTransparent ?? false
        let inFrustum = meshEntriesInFrustum(entries, projectionMatrix: context.projectionMatrix, cameraMatrix: context.cameraMatrix)
        if !isTransparent, let groups = cachedOpaqueGroups(entries: entries, inFrustum: inFrustum, context: context, cameraPosition: cameraPosition) {
            return BlinnPhongBatchesElement(groups: groups, frame: frame, lights: lightValues, shadow: context.shadow, cameraPosition: cameraPosition, isTransparent: false).eraseToAnyElement()
        }
        // One pass, with capacity reserved: this runs every frame over every entry, so copies add up.
        var items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)] = []
        items.reserveCapacity(entries.count)
        var deformed: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)] = []
        for (entry, isInFrustum) in zip(entries, inFrustum) {
            guard let material = entry.material as? BlinnPhongSceneMaterial else {
                continue
            }
            if let result = entry.deformed(revision: context.revision) {
                // Deformed meshes skip culling; their node bounds do not cover the deformation.
                if isTransparent {
                    items.append((entry, result.mesh, result.modelMatrix, material))
                } else {
                    deformed.append((entry, result.mesh, result.modelMatrix, material))
                }
            } else if isInFrustum {
                items.append((entry, entry.mesh, entry.worldTransform, material))
            }
        }
        items += deformed
        let groups: [(key: PipelineKey, single: [InstanceBatch], instanced: [InstanceBatch])]
        if isTransparent {
            // Keep the order: consecutive runs of one vertex layout, with no instancing (it would reorder draws).
            var runs: [(key: PipelineKey, single: [InstanceBatch], instanced: [InstanceBatch])] = []
            for item in items {
                let batch = InstanceBatch(mesh: item.mesh, submeshIndex: item.entry.submeshIndex, material: item.material, receivesShadow: item.entry.receivesShadow, opacity: item.entry.opacity, modelMatrices: [item.modelMatrix])
                let key = PipelineKey(vertexDescriptor: item.mesh.vertexDescriptor, renderState: item.material.renderState)
                if let last = runs.indices.last, runs[last].key == key {
                    runs[last].single.append(batch)
                } else {
                    runs.append((key, [batch], []))
                }
            }
            groups = runs
        } else {
            // Each vertex layout and render state needs its own pipelines; repeated mesh+material pairs draw as one
            // instanced call.
            var grouped: [(key: PipelineKey, items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)])] = []
            for item in items {
                let key = PipelineKey(vertexDescriptor: item.mesh.vertexDescriptor, renderState: item.material.renderState)
                if let index = grouped.firstIndex(where: { $0.key == key }) {
                    grouped[index].items.append(item)
                } else {
                    grouped.append((key, [item]))
                }
            }
            groups = grouped.map { group in
                let batches = instanceBatches(group.items)
                // Single draws go nearest first to reduce overdraw. Instanced batches are one draw call each, so
                // sorting their instances would gain little.
                let single = batches.filter { $0.modelMatrices.count == 1 }
                let distances = single.map { distanceSquared(from: cameraPosition, toOriginOf: $0.modelMatrices[0]) }
                let sortedSingle = single.indices.sorted { distances[$0] < distances[$1] }.map { single[$0] }
                return (key: group.key, single: sortedSingle, instanced: batches.filter { $0.modelMatrices.count > 1 })
            }
        }
        return BlinnPhongBatchesElement(groups: groups, frame: frame, lights: lightValues, shadow: context.shadow, cameraPosition: cameraPosition, isTransparent: isTransparent).eraseToAnyElement()
    }

    // Opaque batching depends on structure, opacity and mirroring, not on where things are, so it is cached and only
    // the model matrices are gathered each frame (#134). Nil (use the full path) when an entry may deform or swap
    // its level of detail, since those change meshes without a structure change.
    // swiftlint:disable:next discouraged_optional_collection - nil is a cache miss
    func cachedOpaqueGroups(entries: [SceneGraph.MeshEntry], inFrustum: [Bool], context: SceneGraphRenderContext, cameraPosition: SIMD3<Float>) -> [(key: PipelineKey, single: [InstanceBatch], instanced: [InstanceBatch])]? {
        var hasher = Hasher()
        hasher.combine(context.revision.structure)
        hasher.combine(entries.count)
        for entry in entries {
            let node = entry.node
            guard node.skin == nil, node.morphTargets.isEmpty, node.levelsOfDetail.isEmpty else {
                return nil
            }
            hasher.combine(ObjectIdentifier(node))
            hasher.combine(entry.submeshIndex)
            hasher.combine(entry.opacity)
            hasher.combine(entry.worldTransform.isMirroring)
        }
        let plan = batchPlans.plan(for: hasher.finalize()) {
            OpaqueBatchPlan(entries: entries)
        }
        return plan.groups.map { group in
            var single: [InstanceBatch] = []
            var instanced: [InstanceBatch] = []
            for planned in group.batches {
                var batch = planned.template
                batch.modelMatrices = planned.entryIndices.compactMap { inFrustum[$0] ? entries[$0].worldTransform : nil }
                switch batch.modelMatrices.count {
                case 0:
                    continue
                case 1:
                    single.append(batch)
                default:
                    instanced.append(batch)
                }
            }
            // Single draws go nearest first to reduce overdraw.
            let distances = single.map { distanceSquared(from: cameraPosition, toOriginOf: $0.modelMatrices[0]) }
            let sortedSingle = single.indices.sorted { distances[$0] < distances[$1] }.map { single[$0] }
            return (key: group.key, single: sortedSingle, instanced: instanced)
        }
    }
}

// Draws prepared batches; an element so it can read the submission index (the shadow map has one texture per frame
// in flight).
private struct BlinnPhongBatchesElement: Element {
    var groups: [(key: PipelineKey, single: [InstanceBatch], instanced: [InstanceBatch])]
    var frame: BlinnPhongFrame
    var lights: [BlinnPhongLight]
    var shadow: SceneGraphShadows.Sampling?
    // World-space camera position; model matrices and shadow lookups are shifted by it.
    var cameraPosition: SIMD3<Float>
    // Blends and does not write depth.
    var isTransparent: Bool

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let frame = frame
            let lightValues = lights
            let shaders = try BlinnPhongShaders.shared()
            let fragmentShader = shadow == nil ? shaders.fragment : shaders.shadowedFragment
            let placeholder = try BlinnPhongShaders.placeholderTexture()
            let defaultSampler = try BlinnPhongShaders.defaultSampler()
            let shadowBinding: (texture: MTLTexture, sampler: MTLSamplerState, uniforms: BlinnPhongShadowUniforms)? = shadow.map { shadow in
                var uniforms = BlinnPhongShadowUniforms()
                uniforms.mapSize = Float(shadow.shadowMap.resolution)
                uniforms.intensity = shadow.intensity
                uniforms.color = shadow.color
                uniforms.radius = Int32(max(shadow.softness, 0))
                withUnsafeMutableBytes(of: &uniforms.sliceViewProjections) { buffer in
                    let slices = buffer.bindMemory(to: simd_float4x4.self)
                    // Both the slices and the shading positions are camera-relative.
                    for (index, matrix) in shadow.shadowMap.lightViewProjectionMatrices.prefix(slices.count).enumerated() {
                        slices[index] = matrix
                    }
                }
                return (shadow.shadowMap.depthTexture(forSubmission: submissionIndex), shadow.shadowMap.sampler, uniforms)
            }

            // Unculled transparent meshes draw back faces first, then front faces. In one pass the faces blend in index
            // order, so back faces can land on top of front faces (#120).
            let isTransparent = isTransparent
            func passes(_ batches: [InstanceBatch]) -> [(batch: InstanceBatch, cullMode: MTLCullMode)] {
                batches.flatMap { batch -> [(batch: InstanceBatch, cullMode: MTLCullMode)] in
                    guard isTransparent, batch.material.cullMode == .none, batch.material.renderState.fillMode == .fill else {
                        return [(batch, batch.material.cullMode)]
                    }
                    return [(batch, .front), (batch, .back)]
                }
            }

            func draw(_ batch: InstanceBatch, cullMode: MTLCullMode, instanced: Bool) -> AnyElement {
                let submesh = batch.mesh.submeshes[batch.submeshIndex]
                let normalMatrices = batch.modelMatrices.map(\.normalMatrix)
                let modelMatrices = batch.modelMatrices.map { $0.cameraRelative(to: cameraPosition) }
                var element = materialDraw(submesh, instanceCount: batch.modelMatrices.count, cullMode: cullMode, isMirrored: batch.isMirrored, fillMode: batch.material.renderState.fillMode)
                .vertexBuffers(batch.mesh.vertexBuffers)
                .parameter("frame", functionType: .vertex, value: frame)
                .eraseToAnyElement()
                if instanced {
                    element = element
                        .parameter("modelMatrices", functionType: .vertex, values: modelMatrices)
                        .parameter("normalMatrices", functionType: .vertex, values: normalMatrices)
                        .eraseToAnyElement()
                } else {
                    element = element
                        .parameter("modelMatrix", functionType: .vertex, value: modelMatrices[0])
                        .parameter("normalMatrix", functionType: .vertex, value: normalMatrices[0])
                        .eraseToAnyElement()
                }
                var resolved = batch.material.resolved(placeholder: placeholder, defaultSampler: defaultSampler)
                resolved.uniforms.receivesShadow = batch.receivesShadow ? 1 : 0
                resolved.uniforms.opacity *= batch.opacity
                element = element
                    .parameter("frame", functionType: .fragment, value: frame)
                    .parameter("lights", functionType: .fragment, values: lightValues)
                    .parameter("material", functionType: .fragment, value: resolved.uniforms)
                    .parameter("ambientTexture", texture: resolved.ambientTexture)
                    .parameter("diffuseTexture", texture: resolved.diffuseTexture)
                    .parameter("specularTexture", texture: resolved.specularTexture)
                    .parameter("emissionTexture", texture: resolved.emissionTexture)
                    .parameter("normalTexture", texture: resolved.normalTexture)
                    .parameter("textureSampler", samplerState: resolved.sampler)
                    .eraseToAnyElement()
                if let shadowBinding {
                    element = element
                        .parameter("shadowMap", texture: shadowBinding.texture)
                        .parameter("shadowSampler", samplerState: shadowBinding.sampler)
                        .parameter("shadow", functionType: .fragment, value: shadowBinding.uniforms)
                        .eraseToAnyElement()
                }
                return element
            }

            return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                let layout = blinnPhongVertexLayout(group.key.vertexDescriptor)
                if !group.single.isEmpty {
                    try RenderPipeline(label: "Blinn-Phong", vertexShader: layout.hasColors ? shaders.coloredVertex : shaders.vertex, fragmentShader: fragmentShader) {
                        ForEach(Array(passes(group.single).enumerated()), id: \.offset) { _, pass in
                            draw(pass.batch, cullMode: pass.cullMode, instanced: false)
                        }
                    }
                    .vertexDescriptor(layout.descriptor)
                    .materialRenderState(group.key.renderState, isTransparent: isTransparent)
                }
                if !group.instanced.isEmpty {
                    try RenderPipeline(label: "Blinn-Phong Instanced", vertexShader: layout.hasColors ? shaders.coloredInstancedVertex : shaders.instancedVertex, fragmentShader: fragmentShader) {
                        ForEach(Array(passes(group.instanced).enumerated()), id: \.offset) { _, pass in
                            draw(pass.batch, cullMode: pass.cullMode, instanced: true)
                        }
                    }
                    .vertexDescriptor(layout.descriptor)
                    .materialRenderState(group.key.renderState, isTransparent: isTransparent)
                }
            }
        }
    }
}

// The mesh's own layout, plus its first color set at attribute 3 when it has one (#246). The shader reads position,
// normal and texture coordinates at attributes 0, 1 and 2.
func blinnPhongVertexLayout(_ vertexDescriptor: VertexDescriptor) -> (descriptor: MTLVertexDescriptor, hasColors: Bool) {
    let descriptor = vertexDescriptor.mtlVertexDescriptor
    guard let color = vertexDescriptor.attributes.first(where: { $0.semantic == .color(0) }) else {
        return (descriptor, false)
    }
    descriptor.attributes[3].format = color.format
    descriptor.attributes[3].offset = color.offset
    descriptor.attributes[3].bufferIndex = color.bufferIndex
    return (descriptor, true)
}

struct PipelineKey: Equatable {
    var vertexDescriptor: VertexDescriptor
    var renderState: MaterialRenderState
}

extension BlinnPhongSceneMaterial {
    struct Resolved {
        var uniforms: BlinnPhongMaterialUniforms
        var ambientTexture: MTLTexture
        var diffuseTexture: MTLTexture
        var specularTexture: MTLTexture
        var emissionTexture: MTLTexture
        var normalTexture: MTLTexture
        var sampler: MTLSamplerState
    }

    // Textures missing from the material are bound as `placeholder`, and flagged off. The first texture's sampler
    // is used for all three.
    func resolved(placeholder: MTLTexture, defaultSampler: MTLSamplerState) -> Resolved {
        func split(_ source: Source) -> (color: SIMD3<Float>, texture: MTLTexture?, sampler: MTLSamplerDescriptor?) {
            switch source {
            case .color(let color):
                (color, nil, nil)
            case let .texture(texture, sampler, tint):
                (tint, texture, sampler)
            }
        }
        let ambient = split(self.ambient)
        let diffuse = split(self.diffuse)
        let specular = split(self.specular)
        let emission = split(self.emission)
        let uniforms = BlinnPhongMaterialUniforms(
            ambient: ambient.color,
            diffuse: diffuse.color,
            specular: specular.color,
            shininess: shininess,
            hasAmbientTexture: ambient.texture == nil ? 0 : 1,
            hasDiffuseTexture: diffuse.texture == nil ? 0 : 1,
            hasSpecularTexture: specular.texture == nil ? 0 : 1,
            receivesShadow: 1,
            opacity: opacity,
            usesDiffuseAlpha: usesDiffuseTextureAlpha ? 1 : 0,
            emission: emission.color,
            hasEmissionTexture: emission.texture == nil ? 0 : 1,
            hasNormalMap: normalMap == nil ? 0 : 1
        )
        let samplerDescriptor = diffuse.sampler ?? ambient.sampler ?? specular.sampler ?? emission.sampler
        let sampler = samplerDescriptor.flatMap { try? BlinnPhongShaders.samplerState(for: $0) } ?? defaultSampler
        return Resolved(uniforms: uniforms, ambientTexture: ambient.texture ?? placeholder, diffuseTexture: diffuse.texture ?? placeholder, specularTexture: specular.texture ?? placeholder, emissionTexture: emission.texture ?? placeholder, normalTexture: normalMap ?? placeholder, sampler: sampler)
    }
}

struct InstanceBatch {
    var mesh: MetalMesh
    var submeshIndex: Int
    var material: BlinnPhongSceneMaterial
    var receivesShadow: Bool
    // The node's inherited opacity; multiplies the material's.
    var opacity: Float = 1
    var modelMatrices: [simd_float4x4]

    // Batches never mix mirrored and unmirrored transforms, so the first one decides the winding.
    var isMirrored: Bool {
        modelMatrices[0].isMirroring
    }
}

// Which entries draw together, by pipeline and instance batch. Batches have no model matrices; those are gathered
// per frame.
struct OpaqueBatchPlan {
    struct Batch {
        var template: InstanceBatch
        var entryIndices: [Int]
    }

    var groups: [(key: PipelineKey, batches: [Batch])] = []

    init(entries: [SceneGraph.MeshEntry]) {
        var grouped: [(key: PipelineKey, items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)], entryIndices: [Int])] = []
        for (index, entry) in entries.enumerated() {
            guard let material = entry.material as? BlinnPhongSceneMaterial else {
                continue
            }
            let item = (entry: entry, mesh: entry.mesh, modelMatrix: entry.worldTransform, material: material)
            let key = PipelineKey(vertexDescriptor: entry.mesh.vertexDescriptor, renderState: material.renderState)
            if let groupIndex = grouped.firstIndex(where: { $0.key == key }) {
                grouped[groupIndex].items.append(item)
                grouped[groupIndex].entryIndices.append(index)
            } else {
                grouped.append((key, [item], [index]))
            }
        }
        groups = grouped.map { group in
            let batches = instanceBatchMembers(group.items).map { batch, members in
                var template = batch
                template.modelMatrices = []
                return Batch(template: template, entryIndices: members.map { group.entryIndices[$0] })
            }
            return (group.key, batches)
        }
    }
}

final class BatchPlanCache: @unchecked Sendable {
    private let lock = NSLock()
    private var plans: [Int: OpaqueBatchPlan] = [:]

    func plan(for signature: Int, make: () -> OpaqueBatchPlan) -> OpaqueBatchPlan {
        lock.lock()
        defer { lock.unlock() }
        if let plan = plans[signature] {
            return plan
        }
        let plan = make()
        // A scene asks for a few plans per frame (one per render batch); a full cache means the scene changed.
        if plans.count >= 16 {
            plans.removeAll()
        }
        plans[signature] = plan
        return plan
    }
}

// Groups items that share vertex buffers, submesh and material, keeping first-seen order.
func instanceBatches(_ items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)]) -> [InstanceBatch] {
    instanceBatchMembers(items).map(\.batch)
}

// Like instanceBatches, with the indices into `items` of each batch's members.
func instanceBatchMembers(_ items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)]) -> [(batch: InstanceBatch, members: [Int])] {
    // Built for every item every frame, so it avoids allocating: the first two vertex buffers (by buffer index) are
    // stored inline, any others in an array.
    struct Key: Hashable {
        var firstBuffer: ObjectIdentifier?
        var secondBuffer: ObjectIdentifier?
        var otherBuffers: [ObjectIdentifier]
        var submeshIndex: Int
        var material: MaterialKey
        var receivesShadow: Bool
        var isMirrored: Bool
        var opacity: Float
    }
    var batches: [(batch: InstanceBatch, members: [Int])] = []
    var indexByKey: [Key: Int] = [:]
    for (itemIndex, item) in items.enumerated() {
        let buffers = vertexBufferIdentifiers(item.mesh)
        let key = Key(firstBuffer: buffers.first, secondBuffer: buffers.second, otherBuffers: buffers.others, submeshIndex: item.entry.submeshIndex, material: MaterialKey(item.material), receivesShadow: item.entry.receivesShadow, isMirrored: item.modelMatrix.isMirroring, opacity: item.entry.opacity)
        if let index = indexByKey[key] {
            batches[index].batch.modelMatrices.append(item.modelMatrix)
            batches[index].members.append(itemIndex)
        } else {
            indexByKey[key] = batches.count
            batches.append((InstanceBatch(mesh: item.mesh, submeshIndex: item.entry.submeshIndex, material: item.material, receivesShadow: item.entry.receivesShadow, opacity: item.entry.opacity, modelMatrices: [item.modelMatrix]), [itemIndex]))
        }
    }
    return batches
}

private func vertexBufferIdentifiers(_ mesh: MetalMesh) -> (first: ObjectIdentifier?, second: ObjectIdentifier?, others: [ObjectIdentifier]) {
    let buffers = mesh.vertexBuffers
    switch buffers.count {
    case 0:
        return (nil, nil, [])
    case 1:
        return (buffers.first.map { ObjectIdentifier($0.value) }, nil, [])
    case 2:
        var iterator = buffers.makeIterator()
        guard let a = iterator.next(), let b = iterator.next() else {
            return (nil, nil, [])
        }
        let (low, high) = a.key < b.key ? (a, b) : (b, a)
        return (ObjectIdentifier(low.value), ObjectIdentifier(high.value), [])
    default:
        let sorted = buffers.sorted { $0.key < $1.key }.map { ObjectIdentifier($0.value) }
        return (sorted[0], sorted[1], Array(sorted.dropFirst(2)))
    }
}

// Materials hold textures, so they are not Hashable; compare colors by value and textures by identity.
private struct MaterialKey: Hashable {
    var ambient: SourceKey
    var diffuse: SourceKey
    var specular: SourceKey
    var emission: SourceKey
    var shininess: Float
    var opacity: Float
    var usesDiffuseTextureAlpha: Bool
    var normalMap: ObjectIdentifier?
    var cullMode: UInt
    var renderState: MaterialRenderState

    init(_ material: BlinnPhongSceneMaterial) {
        ambient = SourceKey(material.ambient)
        diffuse = SourceKey(material.diffuse)
        specular = SourceKey(material.specular)
        emission = SourceKey(material.emission)
        shininess = material.shininess
        opacity = material.opacity
        usesDiffuseTextureAlpha = material.usesDiffuseTextureAlpha
        normalMap = material.normalMap.map { ObjectIdentifier($0) }
        cullMode = material.cullMode.rawValue
        renderState = material.renderState
    }

    enum SourceKey: Hashable {
        case color(SIMD3<Float>)
        case texture(ObjectIdentifier, sampler: ObjectIdentifier?, tint: SIMD3<Float>)

        init(_ source: BlinnPhongSceneMaterial.Source) {
            switch source {
            case .color(let color):
                self = .color(color)
            case let .texture(texture, sampler, tint):
                self = .texture(ObjectIdentifier(texture), sampler: sampler.map { ObjectIdentifier($0) }, tint: tint)
            }
        }
    }
}

// Lights point down their node's -Z axis. `shadowSlices` is parallel to `lights` (empty: no shadows).
func blinnPhongLights(_ lights: [(worldTransform: simd_float4x4, light: Light)], shadowSlices: [Range<Int>] = []) -> [BlinnPhongLight] {
    lights.enumerated().map { index, entry in
        let slices = index < shadowSlices.count ? shadowSlices[index] : 0..<0
        let transform = entry.worldTransform
        let forward = -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        let type: Int32 = switch entry.light.type {
        case .directional: Int32(BLINN_PHONG_LIGHT_DIRECTIONAL)
        case .spot: Int32(BLINN_PHONG_LIGHT_SPOT)
        case .point: Int32(BLINN_PHONG_LIGHT_POINT)
        }
        return BlinnPhongLight(
            position: transform.columns.3.xyz,
            direction: simd_length(forward) > 0 ? simd_normalize(forward) : [0, 0, -1],
            color: entry.light.color * entry.light.intensity,
            type: type,
            range: entry.light.range,
            innerConeCos: cos(entry.light.innerConeAngle),
            outerConeCos: cos(entry.light.outerConeAngle),
            shadowSliceStart: Int32(slices.lowerBound),
            shadowSliceCount: Int32(slices.count)
        )
    }
}

// From BlinnPhong.metal in SceneSprocketsShaders, loaded once.
struct BlinnPhongShaders {
    var vertex: VertexShader
    var instancedVertex: VertexShader
    var coloredVertex: VertexShader
    var coloredInstancedVertex: VertexShader
    var fragment: FragmentShader
    var shadowedFragment: FragmentShader

    nonisolated(unsafe) private static var cached: Self?
    nonisolated(unsafe) private static var cachedPlaceholder: MTLTexture?
    nonisolated(unsafe) private static var cachedSampler: MTLSamplerState?
    // By descriptor identity, so a material's sampler state is made once.
    nonisolated(unsafe) private static var samplerStates: [ObjectIdentifier: (descriptor: MTLSamplerDescriptor, state: MTLSamplerState)] = [:]
    private static let lock = NSLock()

    static func shared() throws -> Self {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("BlinnPhong")
        func fragment(shadows: Bool) throws -> FragmentShader {
            var constants = FunctionConstants()
            constants["HAS_SHADOWS"] = .bool(shadows)
            return try library.function(named: "fragment_main", type: FragmentShader.self, constants: constants)
        }
        func vertex(_ name: String, colors: Bool) throws -> VertexShader {
            var constants = FunctionConstants()
            constants["HAS_VERTEX_COLORS"] = .bool(colors)
            return try library.function(named: name, type: VertexShader.self, constants: constants)
        }
        let shaders = Self(
            vertex: try vertex("vertex_main", colors: false),
            instancedVertex: try vertex("vertex_instanced", colors: false),
            coloredVertex: try vertex("vertex_main", colors: true),
            coloredInstancedVertex: try vertex("vertex_instanced", colors: true),
            fragment: try fragment(shadows: false),
            shadowedFragment: try fragment(shadows: true)
        )
        cached = shaders
        return shaders
    }

    // 1x1 white, bound where a material has no texture.
    static func placeholderTexture() throws -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPlaceholder {
            return cachedPlaceholder
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = _MTLCreateSystemDefaultDevice().makeTexture(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create Blinn-Phong placeholder texture")
        }
        texture.label = "Blinn-Phong Placeholder"
        texture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8](repeating: 255, count: 4), bytesPerRow: 4)
        cachedPlaceholder = texture
        return texture
    }

    static func samplerState(for descriptor: MTLSamplerDescriptor) throws -> MTLSamplerState {
        lock.lock()
        defer { lock.unlock() }
        if let cached = samplerStates[ObjectIdentifier(descriptor)] {
            return cached.state
        }
        guard let state = _MTLCreateSystemDefaultDevice().makeSamplerState(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create Blinn-Phong sampler")
        }
        // The descriptor is kept so its identifier is not reused.
        samplerStates[ObjectIdentifier(descriptor)] = (descriptor, state)
        return state
    }

    static func defaultSampler() throws -> MTLSamplerState {
        lock.lock()
        defer { lock.unlock() }
        if let cachedSampler {
            return cachedSampler
        }
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        guard let sampler = _MTLCreateSystemDefaultDevice().makeSamplerState(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create Blinn-Phong sampler")
        }
        cachedSampler = sampler
        return sampler
    }
}

/// Renders a scene graph's Blinn-Phong meshes. Shorthand for `SceneGraphElement` with a `BlinnPhongMaterialRenderer`.
///
/// ```swift
/// RenderView { context, size in
///     BlinnPhongSceneGraphElement(
///         sceneGraph: sceneGraph,
///         cameraMatrix: cameraMatrix,
///         aspectRatio: Float(size.width / size.height)
///     )
/// }
/// ```
public struct BlinnPhongSceneGraphElement: Element {
    var sceneGraph: SceneGraph
    var camera: SceneGraph.Node?
    var cameraMatrix: simd_float4x4?
    var aspectRatio: Float
    var ambientLightColor: SIMD3<Float>

    /// Creates an element that draws a scene with only the Blinn-Phong renderer.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene to draw.
    ///   - camera: The camera node. If `nil`, the element uses the first camera node.
    ///   - cameraMatrix: A world transform that replaces the camera node's transform.
    ///   - aspectRatio: The width of the view divided by its height.
    ///   - ambientLightColor: The color of the ambient light, in linear RGB.
    public init(
        sceneGraph: SceneGraph,
        camera: SceneGraph.Node? = nil,
        cameraMatrix: simd_float4x4? = nil,
        aspectRatio: Float,
        ambientLightColor: SIMD3<Float> = [0.15, 0.15, 0.2]
    ) {
        self.sceneGraph = sceneGraph
        self.camera = camera
        self.cameraMatrix = cameraMatrix
        self.aspectRatio = aspectRatio
        self.ambientLightColor = ambientLightColor
    }

    public var body: some Element {
        SceneGraphElement(
            sceneGraph: sceneGraph,
            camera: camera,
            cameraMatrix: cameraMatrix,
            aspectRatio: aspectRatio,
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: ambientLightColor)]
        )
    }
}
