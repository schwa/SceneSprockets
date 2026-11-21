import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
#if os(visionOS)
import MetalSprocketsUI
#endif
import MetalSupport
import os
import simd
import Synchronization

/// The camera, lights and settings of one frame, that ``SceneGraphElement`` gives each material renderer.
public struct RenderContext {
    /// The view matrix: the inverse of ``cameraMatrix``.
    public var viewMatrix: simd_float4x4
    /// The projection matrix. It already contains the reversed-depth flip, so use `.greater` depth tests.
    public var projectionMatrix: simd_float4x4
    /// The camera's world transform.
    public var cameraMatrix: simd_float4x4
    /// The lights that the camera sees, with their world transforms.
    public var lights: [(worldTransform: simd_float4x4, light: Light)]
    /// The scene graph's revision, to find out whether cached data is still correct.
    public var revision: SceneGraph.Revision
    /// The scene graph's background and image-based lighting.
    public var environment: SceneGraph.Environment
    /// The camera's categoryBitMask.
    public var categoryBitMask: UInt = .max
    /// Parallel to `lights`: each light node's lightCategoryBitMask.
    public var lightCategoryBitMasks: [UInt] = []
    /// Set when shadows are on, for renderers that sample them while shading.
    public internal(set) var shadow: Shadows.Sampling?
    /// Parallel to `lights` when `shadow` is set: each light's shadow map slices (empty for none).
    public internal(set) var lightShadowSlices: [Range<Int>] = []
    /// When set, renderers output this material value instead of lighting (#195).
    public internal(set) var materialChannel: MaterialChannel?
    /// Set when ambient occlusion is on, for renderers that apply it while shading (#136): an `.r16Float` texture of
    /// ambient visibility (1 is unoccluded), one texel per pixel of the color target.
    public internal(set) var ambientOcclusion: MTLTexture?
    /// Set when the frame draws several views at once (stereo, #380). ``viewMatrix``, ``cameraMatrix`` and
    /// ``projectionMatrix`` then describe one camera between the views, for culling, sorting and renderers without
    /// stereo support.
    public internal(set) var stereoViews: StereoViews?
    /// Set for content drawn into an intermediate target that needs linear light, such as the scene behind PBR glass:
    /// renderers skip ``SceneGraph/Environment/exposure`` and tone mapping then.
    public internal(set) var outputIsLinear = false

    /// The number of views that each draw goes to: 1, or the stereo view count.
    public var viewCount: Int { stereoViews?.count ?? 1 }

    /// Each view's projection times its view matrix.
    public var viewProjections: [simd_float4x4] {
        stereoViews?.viewProjections ?? [projectionMatrix * viewMatrix]
    }
}

/// A renderer for one material family.
///
/// To add a material family, write a type that conforms to this protocol. The scene graph does not change.
public protocol MaterialRenderer {
    /// The material type that the renderer draws.
    var materialType: any SceneMaterial.Type { get }
    /// Returns an element that draws mesh entries whose material is ``materialType``.
    ///
    /// The element draws inside the scene's render pass. ``SceneGraphElement`` can call this method several times in
    /// a frame, for batches with different lights or rendering order.
    ///
    /// - Parameters:
    ///   - entries: The mesh entries to draw.
    ///   - context: The camera, lights and settings of the frame.
    func makeElement(entries: [SceneGraph.MeshEntry], context: RenderContext) throws -> AnyElement
}

/// A renderer that can draw `SceneGraph.Environment.Background.environment`. The element asks each one in order and
/// draws the first non-nil result before any meshes, even when the renderer has no entries.
public protocol BackgroundRenderer {
    /// Returns an element that draws the environment background, or `nil` if this renderer cannot draw it.
    func makeBackgroundElement(context: RenderContext) throws -> AnyElement?
}

/// A renderer that needs its own passes before the scene pass, such as one that draws what is behind glass.
/// `entries` are all of this renderer's entries; `makeElement` is called after this for each batch.
/// `otherOpaqueContent` makes the other renderers' batches, opaque then transparent and faded (#327), for a pass that
/// needs the rest of the scene; nil when there are none.
public protocol PrePassRenderer {
    func makePrePassElement(entries: [SceneGraph.MeshEntry], context: RenderContext, viewSize: (width: Int, height: Int), otherOpaqueContent: () throws -> AnyElement?) throws -> AnyElement?
}

