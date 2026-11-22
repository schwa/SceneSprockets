import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBRShaders
import MetalSupport
import simd

/// Draws a ``PBRModel`` with the glTF metallic-roughness PBR model.
///
/// Place it inside a `RenderPass` with a depth attachment. Use one pipeline for opaque and masked primitives and one
/// for blended primitives, which are sorted back to front each frame.
public struct PBRRenderer: Element {
    public var model: PBRModel
    public var viewMatrix: simd_float4x4
    public var projectionMatrix: simd_float4x4
    public var modelMatrix: simd_float4x4
    public var lighting: PBRLighting
    /// Node transforms to draw with, e.g. from an animation. Nil draws the rest pose.
    public var pose: PBRPose?
    /// The opaque scene rendered by ``PBRTransmissionPass`` earlier in the frame. When set, transmissive materials
    /// show what is behind them; when nil they refract the environment instead.
    public var transmissionTarget: PBRTransmissionTarget?
    /// Set by ``PBRTransmissionPass``. Pre-pass stages write linear HDR radiance.
    var prePassStage: TransmissionPrePassStage = .none
    /// Output one shading input instead of the lit color, for debugging. Ignored by the transmission pre-pass.
    public var debugView: PBRDebugView = .lit
    /// Draw triangle edges over the output. Ignored by the transmission pre-pass.
    public var showsWireframe = false
    /// Materials to draw primitives with instead of their own, e.g. a material variant; switching needs no rebuild.
    public var materialOverrides: PBRModel.MaterialOverrides = [:]
    /// Draw these views at once (stereo, e.g. visionOS) instead of `viewMatrix` and `projectionMatrix`. The pipelines
    /// need a matching `maxVertexAmplificationCount` (``PBRImmersiveScene`` sets it). No transmission pre-pass then.
    public var stereo: StereoViews?
    /// Skip point and line primitives: render passes with a rasterization rate map (visionOS foveation) only allow
    /// triangles, and Metal validation aborts on anything else.
    public var drawsTrianglesOnly = false

    var views: PBRViews { PBRViews(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, stereo: stereo) }
    /// The view-projection of every view drawn.
    var viewProjections: [simd_float4x4] { views.viewProjections }
    /// In stereo, transmissive surfaces draw as coverage: they blend over what is behind them (passthrough or the
    /// environment), so the room shows through glass. With a stereo transmission target, they also show the refracted
    /// model where the target alpha is not zero.
    var transmissionAsCoverage: Bool { views.isStereo && !isTransmissionPrePass }
    /// Whether blended surfaces write depth: in stereo (visionOS), where the compositor needs depth for every pixel we
    /// draw.
    var writesBlendedDepth: Bool { views.isStereo }
    /// Screen-space occlusion is one texture for one view, so stereo and the pre-pass's own target draw without it.
    var usesAmbientOcclusion: Bool { !views.isStereo && !isTransmissionPrePass }
    /// Depth is reversed (near 1, far 0), so nearer is greater.
    var depthFunction: MTLCompareFunction { .greater }
    /// Which part of the model to draw; ``PBRScene`` splits several models' drawing so blended batches of all of
    /// them can be sorted together.
    var phase: DrawPhase = .all
    var isTransmissionPrePass: Bool { prePassStage != .none }
    /// The frame's lighting and view bindings, built once and shared by renderers of one frame (see
    /// ``sharingFrameBindings(_:)``). Nil builds them in `content()`. Cleared when the views or pre-pass stage change.
    var frameBindings: PBRFrameBindings?
    @MSState private var materialTables = PBRMaterialTableCache()

    enum DrawPhase: Equatable {
        case all
        /// Opaque and masked batches only, without transmissive ones drawn as coverage.
        case opaque
        /// Only these batches, in this order.
        case blended([SortedBatch])
    }

    /// A batch in a back-to-front order: a blended batch, or a transmissive opaque one drawn as coverage. Batch IDs
    /// are unique only among a model's opaque or blended batches.
    struct SortedBatch: Hashable {
        var id: Int
        var coverage: Bool
    }

    enum TransmissionPrePassStage {
        case none
        /// Everything except transmissive primitives.
        case opaque
        /// Back faces of double-sided transmissive primitives, seeing the `opaque` stage's result (as three.js does).
        case transmissiveBackFaces
    }

