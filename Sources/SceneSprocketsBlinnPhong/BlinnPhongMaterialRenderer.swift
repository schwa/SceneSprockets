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
public struct BlinnPhongSceneMaterial: SceneMaterial, SamplesShadowsInShader, DrawsDeformedVertices {
    /// Where a term of the material gets its color.
    public enum Source {
        /// A color in linear RGB.
        case color(SIMD3<Float>)
        /// A texture, sampled at the mesh's first texture coordinates and multiplied by `tint`.
        ///
        /// A `nil` sampler uses linear filtering with repeat. The sampler is a descriptor, not a sampler state, so that
        /// `Archive` can save it.
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
    /// A `.texture` source is decoded from 0...1 to -1...1 and then multiplied by its tint, so a tint of `[s, s, 1]`
    /// scales the bumps by `s`. A `.color` source is one tangent-space normal for the whole surface. Meshes do not need
    /// tangents.
    public var normalMap: Source?
    /// A height map for parallax occlusion mapping, sampled at the first texture coordinates: the surface appears to
    /// have depth without extra geometry (#537). Heights are the red channel times the tint's x, 1 at the surface and 0
    /// at ``parallaxDepth`` below it. A `.color` source has no effect.
    public var heightMap: Source?
    /// How deep the lowest point of ``heightMap`` appears, in texture-coordinate units (0.05 is 5% of the texture's
    /// width).
    public var parallaxDepth: Float = 0.05
    /// The depth, color mask, blend, fill and cull settings for the draw. Counter-clockwise triangles are front faces.
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
    ///   - renderState: The depth, color mask, blend, fill and cull settings for the draw.
    public init(ambient: Source, diffuse: Source, specular: Source, shininess: Float, opacity: Float = 1, usesDiffuseTextureAlpha: Bool = false, emission: Source = .color(0), normalMap: Source? = nil, renderState: MaterialRenderState = .init()) {
        self.ambient = ambient
        self.diffuse = diffuse
        self.specular = specular
        self.shininess = shininess
        self.opacity = opacity
        self.usesDiffuseTextureAlpha = usesDiffuseTextureAlpha
        self.emission = emission
        self.normalMap = normalMap
        self.renderState = renderState
    }

    /// Creates a Blinn-Phong material from one color.
    ///
    /// The ambient color is 30% of `color` and the highlights are a 50% gray.
    ///
    /// - Parameters:
    ///   - color: The diffuse color, in linear RGB.
    ///   - shininess: The specular exponent.
    ///   - opacity: The opacity, from 0 to 1.
    ///   - emission: The color that the material adds without lighting.
    public init(color: SIMD3<Float>, shininess: Float = 32, opacity: Float = 1, emission: SIMD3<Float> = .zero) {
        self.init(ambient: .color(color * 0.3), diffuse: .color(color), specular: .color(0.5), shininess: shininess, opacity: opacity, emission: .color(emission))
    }

    public var isTransparent: Bool {
        // Stochastic transparency draws with the opaque meshes (#539).
        (opacity < 1 || usesDiffuseTextureAlpha) && renderState.blendMode != .stochastic || renderState.blendsWithBackground
    }

    public var appliesNodeOpacity: Bool {
        true
    }
}

/// The renderer that draws every mesh with a ``BlinnPhongSceneMaterial``.
///
/// The renderer draws repeated meshes with automatic instancing. Renderers with the same settings are equal, so a
/// `SceneView` made again with a new renderer, for example `renderers: [BlinnPhongMaterialRenderer()]` in a view body,
/// compares equal and keeps drawing with the renderer it has.
public struct BlinnPhongMaterialRenderer: MaterialRenderer, Equatable {
    /// The color of the ambient light, in linear RGB. It lights the ambient term of each material.
    public var ambientLightColor: SIMD3<Float>
    // Shared by copies of the renderer.
    private let batchPlans = BatchPlanCache()
    private let materialResources = MaterialResourcesCache()

    // The cache is not compared: it does not change what the renderer draws (#487).
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.ambientLightColor == rhs.ambientLightColor
    }