/// Renders every mesh entry in one pass by handing each material family to its renderer.
/// Entries whose material type has no renderer are skipped.
/// The view comes from `camera` (default: the first camera node) unless `cameraMatrix` overrides its world transform.
/// With no camera node, `defaultCamera` is used at `cameraMatrix` (identity if nil).
/// `cameraOverride` replaces the camera node's camera (projection and masks) even when there is one, for editor cameras.
/// `defaultLight` is added at the camera when the scene has no lights, like SceneKit's autoenablesDefaultLighting.
public struct SceneGraphElement: Element {
    // Read instead of the live graph, so the element can be built on another thread (#388).
    var presentation: SceneGraph.Presentation
    var cameraID: SceneGraph.Node.ID?
    var cameraMatrix: simd_float4x4?
    var aspectRatio: Float
    var renderers: [any MaterialRenderer]
    var defaultCamera: Camera?
    var cameraOverride: Camera?
    // Keep the scene depth for later passes (it must not be memoryless), such as depth-tested overlays.
    var storesDepth: Bool
    var defaultLight: Light?
    var shadows: Shadows?
    var decorations: ((RenderContext) throws -> AnyElement?)?
    // Draws every mesh in this debug view instead of its material (#132).
    var debugMode: DebugMode?
    // Each renderer shows this material value instead of lighting (#195). Ignored while debugMode is set.
    var materialChannel: MaterialChannel?
    // Draws these views at once instead of the camera's (#380).
    var stereoViews: StereoViews?
    // Multisample antialiasing of the scene pass (#95).
    var sampleCount = 1
    // Meters each frame and scales the environment's exposure (#508).
    var autoExposure: AutoExposure?
    #if os(visionOS)
    // Set by SceneImmersiveContent: the scene pass is the compositor's pass (#381).
    var immersiveContext: ImmersiveContext?
    #endif

    @MSEnvironment(\.renderPassDescriptor)
    private var renderPassDescriptor

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    /// Creates an element that draws a scene graph.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene to draw.
    ///   - camera: The camera node. If `nil`, the element uses the first camera node.
    ///   - cameraMatrix: A world transform that replaces the camera node's transform.
    ///   - aspectRatio: The width of the view divided by its height.
    ///   - renderers: One renderer for each material family that the scene uses.
    ///   - defaultCamera: The camera to use when the scene has no camera node.
    ///   - cameraOverride: A camera that replaces the camera node's camera.
    ///   - defaultLight: A light at the camera when the scene has no lights.
    ///   - shadows: The shadow settings and state, or `nil` for no shadows.
    ///   - storesDepth: Whether to keep the scene depth for later passes.
    ///   - decorations: A closure that returns extra elements to draw in the scene pass.
    ///   - debugMode: A debug view to show instead of the materials.
    ///   - materialChannel: A material value to show instead of lighting.
    ///   - stereoViews: Views to draw at once, such as a visionOS immersive space's eyes. They replace the camera's view
    ///     and projection; the camera still supplies the category mask.
    ///   - sampleCount: Multisample antialiasing samples per pixel (1, 2, 4 or 8). Above 1, the scene pass draws into
    ///     multisampled targets and resolves color and depth into the view's, so post passes read resolved depth.
    ///     Leave RenderView's own sample count at 1.
    ///   - autoExposure: Automatic exposure state, or `nil` for the environment's exposure only.
    ///
    /// Makes the scene's ``SceneGraph/presentation()`` snapshot, so call it on the thread that edits the graph.
    public init(sceneGraph: SceneGraph, camera: SceneGraph.Node? = nil, cameraMatrix: simd_float4x4? = nil, aspectRatio: Float, renderers: [any MaterialRenderer], defaultCamera: Camera? = nil, cameraOverride: Camera? = nil, defaultLight: Light? = nil, shadows: Shadows? = nil, storesDepth: Bool = false, decorations: ((RenderContext) throws -> AnyElement?)? = nil, debugMode: DebugMode? = nil, materialChannel: MaterialChannel? = nil, stereoViews: StereoViews? = nil, sampleCount: Int = 1, autoExposure: AutoExposure? = nil) {
        self.init(presentation: sceneGraph.presentation(), cameraID: camera?.id, cameraMatrix: cameraMatrix, aspectRatio: aspectRatio, renderers: renderers, defaultCamera: defaultCamera, cameraOverride: cameraOverride, defaultLight: defaultLight, shadows: shadows, storesDepth: storesDepth, decorations: decorations, debugMode: debugMode, materialChannel: materialChannel, stereoViews: stereoViews, sampleCount: sampleCount, autoExposure: autoExposure)
    }