    public init(model: PBRModel, viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, modelMatrix: simd_float4x4 = matrix_identity_float4x4, lighting: PBRLighting? = nil, pose: PBRPose? = nil, transmissionTarget: PBRTransmissionTarget? = nil) {
        self.model = model
        self.viewMatrix = viewMatrix
        self.projectionMatrix = projectionMatrix
        self.modelMatrix = modelMatrix
        self.lighting = lighting ?? PBRLighting(lights: model.lights)
        // A model hiding nodes at rest (whose visibility animation can show them) is drawn with its rest pose, which
        // carries that visibility.
        self.pose = pose ?? (model.restPose.hidesNodes ? model.restPose : nil)
        self.transmissionTarget = transmissionTarget
    }

    public var body: some Element {
        get throws {
            try content()
        }
    }

    func content() throws -> some Element {
        let device = model.device
        precondition(lighting.environment.source.device === device, "The model and the lighting environment must be on one device")
        let shaders = try PBRShaders.shared(device: device)
        let views = views
        let viewProjections = views.viewProjections
        let transmissionScene: MTLTexture? = switch prePassStage {
        case .none: transmissionTarget?.color
        case .opaque: nil
        case .transmissiveBackFaces: try transmissionTarget?.backdrop()
        }
        var bindings = try frameBindings ?? makeFrameBindings()
        bindings.frame.linearOutput = isTransmissionPrePass ? 1 : 0
        bindings.frame.showsWireframe = !isTransmissionPrePass && showsWireframe ? 1 : 0
        bindings.frame.hasTransmissionScene = transmissionScene == nil ? 0 : 1
        bindings.frame.transmissionAsCoverage = transmissionAsCoverage ? 1 : 0
        bindings.frame.transmissionSceneMipCount = Float(transmissionScene?.mipmapLevelCount ?? 1)
        bindings.transmissionScene = transmissionScene ?? shaders.placeholderTexture
        bindings.view = PBRViewUniforms(viewProjectionMatrices: viewPair(viewProjections), modelMatrix: modelMatrix, modelNormalMatrix: modelMatrix.inverse.transpose)

        let draws = frameDraws(cameraPosition: views.centerPosition)
        let materials = materialTables.table(for: model)
        for group in draws.groups {
            for draw in group.draws {
                materials.write(draw)
            }
        }
        let context = PipelineContext(shaders: shaders, bindings: bindings, frameResources: bindings.makeFrameResources(), materials: materials, draws: draws)

        return try Group {
            if transmissionScene != nil {
                // Wait for PBRTransmissionPass to finish writing and mipmapping the scene texture.
                QueueBarrier(after: [.fragment, .blit], before: .fragment)
            }
            ForEach(draws.groups) { group in
                try pipeline(group, context: context)
            }
        }
        // Long-lived buffers and textures stay resident across frames, including the material textures that are only
        // reached through argument buffers.
        .useResourceCollection(model.resourceCollection)
    }

    private struct PipelineContext {
        var shaders: PBRShaders
        var bindings: PBRFrameBindings
        var frameResources: ArgumentBuffer
        var materials: PBRMaterialTable
        var draws: FrameDraws
    }

    /// Consecutive draws of a group that one ``DrawList`` issues (same geometry buffers), or one draw that needs its
    /// own element.
    enum DrawSegment: Identifiable {
        case list(id: Int, geometry: PBRGeometryBuffers, draws: [BatchDraw])
        case single(BatchDraw)

        var id: Int {
            switch self {
            case let .list(id, _, _): id
            case let .single(draw): draw.id
            }
        }

        static func segments(_ draws: [BatchDraw]) -> [Self] {
            var segments: [Self] = []
            var listed: [BatchDraw] = []
            func flush() {
                if let first = listed.first {
                    segments.append(.list(id: first.id, geometry: first.batch.primitive.geometry, draws: listed))
                    listed.removeAll(keepingCapacity: true)
                }
            }
            for draw in draws {
                if draw.isListed {
                    if let first = listed.first, first.batch.primitive.geometry !== draw.batch.primitive.geometry {
                        flush()
                    }
                    listed.append(draw)
                } else {
                    flush()
                    segments.append(.single(draw))
                }
            }
            flush()
            return segments
        }
    }