    /// Creates a Blinn-Phong renderer.
    ///
    /// - Parameter ambientLightColor: The color of the ambient light, in linear RGB.
    public init(ambientLightColor: SIMD3<Float> = [0.15, 0.15, 0.2]) {
        self.ambientLightColor = ambientLightColor
    }

    public var materialType: any SceneMaterial.Type {
        BlinnPhongSceneMaterial.self
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func makeElement(entries: [SceneGraph.MeshEntry], context: RenderContext) throws -> AnyElement {
        // The shader works in camera-relative space (#253): the camera is at the origin, and lights and model
        // matrices are shifted by the camera position in Double.
        let shading = BlinnPhongShading(context: context, ambientLightColor: ambientLightColor)
        let cameraPosition = shading.cameraPosition
        // The shader has no morph or skin inputs, so SceneGraphElement deforms those meshes in a GPU pre-pass (#298).
        // SceneGraphElement batches opaque and transparent entries apart, transparent ones sorted farthest first.
        let isTransparent = entries.first?.isTransparent ?? false
        let inFrustum = meshEntriesInFrustum(entries, projectionMatrix: context.projectionMatrix, cameraMatrix: context.cameraMatrix, stereoViews: context.stereoViews)
        if !isTransparent, let groups = cachedOpaqueGroups(entries: entries, inFrustum: inFrustum, context: context, cameraPosition: cameraPosition) {
            return BlinnPhongBatchesElement(groups: groups, shading: shading, ambientOcclusion: context.ambientOcclusion, isTransparent: false, stereoViews: context.stereoViews, materialResources: materialResources).eraseToAnyElement()
        }
        // One pass, with capacity reserved: this runs every frame over every entry, so copies add up.
        var items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)] = []
        items.reserveCapacity(entries.count)
        // SceneGraphElement has already swapped skinned and morphed meshes for their deformed vertices, with bounds that
        // cover the deformation (#590).
        for (entry, isInFrustum) in zip(entries, inFrustum) where isInFrustum {
            guard let material = entry.material as? BlinnPhongSceneMaterial else {
                continue
            }
            items.append((entry, entry.mesh, entry.worldTransform, material))
        }
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
        return BlinnPhongBatchesElement(groups: groups, shading: shading, ambientOcclusion: context.ambientOcclusion, isTransparent: isTransparent, stereoViews: context.stereoViews, materialResources: materialResources).eraseToAnyElement()
    }

    // Opaque batching depends on structure, opacity and mirroring, not on where things are, so it is cached and only
    // the model matrices are gathered each frame (#134). Nil (use the full path) when an entry may deform or swap
    // its level of detail, since those change meshes without a structure change.
    // swiftlint:disable:next discouraged_optional_collection - nil is a cache miss
    func cachedOpaqueGroups(entries: [SceneGraph.MeshEntry], inFrustum: [Bool], context: RenderContext, cameraPosition: SIMD3<Float>) -> [(key: PipelineKey, single: [InstanceBatch], instanced: [InstanceBatch])]? {
        var hasher = Hasher()
        hasher.combine(context.revision.structure)
        hasher.combine(entries.count)
        for entry in entries {
            // Deformed meshes change buffers every frame.
            guard entry.skin == nil, entry.skinVertices.isEmpty, entry.morphTargets.isEmpty, entry.levelsOfDetail.isEmpty else {
                return nil
            }
            hasher.combine(entry.nodeID)
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
    // Its camera position shifts model matrices and shadow lookups.
    var shading: BlinnPhongShading
    var ambientOcclusion: MTLTexture?
    // Blends and does not write depth.
    var isTransparent: Bool
    var stereoViews: StereoViews?
    var materialResources: MaterialResourcesCache

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let frame = shading.frame
            let lightValues = shading.lights
            let cameraPosition = shading.cameraPosition
            let shaders = try BlinnPhongShaders.shared()
            let fragmentShader = shading.shadow == nil ? shaders.fragment : shaders.shadowedFragment
            let placeholder = try BlinnPhongShaders.placeholderTexture()
            let defaultSampler = try BlinnPhongShaders.defaultSampler()
            let shadowBinding = shading.shadowBinding(submissionIndex: submissionIndex)
            let clusterBinding = try shading.lightClusterBinding(device: placeholder.device)
            let materialResources = materialResources
            // One per frame, shared by every draw: the shadow map (a placeholder when off) and ambient occlusion.
            let shadowPlaceholder = try BlinnPhongShaders.shadowPlaceholder()
            let frameResources = ArgumentBuffer(device: placeholder.device, label: "Blinn-Phong Frame Resources")
            frameResources.set("shadowMap", texture: shadowBinding?.texture ?? shadowPlaceholder.map)
            frameResources.set("shadowSampler", samplerState: shadowBinding?.sampler ?? shadowPlaceholder.sampler)
            frameResources.set("ambientOcclusion", texture: ambientOcclusion ?? placeholder)

            // Unculled transparent meshes draw back faces first, then front faces. In one pass the faces blend in index
            // order, so back faces can land on top of front faces (#120).
            let isTransparent = isTransparent
            // A faded mesh (node opacity on an otherwise opaque material) blends as one surface: a depth-only draw,
            // then color only where its nearest face is (#327).
            func isFaded(_ batch: InstanceBatch) -> Bool {
                let state = batch.material.renderState
                return isTransparent && !batch.material.isTransparent && state.fillMode == .fill && state.readsFromDepthBuffer && state.writesToDepthBuffer
            }
            // Consecutive batches that are all faded or all not, in draw order.
            func runs(_ batches: [InstanceBatch]) -> [(isFaded: Bool, batches: [InstanceBatch])] {
                var result: [(isFaded: Bool, batches: [InstanceBatch])] = []
                for batch in batches {
                    let faded = isFaded(batch)
                    if let last = result.indices.last, result[last].isFaded == faded {
                        result[last].batches.append(batch)
                    } else {
                        result.append((faded, [batch]))
                    }
                }
                return result
            }
            func passes(_ batches: [InstanceBatch]) -> [(batch: InstanceBatch, cullMode: MTLCullMode)] {
                batches.flatMap { batch -> [(batch: InstanceBatch, cullMode: MTLCullMode)] in
                    guard isTransparent, batch.material.renderState.cullMode == .none, batch.material.renderState.fillMode == .fill else {
                        return [(batch, batch.material.renderState.cullMode)]
                    }
                    return [(batch, .front), (batch, .back)]
                }
            }

            func draw(_ batch: InstanceBatch, cullMode: MTLCullMode, instanced: Bool) -> AnyElement {
                let submesh = batch.mesh.submeshes[batch.submeshIndex]
                let normalMatrices = batch.modelMatrices.map(\.normalMatrix)
                let modelMatrices = batch.modelMatrices.map { $0.cameraRelative(to: cameraPosition) }
                var element = materialDraw(submesh, instanceCount: batch.modelMatrices.count, cullMode: cullMode, isMirrored: batch.isMirrored, fillMode: batch.material.renderState.fillMode, stereoViews: stereoViews)
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
                    .parameter("lightClusterUniforms", functionType: .fragment, value: clusterBinding.uniforms)
                    .parameter("lightClusters", functionType: .fragment, buffer: clusterBinding.buffer)
                    .parameter("material", functionType: .fragment, value: resolved.uniforms)
                    .parameter("frameResources", functionType: .fragment, argumentBuffer: frameResources)
                    .parameter("materialResources", functionType: .fragment, argumentBuffer: materialResources.resources(for: resolved))
                    .eraseToAnyElement()
                if let shadowBinding {
                    element = element
                        .parameter("shadow", functionType: .fragment, value: shadowBinding.uniforms)
                        .eraseToAnyElement()
                }
                return element
            }

            let viewCount = stereoViews?.count ?? 1
            return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                let layout = blinnPhongVertexLayout(group.key.vertexDescriptor)
                let vertexShader = layout.hasColors ? shaders.coloredVertex : shaders.vertex
                ForEach(Array(runs(group.single).enumerated()), id: \.offset) { _, run in
                    if run.isFaded {
                        ForEach(Array(run.batches.enumerated()), id: \.offset) { _, batch in
                            try RenderPipeline(label: "Blinn-Phong Faded Depth", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                                draw(batch, cullMode: batch.material.renderState.cullMode, instanced: false)
                            }
                            .vertexDescriptor(layout.descriptor)
                            .depthCompare(function: .greater, writes: true)
                            .renderPipelineDescriptorTransformer { descriptor in
                                descriptor.colorAttachments[0].writeMask = []
                            }
                            .vertexAmplification(count: viewCount)
                            try RenderPipeline(label: "Blinn-Phong Faded", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                                draw(batch, cullMode: batch.material.renderState.cullMode, instanced: false)
                            }
                            .vertexDescriptor(layout.descriptor)
                            .materialRenderState(group.key.renderState, isTransparent: true, writesBlendedDepth: stereoViews != nil, depthFunction: .greaterEqual)
                            .vertexAmplification(count: viewCount)
                        }
                    } else {
                        try RenderPipeline(label: "Blinn-Phong", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                            ForEach(Array(passes(run.batches).enumerated()), id: \.offset) { _, pass in
                                draw(pass.batch, cullMode: pass.cullMode, instanced: false)
                            }
                        }
                        .vertexDescriptor(layout.descriptor)
                        .materialRenderState(group.key.renderState, isTransparent: isTransparent, writesBlendedDepth: stereoViews != nil)
                        .vertexAmplification(count: viewCount)
                    }
                }
                if !group.instanced.isEmpty {
                    try RenderPipeline(label: "Blinn-Phong Instanced", vertexShader: layout.hasColors ? shaders.coloredInstancedVertex : shaders.instancedVertex, fragmentShader: fragmentShader) {
                        ForEach(Array(passes(group.instanced).enumerated()), id: \.offset) { _, pass in
                            draw(pass.batch, cullMode: pass.cullMode, instanced: true)
                        }
                    }
                    .vertexDescriptor(layout.descriptor)
                    .materialRenderState(group.key.renderState, isTransparent: isTransparent, writesBlendedDepth: stereoViews != nil)
                    .vertexAmplification(count: viewCount)
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

extension BlinnPhongSceneMaterial: AppliesAmbientOcclusionInShader {}

// Opacity and diffuse texture alpha cut holes in the shadow (#541).
extension BlinnPhongSceneMaterial: ShadowCasterAlphaMaterial {
    public var shadowCasterAlpha: ShadowCasterAlpha? {
        var alpha = ShadowCasterAlpha(opacity: opacity)
        if usesDiffuseTextureAlpha, case let .texture(texture, samplerDescriptor, _) = diffuse {
            alpha.texture = texture
            alpha.sampler = samplerDescriptor.flatMap { try? BlinnPhongShaders.samplerState(for: $0) }
        }
        return opacity < 1 || alpha.texture != nil ? alpha : nil
    }
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
        var heightTexture: MTLTexture
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
        let normal = normalMap.map(split)
        let height = heightMap.map(split)
        let uniforms = resolvedUniforms()
        let samplerDescriptor = diffuse.sampler ?? ambient.sampler ?? specular.sampler ?? emission.sampler
        let sampler = samplerDescriptor.flatMap { try? BlinnPhongShaders.samplerState(for: $0) } ?? defaultSampler
        return Resolved(uniforms: uniforms, ambientTexture: ambient.texture ?? placeholder, diffuseTexture: diffuse.texture ?? placeholder, specularTexture: specular.texture ?? placeholder, emissionTexture: emission.texture ?? placeholder, normalTexture: normal?.texture ?? placeholder, heightTexture: height?.texture ?? placeholder, sampler: sampler)
    }

    func resolvedUniforms() -> BlinnPhongMaterialUniforms {
        func split(_ source: Source) -> (color: SIMD3<Float>, texture: MTLTexture?) {
            switch source {
            case .color(let color):
                (color, nil)
            case let .texture(texture, _, tint):
                (tint, texture)
            }
        }
        let ambient = split(self.ambient)
        let diffuse = split(self.diffuse)
        let specular = split(self.specular)
        let emission = split(self.emission)
        let normal = normalMap.map(split)
        let height = heightMap.map(split)
        return BlinnPhongMaterialUniforms(
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
            hasNormalMap: normal == nil ? 0 : 1,
            normal: normal?.color ?? [0, 0, 1],
            hasNormalTexture: normal?.texture == nil ? 0 : 1,
            hasHeightTexture: height?.texture == nil ? 0 : 1,
            heightScale: height?.color.x ?? 1,
            parallaxDepth: parallaxDepth,
            stochasticAlpha: renderState.blendMode == .stochastic ? 1 : 0
        )
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

// One BlinnPhongMaterialResources argument buffer per set of textures and sampler. Materials are values, so the key is
// the identities of what they bind; each buffer keeps its textures alive, so identifiers in the key are not reused.
final class MaterialResourcesCache: @unchecked Sendable {
    private let lock = NSLock()
    private var buffers: [[ObjectIdentifier]: ArgumentBuffer] = [:]

    func resources(for resolved: BlinnPhongSceneMaterial.Resolved) -> ArgumentBuffer {
        let textures = [resolved.ambientTexture, resolved.diffuseTexture, resolved.specularTexture, resolved.emissionTexture, resolved.normalTexture, resolved.heightTexture]
        let key = textures.map { ObjectIdentifier($0) } + [ObjectIdentifier(resolved.sampler)]
        return lock.withLock {
            if let buffer = buffers[key] {
                return buffer
            }
            // Dropped wholesale past this many, so changing materials cannot grow it forever.
            if buffers.count >= 256 {
                buffers.removeAll()
            }
            let buffer = ArgumentBuffer(device: resolved.ambientTexture.device, label: "Blinn-Phong Material Resources")
            for (name, texture) in zip(["ambientTexture", "diffuseTexture", "specularTexture", "emissionTexture", "normalTexture", "heightTexture"], textures) {
                buffer.set(name, texture: texture)
            }
            buffer.set("textureSampler", samplerState: resolved.sampler)
            buffers[key] = buffer
            return buffer
        }
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
    var normalMap: SourceKey?
    var heightMap: SourceKey?
    var parallaxDepth: Float
    var renderState: MaterialRenderState

    init(_ material: BlinnPhongSceneMaterial) {
        ambient = SourceKey(material.ambient)
        diffuse = SourceKey(material.diffuse)
        specular = SourceKey(material.specular)
        emission = SourceKey(material.emission)
        shininess = material.shininess
        opacity = material.opacity
        usesDiffuseTextureAlpha = material.usesDiffuseTextureAlpha
        normalMap = material.normalMap.map(SourceKey.init)
        heightMap = material.heightMap.map(SourceKey.init)
        parallaxDepth = material.parallaxDepth
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
    nonisolated(unsafe) private static var cachedShadowPlaceholder: (map: MTLTexture, sampler: MTLSamplerState)?
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
        // Argument buffers (materialResources) need samplers made for them; the caller's descriptor is not changed.
        let argumentBufferDescriptor = descriptor.copy() as! MTLSamplerDescriptor // swiftlint:disable:this force_cast
        argumentBufferDescriptor.supportArgumentBuffers = true
        guard let state = _MTLCreateSystemDefaultDevice().makeSamplerState(descriptor: argumentBufferDescriptor) else {
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
        descriptor.supportArgumentBuffers = true
        guard let sampler = _MTLCreateSystemDefaultDevice().makeSamplerState(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create Blinn-Phong sampler")
        }
        cachedSampler = sampler
        return sampler
    }

    // A 1x1 depth array and comparison sampler for the frame resources when shadows are off; never sampled then.
    static func shadowPlaceholder() throws -> (map: MTLTexture, sampler: MTLSamplerState) {
        lock.lock()
        defer { lock.unlock() }
        if let cachedShadowPlaceholder {
            return cachedShadowPlaceholder
        }
        let device = _MTLCreateSystemDefaultDevice()
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false)
        textureDescriptor.textureType = .type2DArray
        textureDescriptor.usage = .shaderRead
        textureDescriptor.storageMode = .private
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.compareFunction = .greaterEqual
        samplerDescriptor.supportArgumentBuffers = true
        guard let map = device.makeTexture(descriptor: textureDescriptor), let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create Blinn-Phong shadow placeholder")
        }
        map.label = "Blinn-Phong Shadow Placeholder"
        cachedShadowPlaceholder = (map, sampler)
        return (map, sampler)
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