    /// Creates an element that draws a snapshot of a scene graph, from ``SceneGraph/presentation()``. The snapshot can
    /// be drawn on any thread. `cameraID` picks the camera node (the first camera if `nil`); the other parameters are
    /// as in ``init(sceneGraph:camera:cameraMatrix:aspectRatio:renderers:defaultCamera:cameraOverride:defaultLight:shadows:storesDepth:decorations:debugMode:materialChannel:stereoViews:sampleCount:autoExposure:)``.
    public init(presentation: SceneGraph.Presentation, cameraID: SceneGraph.Node.ID? = nil, cameraMatrix: simd_float4x4? = nil, aspectRatio: Float, renderers: [any MaterialRenderer], defaultCamera: Camera? = nil, cameraOverride: Camera? = nil, defaultLight: Light? = nil, shadows: Shadows? = nil, storesDepth: Bool = false, decorations: ((RenderContext) throws -> AnyElement?)? = nil, debugMode: DebugMode? = nil, materialChannel: MaterialChannel? = nil, stereoViews: StereoViews? = nil, sampleCount: Int = 1, autoExposure: AutoExposure? = nil) {
        self.presentation = presentation
        self.autoExposure = autoExposure
        self.sampleCount = max(sampleCount, 1)
        self.cameraID = cameraID
        self.stereoViews = stereoViews
        self.debugMode = debugMode
        self.materialChannel = materialChannel
        self.cameraOverride = cameraOverride
        self.storesDepth = storesDepth
        self.decorations = decorations
        self.cameraMatrix = cameraMatrix
        self.aspectRatio = aspectRatio
        // Kept with the debug renderer, so background renderers still draw.
        self.renderers = debugMode == nil ? renderers : renderers + [SceneGraphDebugRenderer()]
        self.defaultCamera = defaultCamera
        self.defaultLight = defaultLight
        self.shadows = shadows
    }