    // One pipeline for a group: the frame's instance, record, joint and material tables are bound once, around one
    // DrawList per run of listed draws.
    private func pipeline(_ group: DrawGroup, context: PipelineContext) throws -> some Element {
        let variant = group.variant
        let segments = DrawSegment.segments(group.draws)
        // visionOS shows our color only where depth is written. In stereo, blended surfaces write depth so glass over
        // passthrough stays visible (see PBRPipelineState). They draw back to front, so nearer ones still pass.
        return try RenderPipeline(label: group.label, vertexShader: context.shaders.vertexShader(variant), fragmentShader: context.shaders.fragment) {
            let content = ForEach(segments) { segment in
                if case let .list(_, geometry, draws) = segment {
                    drawList(draws, geometry: geometry, skinned: variant.skinned)
                } else if case let .single(draw) = segment {
                    singleDraw(draw)
                }
            }
            .parameter("view", value: context.bindings.view)
            .parameter("materials", argumentBuffer: context.materials.resources)
            .parameter("instanceRecords", values: context.draws.records, else: model.instanceRecordBuffer)
            context.bindings.apply(to: tables(content, variant: variant, draws: context.draws), frameResources: context.frameResources)
        }
        .vertexDescriptor(variant.skinned ? PBRModel.skinnedVertexDescriptor : PBRModel.vertexDescriptor)
        .renderPipelineDescriptorTransformer { descriptor in
            group.state.apply(to: descriptor)
        }
        .depthStencilDescriptor(group.state.depthStencilDescriptor(function: depthFunction))
    }

    // Skinned shaders read joints from the palette; the others read instances.
    @ElementBuilder
    private func tables(_ content: some Element, variant: VertexVariant, draws: FrameDraws) -> some Element {
        if variant.skinned {
            content
                .parameter("jointMatrices", values: draws.palette)
                .parameter("recordJointOffsets", buffer: model.jointOffsetBuffer)
        } else {
            content.parameter("instances", values: draws.instances, else: model.instanceBuffer)
        }
    }

    /// The bindings that depend only on the lighting, views, debug view and pre-pass stage.
    func makeFrameBindings() throws -> PBRFrameBindings {
        let views = views
        return try PBRFrameBindings(
            lighting: lighting,
            viewProjections: views.viewProjections,
            cameraPositions: views.cameraPositions,
            debugView: isTransmissionPrePass ? .lit : debugView,
            usesAmbientOcclusion: usesAmbientOcclusion
        )
    }

    /// Every draw of `draws`, all sharing `geometry`, from one element: a row per instance range. Draws are already
    /// culled, so the list does not cull.
    @ElementBuilder
    private func drawList(_ draws: [BatchDraw], geometry: PBRGeometryBuffers, skinned: Bool) -> some Element {
        let rows = draws.flatMap { draw in
            let primitive = draw.batch.primitive
            return draw.ranges.map { range in
                DrawRow(
                    primitiveType: primitive.primitiveType,
                    geometry: .indexed(primitive.indexStart ..< primitive.indexStart + primitive.indexCount, baseVertex: primitive.baseVertex),
                    instances: range.start ..< range.start + range.count,
                    cullMode: draw.cullMode,
                    // glTF front faces are counter-clockwise; a mirroring transform flips that.
                    winding: range.mirrored ? .clockwise : .counterClockwise
                )
            }
        }
        let list = DrawList(indexBuffer: geometry.indexBuffer, indexType: .uint32, stereoViews: stereo, rows: rows)
            .vertexBuffer(geometry.vertexBuffer, index: 0)
        if skinned, let skinBuffer = geometry.skinBuffer {
            list.vertexBuffer(skinBuffer, index: PBRModel.skinBufferIndex)
        } else {
            list
        }
    }

    /// A draw with its own element: morph targets, which need their own inputs, or a lines fill mode.
    @ElementBuilder
    private func singleDraw(_ batchDraw: BatchDraw) -> some Element {
        let primitive = batchDraw.batch.primitive
        if let morphBuffer = primitive.morphBuffer, primitive.morphTargetCount > 0 {
            draw(batchDraw)
                .parameter("morph", value: PBRMorphUniforms(targetCount: UInt32(primitive.morphTargetCount), vertexCount: UInt32(primitive.vertexCount)))
                .parameter("morphDeltas", buffer: morphBuffer)
                .parameter("morphWeights", values: batchDraw.morphWeights ?? [0])
        } else {
            draw(batchDraw)
        }
    }

