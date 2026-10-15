import GeometryLite3D
import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSceneGraphShaders
import MetalSupport
import SwiftMesh
import simd

// A Blinn-Phong surface: ambient (lit by the renderer's ambient light), diffuse and specular, each a color or a
// texture tinted by a color.
public struct BlinnPhongSceneMaterial: MetalSprocketsSceneGraph.Material, SamplesShadowsInShader {
    public enum Source {
        // Linear RGB.
        case color(SIMD3<Float>)
        // Sampled at the mesh's first texture coordinates and multiplied by `tint`. A nil sampler uses linear
        // filtering with repeat.
        case texture(MTLTexture, sampler: MTLSamplerState? = nil, tint: SIMD3<Float> = .one)

        public static func color(_ grey: Float) -> Self {
            .color(SIMD3(repeating: grey))
        }
    }

    public var ambient: Source
    public var diffuse: Source
    public var specular: Source
    public var shininess: Float
    // 0 is invisible, 1 opaque. Below 1 the material blends over what is behind it and does not write depth;
    // transparent meshes draw after opaque ones of the same rendering order, farthest first.
    public var opacity: Float
    // Multiplies opacity by the diffuse texture's alpha (and makes the material transparent).
    public var usesDiffuseTextureAlpha: Bool
    // Added unlit, like SCNMaterial.emission.
    public var emission: Source
    // Tangent-space normal map (+Y up, as in glTF), sampled at the first texture coordinates. Meshes need no tangents.
    public var normalMap: MTLTexture?
    // Counter-clockwise triangles are front faces. `.none` draws both sides.
    public var cullMode: MTLCullMode
    public var renderState: MaterialRenderState

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

public struct BlinnPhongMaterialRenderer: SceneGraphMaterialRenderer {
    public var ambientLightColor: SIMD3<Float>

    public init(ambientLightColor: SIMD3<Float> = [0.15, 0.15, 0.2]) {
        self.ambientLightColor = ambientLightColor
    }

    public var materialType: any MetalSprocketsSceneGraph.Material.Type {
        BlinnPhongSceneMaterial.self
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let viewProjection = context.projectionMatrix * context.viewMatrix
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let lights = blinnPhongLights(context.lights, shadowSlices: context.shadow == nil ? [] : context.lightShadowSlices)
        let frame = BlinnPhongFrame(viewProjection: viewProjection, cameraPosition: cameraPosition, ambientLightColor: ambientLightColor, lightCount: Int32(lights.count))
        // An empty array cannot be bound; the shader reads none of it when lightCount is 0.
        let lightValues = lights.isEmpty ? [BlinnPhongLight()] : lights
        // The shader has no morph or skin inputs, so those meshes are deformed on the CPU. They skip culling because
        // their node bounds do not cover the deformation.
        // SceneGraphElement batches opaque and transparent entries apart, transparent ones sorted farthest first.
        let isTransparent = entries.first?.isTransparent ?? false
        let culled = Set(culledMeshEntries(entries, viewProjection: viewProjection).map { ObjectIdentifier($0.node) })
        var visible: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4)] = []
        var deformed: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4)] = []
        for entry in entries {
            if let result = entry.deformed(revision: context.revision) {
                // Deformed meshes skip culling; their node bounds do not cover the deformation.
                if isTransparent {
                    visible.append((entry, result.mesh, result.modelMatrix))
                } else {
                    deformed.append((entry, result.mesh, result.modelMatrix))
                }
            } else if culled.contains(ObjectIdentifier(entry.node)) {
                visible.append((entry, entry.mesh, entry.worldTransform))
            }
        }
        if !isTransparent {
            visible = sortedFrontToBack(visible.map(\.entry), cameraPosition: cameraPosition).map { (entry: $0, mesh: $0.mesh, modelMatrix: $0.worldTransform) } + deformed
        }
        let items = visible.compactMap { item in
            (item.entry.material as? BlinnPhongSceneMaterial).map { (entry: item.entry, mesh: item.mesh, modelMatrix: item.modelMatrix, material: $0) }
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
                return (key: group.key, single: batches.filter { $0.modelMatrices.count == 1 }, instanced: batches.filter { $0.modelMatrices.count > 1 })
            }
        }
        return BlinnPhongBatchesElement(groups: groups, frame: frame, lights: lightValues, shadow: context.shadow, isTransparent: isTransparent).eraseToAnyElement()
    }
}