    public var body: some Element {
        get throws {
            guard var context = makeRenderContext(presentation: presentation, cameraID: cameraID, cameraMatrix: cameraMatrix, aspectRatio: aspectRatio, defaultCamera: defaultCamera ?? (stereoViews == nil ? nil : Camera(projection: PerspectiveProjection())), cameraOverride: cameraOverride, defaultLight: defaultLight, stereoViews: stereoViews) else {
                return EmptyElement().eraseToAnyElement()
            }
            let cameraPosition = context.cameraMatrix.columns.3.xyz
            context.materialChannel = debugMode == nil ? materialChannel : nil
            // Metered into after the post passes; needs the view's color and depth to be readable.
            let autoExposureBuffer: MTLBuffer? = try {
                guard let autoExposure, debugMode == nil, let device = renderPassDescriptor?.colorAttachments[0].texture?.device else {
                    return nil
                }
                let (exposure, buffer) = try autoExposure.update(submissionIndex: submissionIndex, device: device)
                context.environment.exposure *= exposure
                return buffer
            }()
            var entries = applyLevelsOfDetail(presentation.meshes.filter { $0.categoryBitMask & context.categoryBitMask != 0 }, cameraPosition: cameraPosition)
            if let debugMode {
                entries = entries.map { entry in
                    var entry = entry
                    entry.material = SceneGraphDebugMaterial(mode: debugMode)
                    return entry
                }
            }
            // The shadow mask and fog passes read and write the view's textures, so they need the right usage.
            let postTargets: (color: MTLTexture, depth: MTLTexture)? = {
                // Shadow and post passes read and write one 2D target; stereo targets are layered (#382).
                guard stereoViews == nil, let color = renderPassDescriptor?.colorAttachments[0].texture, let depth = renderPassDescriptor?.depthAttachment.texture,
                      color.usage.isSuperset(of: Shadows.requiredColorUsage), depth.usage.isSuperset(of: Shadows.requiredDepthUsage),
                      depth.storageMode != .memoryless
                else {
                    return nil
                }
                return (color, depth)
            }()
            // Prepared before the renderers, which sample it while shading.
            let shadowFrame = try postTargets.flatMap { targets in
                try shadows?.prepare(entries: entries, context: context, bounds: presentation.bounds, viewSize: (targets.color.width, targets.color.height), renderers: renderers)
            }
            if let shadows, let shadowFrame {
                context.shadow = Shadows.Sampling(shadowMap: shadowFrame.shadowMap, intensity: shadows.intensity, color: shadows.color, softness: shadows.softness)
                context.lightShadowSlices = shadowFrame.lightSlices
            }
            var prePasses: [AnyElement] = []
            // Morphs and skins on the GPU for renderers that draw plain vertex buffers (#298). Their entries are then
            // swapped for the deformed meshes, so those renderers draw them like any other mesh (#590).
            let deformationJobs = GPUDeformation.prepare(entries: entries, revision: context.revision, submissionIndex: submissionIndex)
            if !deformationJobs.isEmpty {
                prePasses.append(DeformationPass(jobs: deformationJobs).eraseToAnyElement())
            }
            let revision = context.revision
            entries = entries.map { $0.material is any DrawsDeformedVertices ? $0.resolvingDeformation(revision: revision) : $0 }
            let opaque = entries.filter { !$0.isTransparent }
            let inShaderAmbientOcclusion = opaque.filter { $0.material is any AppliesAmbientOcclusionInShader }
            let wantsAmbientOcclusion = context.environment.ambientOcclusion != nil && postTargets != nil && debugMode == nil
            let ambientOcclusionContent = wantsAmbientOcclusion && !opaque.isEmpty ? try makeOpaqueContent(entries: opaque, context: context, excluding: nil) : nil
            let visibleParticleFrames = presentation.visibleParticleIndices.map { presentation.particleFrames[$0] }
            let postProcessing = postTargets == nil ? nil : presentation.postProcessing
            let plan = SceneFramePlan(.init(
                hasPostTargets: postTargets != nil,
                isDebug: debugMode != nil,
                hasAmbientOcclusionSettings: context.environment.ambientOcclusion != nil,
                opaqueCount: ambientOcclusionContent == nil ? 0 : opaque.count,
                inShaderAmbientOcclusionCount: inShaderAmbientOcclusion.count,
                hasShadowFrame: shadowFrame != nil,
                shadowMasksEverything: shadowFrame?.masksEverything ?? false,
                hasFog: presentation.fog != nil,
                adjustsColor: postProcessing?.adjustsColor ?? false,
                hasSoftParticles: visibleParticleFrames.contains(where: \.isSoft),
                hasAutoExposure: autoExposureBuffer != nil,
                resolvesMultisample: renderPassDescriptor?.colorAttachments[0].resolveTexture != nil || sampleCount > 1,
                storesDepthRequested: storesDepth,
                depthIsMemoryless: renderPassDescriptor?.depthAttachment.texture?.storageMode == .memoryless
            ))
            var ambientOcclusionApply: ApplyAmbientOcclusionPass?
            if case let .passes(inShaderDepth, appliesAsPostPass) = plan.ambientOcclusion, let postTargets, let ambientOcclusionContent, let settings = context.environment.ambientOcclusion {
                let inShaderContent = inShaderDepth ? try makeOpaqueContent(entries: inShaderAmbientOcclusion, context: context, excluding: nil) : nil
                ambientOcclusionApply = try makeAmbientOcclusionPasses(settings: settings, content: ambientOcclusionContent, inShaderContent: inShaderContent, splitsInShader: inShaderDepth, appliesAsPostPass: appliesAsPostPass, postTargets: postTargets, context: &context, prePasses: &prePasses)
            }
            prePasses += try makeRendererPrePasses(entries: entries, context: context)
            #if os(visionOS)
            if immersiveContext != nil {
                // Only the compositor's pass may end through its render context, which also ends the command buffer.
                prePasses = prePasses.map { $0.immersiveRenderContext(nil).eraseToAnyElement() }
            }
            #endif
            var elements = try makeSceneElements(entries: entries, context: context, drawsText: plan.drawsText)
            // Particles simulate in their own compute pass before the scene pass, then draw after the meshes.
            let particleSimulations = try presentation.particleFrames.map { try $0.system.simulate($0, view: context.viewMatrix).eraseToAnyElement() }
            prePasses = particleSimulations + prePasses
            // Soft particles read the scene's depth, so they draw in a second pass after a depth copy.
            let softParticleDepth: (scene: MTLTexture, copy: MTLTexture)? = try {
                guard plan.hasSoftParticlePass, let postTargets else {
                    return nil
                }
                let copy = try ParticleDepthShaders.sceneDepthTexture(device: postTargets.depth.device, width: postTargets.depth.width, height: postTargets.depth.height)
                return (postTargets.depth, copy)
            }()
            var particleElements: [AnyElement] = []
            for frame in visibleParticleFrames {
                // Made by the simulation above.
                guard let runtime = frame.system.renderRuntime else {
                    continue
                }
                // Sprite draws inherit the scene pass's depth state, which writes depth; blended sprites must not.
                let rendered: AnyElement = if let stereoViews = context.stereoViews {
                    // Simulation already sorts for context.viewMatrix, the center camera (#379).
                    try runtime.render(views: stereoViews, sceneDepth: softParticleDepth?.copy).eraseToAnyElement()
                } else {
                    try runtime.render(projection: context.projectionMatrix, view: context.viewMatrix, sceneDepth: softParticleDepth?.copy).eraseToAnyElement()
                }
                particleElements.append(rendered.depthCompare(function: .greater, writes: false).eraseToAnyElement())
            }
            if softParticleDepth == nil {
                elements += particleElements
                particleElements = []
            }
            let clearColor: MTLClearColor? = if case let .color(color) = context.environment.background {
                MTLClearColor(red: Double(color.x), green: Double(color.y), blue: Double(color.z), alpha: Double(color.w))
            } else {
                nil
            }
            let scenePass = try MetalSprockets.Group {
                try makeScenePass(elements: elements, clearColor: clearColor, storesDepth: plan.scenePassStoresDepth)
                if let softParticleDepth {
                    ParticleDepthCopyPass(depthTexture: softParticleDepth.scene, output: softParticleDepth.copy)
                    try makeParticlePass(elements: particleElements, storesDepth: plan.particlePassStoresDepth)
                }
            }
            guard let postTargets, plan.hasPostPhase else {
                if prePasses.isEmpty {
                    return scenePass.gpuTimed(SceneGPUTimingLabel.scene).eraseToAnyElement()
                }
                return try MetalSprockets.Group {
                    ForEach(Array(prePasses.enumerated()), id: \.offset) { _, prePass in
                        prePass
                    }
                    .gpuTimed(SceneGPUTimingLabel.prePasses)
                    scenePass
                        .gpuTimed(SceneGPUTimingLabel.scene)
                }
                .eraseToAnyElement()
            }
            // Post passes rebuild positions from depth in camera-relative space (camera at the origin), so they stay
            // precise far from the world origin (#257). Shadow views are camera-relative too.
            let relativeViewProjection = context.projectionMatrix * context.viewMatrix.rotationOnlyView
            let postPasses = plan.postPasses.compactMap { postPass in
                makePostPass(postPass, shadowFrame: shadowFrame, ambientOcclusionApply: ambientOcclusionApply, postProcessing: postProcessing, postTargets: postTargets, relativeViewProjection: relativeViewProjection, autoExposureBuffer: autoExposureBuffer)?
                    .gpuTimed(postPass.gpuTimingLabel)
                    .eraseToAnyElement()
            }
            // The shadow and post passes open their own encoders, so they are siblings of the scene pass.
            return try MetalSprockets.Group {
                if let shadowFrame {
                    ShadowCasterDepthPass(frame: shadowFrame)
                        .gpuTimed(SceneGPUTimingLabel.shadowCasters)
                }
                ForEach(Array(prePasses.enumerated()), id: \.offset) { _, prePass in
                    prePass
                }
                .gpuTimed(SceneGPUTimingLabel.prePasses)
                scenePass
                    .gpuTimed(SceneGPUTimingLabel.scene)
                ForEach(Array(postPasses.enumerated()), id: \.offset) { _, postPass in
                    postPass
                }
            }
            .eraseToAnyElement()
        }
    }