    /// One instanced draw per range of `batchDraw`.
    private func draw(_ batchDraw: BatchDraw) -> some Element {
        let primitive = batchDraw.batch.primitive
        // The primitive's range of the model's shared buffers. Vertex buffers are bound at the primitive's first vertex
        // (baseVertex 0), so vertex_id stays local, as the per-primitive morph buffer expects.
        let geometry = primitive.geometry
        let indexBuffer = geometry.indexBuffer
        let indexCount = primitive.indexCount
        let indexOffset = UInt64(primitive.indexStart * MemoryLayout<UInt32>.stride)
        let primitiveType = primitive.primitiveType
        let draw = Draw { encoder in
            stereo?.configure(encoder)
            for range in batchDraw.ranges {
                // glTF front faces are counter-clockwise; a mirroring transform flips that.
                encoder.setFrontFacing(range.mirrored ? .clockwise : .counterClockwise)
                encoder.drawIndexedPrimitives(
                    primitiveType: primitiveType,
                    indexCount: indexCount,
                    indexType: .uint32,
                    indexBuffer: indexBuffer.gpuAddress + indexOffset,
                    indexBufferLength: indexCount * MemoryLayout<UInt32>.stride,
                    instanceCount: range.count,
                    baseVertex: 0,
                    baseInstance: range.start
                )
            }
            // Winding varies per range, so it is set here; put back the default the pass assumes (#472).
            encoder.setFrontFacing(.clockwise)
        }
        .cullMode(batchDraw.cullMode)
        .triangleFillMode(batchDraw.fillMode)
        // The index buffer is only referenced by address; the model's resource collection keeps it resident and the
        // model keeps it alive.
        .vertexBuffer(geometry.vertexBuffer, index: 0, offset: primitive.baseVertex * MemoryLayout<PBRVertex>.stride)
        return skinVertices(of: batchDraw, on: draw)
    }

    @ElementBuilder
    private func skinVertices(of batchDraw: BatchDraw, on content: some Element) -> some Element {
        let primitive = batchDraw.batch.primitive
        if batchDraw.batch.skinIndex != nil, let skinBuffer = primitive.geometry.skinBuffer {
            content.vertexBuffer(skinBuffer, index: PBRModel.skinBufferIndex, offset: primitive.baseVertex * MemoryLayout<PBRSkinVertex>.stride)
        } else {
            content
        }
    }
}

extension PBRRenderer {
    /// This renderer drawing only `phase`.
    func drawing(_ phase: DrawPhase) -> Self {
        var renderer = self
        renderer.phase = phase
        return renderer
    }

    /// This renderer drawing a transmission pre-pass stage.
    func prePass(_ stage: TransmissionPrePassStage) -> Self {
        var renderer = self
        renderer.prePassStage = stage
        renderer.frameBindings = nil
        return renderer
    }

    /// This renderer drawing `stereo`'s views.
    func viewing(_ stereo: StereoViews?) -> Self {
        var renderer = self
        renderer.stereo = stereo
        renderer.frameBindings = nil
        return renderer
    }

    /// `renderers` with the first one's frame bindings built once and shared. The caller guarantees they all have the
    /// same lighting, views, debug view and pre-pass stage.
    static func sharingFrameBindings(_ renderers: [PBRRenderer]) throws -> [PBRRenderer] {
        guard renderers.count > 1 else {
            return renderers
        }
        let bindings = try renderers[0].makeFrameBindings()
        return renderers.map { renderer in
            var renderer = renderer
            renderer.frameBindings = bindings
            return renderer
        }
    }

    /// Draws `renderers` in order. The first is drawn directly: with one renderer the ForEach is empty, which costs
    /// less per frame than a ForEach of one or a conditional.
    @ElementBuilder
    static func all(_ renderers: [PBRRenderer]) -> some Element {
        renderers[0]
        ForEach(renderers.indices.dropFirst(), id: \.self) { index in
            renderers[index]
        }
    }
}

extension Element {
    /// Binds `values` when given (this frame's), else `buffer` (prebuilt).
    @ElementBuilder
    // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
    func parameter<Value>(_ name: String, values: [Value]?, else buffer: MTLBuffer) -> some Element {
        if let values {
            parameter(name, values: values)
        } else {
            parameter(name, buffer: buffer)
        }
    }
}