// Draws prepared batches; an element so it can read the submission index (the shadow map has one texture per frame
// in flight).
private struct BlinnPhongBatchesElement: Element {
    var groups: [(key: PipelineKey, single: [InstanceBatch], instanced: [InstanceBatch])]
    var frame: BlinnPhongFrame
    var lights: [BlinnPhongLight]
    var shadow: SceneGraphShadows.Sampling?
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
                    for (index, matrix) in shadow.shadowMap.lightViewProjectionMatrices.prefix(slices.count).enumerated() {
                        slices[index] = matrix
                    }
                }
                return (shadow.shadowMap.depthTexture(forSubmission: submissionIndex), shadow.shadowMap.sampler, uniforms)
            }

            func draw(_ batch: InstanceBatch, instanced: Bool) throws -> AnyElement {
                let submesh = batch.mesh.submeshes[batch.submeshIndex]
                let normalMatrices = batch.modelMatrices.map(\.normalMatrix)
                var element = materialDraw(submesh, instanceCount: batch.modelMatrices.count, cullMode: batch.material.cullMode, isMirrored: batch.isMirrored, fillMode: batch.material.renderState.fillMode)
                .vertexBuffers(batch.mesh.vertexBuffers)
                .parameter("frame", functionType: .vertex, value: frame)
                .eraseToAnyElement()
                if instanced {
                    element = element
                        .parameter("modelMatrices", functionType: .vertex, values: batch.modelMatrices)
                        .parameter("normalMatrices", functionType: .vertex, values: normalMatrices)
                        .eraseToAnyElement()
                } else {
                    element = element
                        .parameter("modelMatrix", functionType: .vertex, value: batch.modelMatrices[0])
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

            return try ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                if !group.single.isEmpty {
                    try RenderPipeline(label: "Blinn-Phong", vertexShader: shaders.vertex, fragmentShader: fragmentShader) {
                        try ForEach(Array(group.single.enumerated()), id: \.offset) { _, batch in
                            try draw(batch, instanced: false)
                        }
                    }
                    .vertexDescriptor(group.key.vertexDescriptor.mtlVertexDescriptor)
                    .materialRenderState(group.key.renderState, isTransparent: isTransparent)
                }
                if !group.instanced.isEmpty {
                    try RenderPipeline(label: "Blinn-Phong Instanced", vertexShader: shaders.instancedVertex, fragmentShader: fragmentShader) {
                        try ForEach(Array(group.instanced.enumerated()), id: \.offset) { _, batch in
                            try draw(batch, instanced: true)
                        }
                    }
                    .vertexDescriptor(group.key.vertexDescriptor.mtlVertexDescriptor)
                    .materialRenderState(group.key.renderState, isTransparent: isTransparent)
                }
            }
        }
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
        var sampler: MTLSamplerState
    }

    // Textures missing from the material are bound as `placeholder`, and flagged off. The first texture's sampler
    // is used for all three.
    func resolved(placeholder: MTLTexture, defaultSampler: MTLSamplerState) -> Resolved {
        func split(_ source: Source) -> (color: SIMD3<Float>, texture: MTLTexture?, sampler: MTLSamplerState?) {
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
        let sampler = diffuse.sampler ?? ambient.sampler ?? specular.sampler ?? emission.sampler ?? defaultSampler
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

// Groups items that share vertex buffers, submesh and material, keeping first-seen order.
func instanceBatches(_ items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongSceneMaterial)]) -> [InstanceBatch] {
    struct Key: Hashable {
        var vertexBuffers: [ObjectIdentifier]
        var submeshIndex: Int
        var material: MaterialKey
        var receivesShadow: Bool
        var isMirrored: Bool
        var opacity: Float
    }
    var batches: [InstanceBatch] = []
    var indexByKey: [Key: Int] = [:]
    for item in items {
        let buffers = item.mesh.vertexBuffers.sorted { $0.key < $1.key }.map { ObjectIdentifier($0.value) }
        let key = Key(vertexBuffers: buffers, submeshIndex: item.entry.submeshIndex, material: MaterialKey(item.material), receivesShadow: item.entry.receivesShadow, isMirrored: item.modelMatrix.isMirroring, opacity: item.entry.opacity)
        if let index = indexByKey[key] {
            batches[index].modelMatrices.append(item.modelMatrix)
        } else {
            indexByKey[key] = batches.count
            batches.append(InstanceBatch(mesh: item.mesh, submeshIndex: item.entry.submeshIndex, material: item.material, receivesShadow: item.entry.receivesShadow, opacity: item.entry.opacity, modelMatrices: [item.modelMatrix]))
        }
    }
    return batches
}

// Materials hold textures, so they are not Hashable; compare colors by value and textures by identity.
private struct MaterialKey: Hashable {
    var sources: [SourceKey]
    var shininess: Float
    var opacity: Float
    var usesDiffuseTextureAlpha: Bool
    var normalMap: ObjectIdentifier?
    var cullMode: UInt
    var renderState: MaterialRenderState

    init(_ material: BlinnPhongSceneMaterial) {
        sources = [material.ambient, material.diffuse, material.specular, material.emission].map(SourceKey.init)
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

// From BlinnPhong.metal in MetalSprocketsSceneGraphShaders, loaded once.
struct BlinnPhongShaders {
    var vertex: VertexShader
    var instancedVertex: VertexShader
    var fragment: FragmentShader
    var shadowedFragment: FragmentShader

    nonisolated(unsafe) private static var cached: BlinnPhongShaders?
    nonisolated(unsafe) private static var cachedPlaceholder: MTLTexture?
    nonisolated(unsafe) private static var cachedSampler: MTLSamplerState?
    private static let lock = NSLock()

    static func shared() throws -> BlinnPhongShaders {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .metalSprocketsSceneGraphShaders()).namespaced("BlinnPhong")
        func fragment(shadows: Bool) throws -> FragmentShader {
            var constants = FunctionConstants()
            constants["HAS_SHADOWS"] = .bool(shadows)
            return try library.function(named: "fragment_main", type: FragmentShader.self, constants: constants)
        }
        let shaders = BlinnPhongShaders(vertex: try library.vertex_main, instancedVertex: try library.vertex_instanced, fragment: try fragment(shadows: false), shadowedFragment: try fragment(shadows: true))
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