    // Ambient occlusion from a depth pre-pass, before shading, so in-shader materials darken only their ambient light
    // (#136). Sets the context's visibility texture; returns the pass that applies it to the other materials.
    private func makeAmbientOcclusionPasses(settings: SceneGraph.AmbientOcclusion, content: AnyElement, inShaderContent: AnyElement?, splitsInShader: Bool, appliesAsPostPass: Bool, postTargets: (color: MTLTexture, depth: MTLTexture), context: inout RenderContext, prePasses: inout [AnyElement]) throws -> ApplyAmbientOcclusionPass? {
        let targets = try AmbientOcclusionTargets.targets(device: postTargets.color.device, width: postTargets.color.width, height: postTargets.color.height, colorFormat: postTargets.color.pixelFormat, depthFormat: postTargets.depth.pixelFormat)
        let relativeViewProjection = context.projectionMatrix * context.viewMatrix.rotationOnlyView
        prePasses.append(AmbientOcclusionDepthPass(label: "Ambient Occlusion Depth", depth: targets.depth, scratchColor: targets.scratchColor, content: content).eraseToAnyElement())
        if let inShaderContent {
            prePasses.append(AmbientOcclusionDepthPass(label: "Ambient Occlusion In-Shader Depth", depth: targets.inShaderDepth, scratchColor: targets.scratchColor, content: inShaderContent).eraseToAnyElement())
        }
        prePasses.append(AmbientOcclusionPass(settings: settings, depthTexture: targets.depth, visibilityTexture: targets.visibility, viewProjection: relativeViewProjection, cameraPosition: .zero).eraseToAnyElement())
        context.ambientOcclusion = targets.visibility
        guard appliesAsPostPass else {
            return nil
        }
        return ApplyAmbientOcclusionPass(visibilityTexture: targets.visibility, depthTexture: targets.depth, inShaderDepthTexture: splitsInShader ? targets.inShaderDepth : nil, colorTexture: postTargets.color)
    }

    // Passes that renderers need before the scene pass, such as what is behind glass.
    private func makeRendererPrePasses(entries: [SceneGraph.MeshEntry], context: RenderContext) throws -> [AnyElement] {
        guard let color = renderPassDescriptor?.colorAttachments[0].texture else {
            return []
        }
        var prePasses: [AnyElement] = []
        for (renderer, rendererEntries) in zip(renderers, partitionMeshEntries(entries, renderers: renderers)) {
            guard let prePassRenderer = renderer as? any PrePassRenderer, !rendererEntries.isEmpty else {
                continue
            }
            let materialType = renderer.materialType
            if let prePass = try prePassRenderer.makePrePassElement(entries: rendererEntries, context: context, viewSize: (color.width, color.height), otherOpaqueContent: {
                var linearContext = context
                linearContext.outputIsLinear = true
                return try makeOpaqueContent(entries: entries, context: linearContext, excluding: materialType)
            }) {
                prePasses.append(prePass)
            }
        }
        return prePasses
    }