/// The per-frame inputs of `PBR::shade` (PBRLighting.h): frame uniforms, lights, environment, shadows and screen-space
/// occlusion, with placeholders for what is off. ``PBRRenderer`` uses it; so can other renderers whose shaders build
/// their own `PBR::Fragment`, so their surfaces are lit like PBR meshes.
///
/// ``apply(to:)`` binds by name: `frame`, `lights`, `environmentIrradiance`, `environmentSpecular`, `brdfLookup`,
/// `environmentSampler`, `transmissionScene`, `shadow`, `shadowMap`, `shadowSampler` and `ambientOcclusion`, as
/// `PBR::shade` takes them.
public struct PBRFrameBindings {
    public var frame: PBRFrameUniforms
    /// Never empty: shaders read through a pointer, so an unlit frame binds one unused light.
    public var lights: [LightingLight]
    // PBRRenderer's vertex shaders; not bound by apply(to:).
    var view: PBRViewUniforms
    public var transmissionScene: MTLTexture
    public var irradiance: MTLTexture
    public var specular: MTLTexture
    public var brdfLookup: MTLTexture
    public var sampler: MTLSamplerState
    public var shadow: LightingShadowUniforms
    public var shadowMap: MTLTexture
    public var shadowSampler: MTLSamplerState
    public var ambientOcclusion: MTLTexture

    /// Bindings for `lighting` seen from `viewProjections` (one per view; two in stereo). There is no transmission
    /// scene, so transmissive materials refract the environment.
    public init(lighting: PBRLighting, viewProjections: [simd_float4x4], cameraPositions: [SIMD3<Float>], debugView: PBRDebugView = .lit, usesAmbientOcclusion: Bool = true) throws {
        precondition(!viewProjections.isEmpty && viewProjections.count == cameraPositions.count, "One camera position per view")
        let environment = lighting.environment
        let shaders = try PBRShaders.shared(device: environment.source.device)
        let ambientOcclusion = usesAmbientOcclusion ? lighting.ambientOcclusion : nil
        var frame = PBRFrameUniforms()
        frame.cameraPositions = viewPair(cameraPositions)
        frame.exposure = lighting.exposure
        frame.toneMapping = lighting.toneMapping.shaderValue
        frame.environmentRotation = lighting.environmentRotationMatrix
        frame.lightCount = Int32(lighting.lights.count)
        frame.environmentIntensity = lighting.environmentIntensity
        frame.specularMipCount = Float(environment.specular.mipmapLevelCount)
        frame.viewProjectionMatrices = viewPair(viewProjections)
        frame.debugView = debugView.shaderValue
        frame.transmissionSceneMipCount = 1
        frame.ambientOcclusionStrength = ambientOcclusion?.strength ?? 0
        frame.ambientLight = lighting.ambientLight
        self.frame = frame
        lights = lighting.lights.isEmpty ? [LightingLight()] : lighting.lights
        view = PBRViewUniforms(viewProjectionMatrices: viewPair(viewProjections), modelMatrix: matrix_identity_float4x4, modelNormalMatrix: matrix_identity_float4x4)
        transmissionScene = shaders.placeholderTexture
        irradiance = environment.irradiance
        specular = environment.specular
        brdfLookup = environment.brdfLookup
        sampler = shaders.environmentSampler
        shadow = lighting.shadows?.uniforms ?? LightingShadowUniforms()
        shadowMap = lighting.shadows?.map ?? shaders.placeholderShadowMap
        shadowSampler = lighting.shadows?.sampler ?? shaders.shadowSampler
        self.ambientOcclusion = ambientOcclusion?.texture ?? shaders.placeholderOcclusion
    }

    /// The textures and samplers as a `LightingFrameResources` argument buffer, for ``apply(to:frameResources:)``. Make it once
    /// per frame and share it between pipelines.
    public func makeFrameResources() -> ArgumentBuffer {
        let resources = ArgumentBuffer(device: irradiance.device, label: "PBR Frame Resources")
        resources.set("environmentIrradiance", texture: irradiance)
        resources.set("environmentSpecular", texture: specular)
        resources.set("brdfLookup", texture: brdfLookup)
        resources.set("transmissionScene", texture: transmissionScene)
        resources.set("shadowMap", texture: shadowMap)
        resources.set("ambientOcclusion", texture: ambientOcclusion)
        resources.set("environmentSampler", samplerState: sampler)
        resources.set("shadowSampler", samplerState: shadowSampler)
        return resources
    }

    /// Binds `frame`, `lights`, `shadow` and `frameResources` (from ``makeFrameResources()``), as the `PBR::shade`
    /// overload that takes a `LightingFrameResources` reads them.
    public func apply(to content: some Element, frameResources: ArgumentBuffer) -> some Element {
        content
            .parameter("frame", value: frame)
            .parameter("lights", values: lights)
            .parameter("shadow", value: shadow)
            .parameter("frameResources", argumentBuffer: frameResources)
    }