    // The scene pass's content before particles: background, mesh batches, decorations and node text.
    private func makeSceneElements(entries: [SceneGraph.MeshEntry], context: RenderContext, drawsText: Bool) throws -> [AnyElement] {
        var elements: [AnyElement] = []
        switch context.environment.background {
        case let .gradient(gradient):
            elements.append(SkyGradientBackground(gradient: gradient, viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, stereoViews: context.stereoViews).eraseToAnyElement())
        case .environment:
            for case let renderer as any BackgroundRenderer in renderers {
                if let background = try renderer.makeBackgroundElement(context: context) {
                    elements.append(background)
                    break
                }
            }
        default:
            break
        }
        // One batch per rendering order and set of affecting lights; each renderer draws its part of each batch.
        for batch in renderBatches(entries, context: context) {
            let partitions = partitionMeshEntries(batch.entries, renderers: renderers)
            elements += try zip(renderers, partitions).compactMap { renderer, entries in
                entries.isEmpty ? nil : try renderer.makeElement(entries: entries, context: batch.context)
            }
        }
        // Editor aids such as grids and axes: in the scene pass after the meshes, so they depth-test against them.
        if let decorations, let decoration = try decorations(context) {
            elements.append(decoration)
        }
        #if arch(arm64)
        // Node text (#119): after the meshes, depth-tested against them.
        if drawsText, let color = renderPassDescriptor?.colorAttachments[0].texture {
            let texts = presentation.texts.filter { $0.categoryBitMask & context.categoryBitMask != 0 }.map { ($0.text, $0.worldTransform) }
            elements += try Self.makeTextElements(texts, context: context, viewportSize: [Float(color.width), Float(color.height)], device: color.device)
        }
        #endif
        return elements
    }

    private func makePostPass(_ postPass: SceneFramePlan.PostPass, shadowFrame: Shadows.Frame?, ambientOcclusionApply: ApplyAmbientOcclusionPass?, postProcessing: SceneGraph.PostProcessing?, postTargets: (color: MTLTexture, depth: MTLTexture), relativeViewProjection: simd_float4x4, autoExposureBuffer: MTLBuffer?) -> AnyElement? {
        switch postPass {
        case .shadowMask:
            guard let shadows, let shadowFrame else {
                return nil
            }
            return SceneShadowMaskPass(frame: shadowFrame, sceneDepthTexture: postTargets.depth, outputTexture: postTargets.color, viewProjection: relativeViewProjection, intensity: shadows.intensity, color: shadows.color, radius: shadows.softness).eraseToAnyElement()
        case .ambientOcclusion:
            return ambientOcclusionApply?.eraseToAnyElement()
        case .fog:
            guard let fog = presentation.fog else {
                return nil
            }
            return FogPass(fog: fog, depthTexture: postTargets.depth, colorTexture: postTargets.color, inverseViewProjection: relativeViewProjection.inverse, cameraPosition: .zero).eraseToAnyElement()
        case .colorAdjust:
            return postProcessing.map { ColorAdjustPass(settings: $0, colorTexture: postTargets.color).eraseToAnyElement() }
        case .autoExposure:
            return autoExposureBuffer.map { AutoExposurePass(colorTexture: postTargets.color, depthTexture: postTargets.depth, buffer: $0).eraseToAnyElement() }
        }
    }

    // Batches of every renderer except the one for `excluding`, in draw order, with reversed depth. Transparent and
    // faded entries are included, so glass still shows a scene that is fading (#327).
    private func makeOpaqueContent(entries: [SceneGraph.MeshEntry], context: RenderContext, excluding: (any SceneMaterial.Type)?) throws -> AnyElement? {
        var elements: [AnyElement] = []
        for batch in renderBatches(entries, context: context) {
            let partitions = partitionMeshEntries(batch.entries, renderers: renderers)
            for (renderer, entries) in zip(renderers, partitions) where !entries.isEmpty && ObjectIdentifier(renderer.materialType) != excluding.map(ObjectIdentifier.init) {
                elements.append(try renderer.makeElement(entries: entries, context: batch.context))
            }
        }
        guard !elements.isEmpty else {
            return nil
        }
        return ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
            element
        }
        .depthCompare(function: .greater, writes: true)
        .eraseToAnyElement()
    }

    // Draws soft particles over the finished scene pass: loads its color and depth.
    private func makeParticlePass(elements: [AnyElement], storesDepth: Bool) throws -> some Element {
        try RenderPass(label: "Soft Particles") {
            // Wait for the depth copy.
            QueueBarrier(after: .dispatch, before: .fragment)
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                element
            }
        }
        .renderPassDescriptorModifier { descriptor in
            descriptor.colorAttachments[0].loadAction = .load
            descriptor.depthAttachment.loadAction = .load
            descriptor.depthAttachment.storeAction = storesDepth ? .store : .dontCare
        }
    }

    private func makeScenePass(elements: [AnyElement], clearColor: MTLClearColor?, storesDepth: Bool) throws -> AnyElement {
        #if os(visionOS)
        if let immersiveContext {
            // The compositor's pass: progressive immersion's stencil mask, and the compositor ends the encoder.
            return ImmersiveRenderPass(context: immersiveContext, label: "Scene") {
                ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                    element
                }
            }
            .depthCompare(function: .greater, writes: true)
            .renderPassDescriptorModifier { descriptor in
                if let clearColor {
                    descriptor.colorAttachments[0].clearColor = clearColor
                    descriptor.colorAttachments[0].loadAction = .clear
                }
            }
            .eraseToAnyElement()
        }
        #endif
        // The view's depth, where a multisampled pass resolves its depth for the passes that read it.
        let resolvedDepth = renderPassDescriptor?.depthAttachment.texture
        let sampleCount = self.sampleCount
        // Reversed depth (near 1, far 0) for every renderer, because MetalSprocketsPBR requires it.
        return try RenderPass {
            if storesDepth {
                // The view's depth texture is shared by every frame in flight, and Metal 4 does not track hazards:
                // without this, the previous frame's shadow mask pass can still be reading depth while this pass
                // clears it, and that frame's shadow disappears. The previous frame's render passes after the scene
                // (selection outline, manipulator) use the same depth attachment in the fragment stage, so wait for
                // those too (#214).
                QueueBarrier(after: [.dispatch, .fragment], before: [.vertex, .fragment])
            }
            ForEach(Array(elements.enumerated()), id: \.offset) { _, element in
                element
            }
        }
        .depthCompare(function: .greater, writes: true)
        .renderPassDescriptorModifier { descriptor in
            descriptor.depthAttachment.clearDepth = 0
            // The shadow mask pass reads depth afterwards. Memoryless depth (the default) cannot be stored.
            if storesDepth {
                if sampleCount > 1, let resolvedDepth {
                    // Reversed depth: the nearest sample is the largest.
                    descriptor.depthAttachment.resolveTexture = resolvedDepth
                    descriptor.depthAttachment.depthResolveFilter = .max
                    descriptor.depthAttachment.storeAction = .multisampleResolve
                } else {
                    descriptor.depthAttachment.storeAction = .store
                }
            }
            if let clearColor {
                descriptor.colorAttachments[0].clearColor = clearColor
                descriptor.colorAttachments[0].loadAction = .clear
            }
        }
        .msaa(sampleCount: sampleCount)
        .eraseToAnyElement()
    }
}

func makeRenderContext(sceneGraph: SceneGraph, camera: SceneGraph.Node?, cameraMatrix: simd_float4x4?, aspectRatio: Float, defaultCamera: Camera? = nil, cameraOverride: Camera? = nil, defaultLight: Light? = nil, stereoViews: StereoViews? = nil) -> RenderContext? {
    makeRenderContext(presentation: sceneGraph.presentation(), cameraID: camera?.id, cameraMatrix: cameraMatrix, aspectRatio: aspectRatio, defaultCamera: defaultCamera, cameraOverride: cameraOverride, defaultLight: defaultLight, stereoViews: stereoViews)
}

func makeRenderContext(presentation: SceneGraph.Presentation, cameraID: SceneGraph.Node.ID?, cameraMatrix: simd_float4x4?, aspectRatio: Float, defaultCamera: Camera? = nil, cameraOverride: Camera? = nil, defaultLight: Light? = nil, stereoViews: StereoViews? = nil) -> RenderContext? {
    let cameras = presentation.cameras
    let entry = cameraID.map { id in cameras.first { $0.nodeID == id } } ?? cameras.first
    let resolved: (camera: Camera, worldTransform: simd_float4x4)
    if let cameraOverride {
        resolved = (cameraOverride, cameraMatrix ?? entry?.worldTransform ?? .identity)
    } else if let entry {
        resolved = (entry.camera, cameraMatrix ?? entry.worldTransform)
    } else if let defaultCamera {
        resolved = (defaultCamera, cameraMatrix ?? .identity)
    } else {
        return nil
    }
    let cameraMatrix = stereoViews?.centerCameraMatrix ?? resolved.worldTransform
    var lights = presentation.lights.map { (worldTransform: $0.worldTransform, light: $0.light) }
    var lightMasks = presentation.lights.map(\.lightCategoryBitMask)
    if lights.isEmpty, let defaultLight {
        lights = [(cameraMatrix, defaultLight)]
        lightMasks = [.max]
    }
    var context = RenderContext(
        viewMatrix: cameraMatrix.inverse,
        projectionMatrix: stereoViews?.projectionMatrices[0] ?? .reverseZ * resolved.camera.projection.projectionMatrix(aspectRatio: aspectRatio),
        cameraMatrix: cameraMatrix,
        lights: lights,
        revision: presentation.revision,
        environment: presentation.environment,
        categoryBitMask: resolved.camera.categoryBitMask,
        lightCategoryBitMasks: lightMasks
    )
    context.stereoViews = stereoViews
    return context
}