    public func apply(to content: some Element) -> some Element {
        content
            .parameter("frame", value: frame)
            .parameter("lights", values: lights)
            .parameter("environmentIrradiance", texture: irradiance)
            .parameter("environmentSpecular", texture: specular)
            .parameter("brdfLookup", texture: brdfLookup)
            .parameter("environmentSampler", samplerState: sampler)
            .parameter("transmissionScene", texture: transmissionScene)
            .parameter("shadow", value: shadow)
            .parameter("shadowMap", texture: shadowMap)
            .parameter("shadowSampler", samplerState: shadowSampler)
            .parameter("ambientOcclusion", texture: ambientOcclusion)
    }
}

struct PBRShaders {
    var vertex: VertexShader
    var fragment: FragmentShader
    var skinnedVertex: VertexShader
    var morphedVertex: VertexShader
    var skinnedMorphedVertex: VertexShader
    var backgroundVertex: VertexShader
    var backgroundFragment: FragmentShader
    var copyFragment: FragmentShader
    /// Bound as the transmission scene when there is none; never sampled then.
    var placeholderTexture: MTLTexture
    var environmentSampler: MTLSamplerState
    /// Bound as the shadow map when there is none; never sampled then.
    var placeholderShadowMap: MTLTexture
    var placeholderOcclusion: MTLTexture
    var shadowSampler: MTLSamplerState

    private static let cache = Cache()

    /// The shaders and placeholders for `device`, made once per device.
    static func shared(device: MTLDevice) throws -> Self {
        try cache.shaders(for: device)
    }

    // @unchecked: Metal objects are not Sendable, so Mutex cannot hold them; `lock` guards `entries`, the only state,
    // and the shaders are never changed after they are made. Renderers are built on several threads.
    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [ObjectIdentifier: PBRShaders] = [:]

        func shaders(for device: MTLDevice) throws -> PBRShaders {
            let key = ObjectIdentifier(device)
            if let cached = lock.withLock({ entries[key] }) {
                return cached
            }
            let made = try PBRShaders.make(device: device)
            return lock.withLock {
                if let raced = entries[key] {
                    return raced
                }
                entries[key] = made
                return made
            }
        }
    }

    func vertexShader(_ variant: VertexVariant) -> VertexShader {
        switch (variant.skinned, variant.morphed) {
        case (false, false): vertex
        case (false, true): morphedVertex
        case (true, false): skinnedVertex
        case (true, true): skinnedMorphedVertex
        }
    }

    private static func make(device: MTLDevice) throws -> Self {
        let library = try ShaderLibrary(bundle: .metalSprocketsPBRShaders(), device: device)
        let pbr = library.namespaced("PBR")
        let ibl = library.namespaced("PBRIBL")

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.supportArgumentBuffers = true
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor),
              let placeholderTexture = device.makeTexture(descriptor: {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 1, height: 1, mipmapped: false)
                // An array, like PBRTransmissionTarget's textures.
                descriptor.textureType = .type2DArray
                descriptor.usage = .shaderRead
                return descriptor
              }()),
              let placeholderShadowMap = device.makeTexture(descriptor: {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false)
                descriptor.textureType = .type2DArray
                descriptor.usage = .shaderRead
                descriptor.storageMode = .private
                return descriptor
              }()),
              let placeholderOcclusion = device.makeTexture(descriptor: {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 1, height: 1, mipmapped: false)
                descriptor.usage = .shaderRead
                return descriptor
              }()),
              let shadowSampler = device.makeSamplerState(descriptor: {
                let descriptor = MTLSamplerDescriptor()
                descriptor.supportArgumentBuffers = true
                descriptor.minFilter = .linear
                descriptor.magFilter = .linear
                descriptor.sAddressMode = .clampToEdge
                descriptor.tAddressMode = .clampToEdge
                descriptor.compareFunction = .lessEqual
                return descriptor
              }())
        else {
            throw LightingEnvironmentError.resourceCreationFailed("renderer resources")
        }

        return Self(
            vertex: try pbr.vertex_main,
            fragment: try pbr.fragment_main,
            skinnedVertex: try pbr.vertex_skinned,
            morphedVertex: try pbr.vertex_main_morphed,
            skinnedMorphedVertex: try pbr.vertex_skinned_morphed,
            backgroundVertex: try ibl.background_vertex,
            backgroundFragment: try ibl.background_fragment,
            copyFragment: try ibl.copy_fragment,
            placeholderTexture: placeholderTexture,
            environmentSampler: sampler,
            placeholderShadowMap: placeholderShadowMap,
            placeholderOcclusion: placeholderOcclusion,
            shadowSampler: shadowSampler
        )
    }
}