/// Splits mesh entries into the batches that ``SceneGraphElement`` draws, each with the context for that batch.
///
/// For custom elements that draw a scene with ``MaterialRenderer`` types. Entries are grouped by
/// `renderingOrder` (ascending), then opaque before transparent, then by the lights whose category masks match,
/// keeping first-seen order. Transparent entries are sorted farthest first. Each batch's context holds only its
/// lights.
///
/// - Parameters:
///   - entries: The mesh entries to draw.
///   - context: The frame's context.
/// - Returns: The batches in draw order.
public func renderBatches(_ entries: [SceneGraph.MeshEntry], context: RenderContext) -> [(entries: [SceneGraph.MeshEntry], context: RenderContext)] {
    struct Key: Hashable {
        var order: Int
        var isTransparent: Bool
        var lights: [Int]
    }
    var keys: [Key] = []
    var groups: [Key: [SceneGraph.MeshEntry]] = [:]
    for entry in entries {
        // Lights without a mask light everything.
        let lights = context.lights.indices.filter { index in
            let mask = index < context.lightCategoryBitMasks.count ? context.lightCategoryBitMasks[index] : .max
            return mask & entry.categoryBitMask != 0
        }
        let key = Key(order: entry.renderingOrder, isTransparent: entry.isTransparent, lights: lights)
        if groups[key] == nil {
            keys.append(key)
        }
        groups[key, default: []].append(entry)
    }
    let cameraPosition = context.cameraMatrix.columns.3.xyz
    for key in keys where key.isTransparent {
        groups[key] = sortedBackToFront(groups[key] ?? [], cameraPosition: cameraPosition)
    }
    let allLights = Array(context.lights.indices)
    return keys
        .enumerated()
        .sorted {
            ($0.element.order, $0.element.isTransparent ? 1 : 0, $0.offset) < ($1.element.order, $1.element.isTransparent ? 1 : 0, $1.offset)
        }
        .map { _, key in
            var batchContext = context
            if key.lights != allLights {
                batchContext.lights = key.lights.map { context.lights[$0] }
                batchContext.lightCategoryBitMasks = key.lights.map { $0 < context.lightCategoryBitMasks.count ? context.lightCategoryBitMasks[$0] : .max }
                if !context.lightShadowSlices.isEmpty {
                    batchContext.lightShadowSlices = key.lights.map { $0 < context.lightShadowSlices.count ? context.lightShadowSlices[$0] : 0..<0 }
                }
            }
            return (groups[key] ?? [], batchContext)
        }
}

// Returns one array per renderer, in renderer order.
func partitionMeshEntries(_ entries: [SceneGraph.MeshEntry], renderers: [any MaterialRenderer]) -> [[SceneGraph.MeshEntry]] {
    var indexByType: [ObjectIdentifier: Int] = [:]
    for (index, renderer) in renderers.enumerated() {
        indexByType[ObjectIdentifier(renderer.materialType)] = index
    }
    var partitions = Array(repeating: [SceneGraph.MeshEntry](), count: renderers.count)
    for entry in entries {
        let materialType = type(of: entry.material)
        if let index = indexByType[ObjectIdentifier(materialType)] {
            partitions[index].append(entry)
        } else {
            MissingRendererWarning.report(materialType)
        }
    }
    return partitions
}

// Logs once per material type that a mesh was skipped because no renderer draws its material (#369).
enum MissingRendererWarning {
    private static let logger = Logger(subsystem: "io.schwa.SceneSprockets", category: "Rendering")
    private static let reported = Mutex<Set<ObjectIdentifier>>([])

    static func report(_ materialType: any SceneMaterial.Type) {
        let isNew = reported.withLock { $0.insert(ObjectIdentifier(materialType)).inserted }
        if isNew {
            logger.warning("No renderer for \(String(describing: materialType), privacy: .public): meshes with this material are not drawn. Add its renderer to the view's renderers.")
        }
    }

    static func hasReported(_ materialType: any SceneMaterial.Type) -> Bool {
        reported.withLock { $0.contains(ObjectIdentifier(materialType)) }
    }
}

extension Element {
    /// Binds vertex buffers at their indices.
    public func vertexBuffers(_ buffers: [Int: MTLBuffer]) -> some Element {
        buffers.sorted { $0.key < $1.key }.reduce(AnyElement(self)) { element, entry in
            AnyElement(element.vertexBuffer(entry.value, index: entry.key))
        }
    }
}

/// Groups entries by vertex descriptor, keeping first-seen order.
package func groupedByVertexDescriptor<Entry>(_ entries: [Entry], vertexDescriptor: (Entry) -> VertexDescriptor) -> [(vertexDescriptor: VertexDescriptor, entries: [Entry])] {
    var groups: [(vertexDescriptor: VertexDescriptor, entries: [Entry])] = []
    for entry in entries {
        let descriptor = vertexDescriptor(entry)
        if let index = groups.firstIndex(where: { $0.vertexDescriptor == descriptor }) {
            groups[index].entries.append(entry)
        } else {
            groups.append((descriptor, [entry]))
        }
    }
    return groups
}
