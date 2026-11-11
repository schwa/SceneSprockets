import GeometryLite3D
import Metal
import MetalSprockets
import MetalSupport
import simd

/// The camera, lights and settings of one frame, that ``SceneGraphElement`` gives each material renderer.
public struct SceneGraphRenderContext {
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
    public internal(set) var shadow: SceneGraphShadows.Sampling?
    /// Parallel to `lights` when `shadow` is set: each light's shadow map slices (empty for none).
    public internal(set) var lightShadowSlices: [Range<Int>] = []
    /// When set, renderers output this material value instead of lighting (#195).
    public internal(set) var materialChannel: SceneGraphMaterialChannel?
}

/// A renderer for one material family.
///
/// To add a material family, write a type that conforms to this protocol. The scene graph does not change.
public protocol SceneGraphMaterialRenderer {
    /// The material type that the renderer draws.
    var materialType: any SceneSprockets.Material.Type { get }
    /// Returns an element that draws mesh entries whose material is ``materialType``.
    ///
    /// The element draws inside the scene's render pass. ``SceneGraphElement`` can call this method several times in
    /// a frame, for batches with different lights or rendering order.
    ///
    /// - Parameters:
    ///   - entries: The mesh entries to draw.
    ///   - context: The camera, lights and settings of the frame.
    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement
}

/// A renderer that can draw `SceneGraph.Environment.Background.environment`. The element asks each one in order and
/// draws the first non-nil result before any meshes, even when the renderer has no entries.
public protocol SceneGraphBackgroundRenderer {
    /// Returns an element that draws the environment background, or `nil` if this renderer cannot draw it.
    func makeBackgroundElement(context: SceneGraphRenderContext) throws -> AnyElement?
}

/// A renderer that needs its own passes before the scene pass, such as one that draws what is behind glass.
/// `entries` are all of this renderer's entries; `makeElement` is called after this for each batch.
/// `otherOpaqueContent` makes the other renderers' opaque batches, for a pass that needs the rest of the scene; nil
/// when there are none.
public protocol SceneGraphPrePassRenderer {
    func makePrePassElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext, viewSize: (width: Int, height: Int), otherOpaqueContent: () throws -> AnyElement?) throws -> AnyElement?
}

/// Renders every mesh entry in one pass by handing each material family to its renderer.
/// Entries whose material type has no renderer are skipped.
/// The view comes from `camera` (default: the first camera node) unless `cameraMatrix` overrides its world transform.
/// With no camera node, `defaultCamera` is used at `cameraMatrix` (identity if nil).
/// `cameraOverride` replaces the camera node's camera (projection and masks) even when there is one, for editor cameras.
/// `defaultLight` is added at the camera when the scene has no lights, like SceneKit's autoenablesDefaultLighting.
public struct SceneGraphElement: Element {
    var sceneGraph: SceneGraph
    var camera: SceneGraph.Node?
    var cameraMatrix: simd_float4x4?
    var aspectRatio: Float
    var renderers: [any SceneGraphMaterialRenderer]
    var defaultCamera: Camera?
    var cameraOverride: Camera?
    // Keep the scene depth for later passes (it must not be memoryless), such as depth-tested overlays.
    var storesDepth: Bool
    var defaultLight: Light?
    var shadows: SceneGraphShadows?
    var decorations: ((SceneGraphRenderContext) throws -> AnyElement?)?
    // Draws every mesh in this debug view instead of its material (#132).
    var debugMode: SceneGraphDebugMode?
    // Each renderer shows this material value instead of lighting (#195). Ignored while debugMode is set.
    var materialChannel: SceneGraphMaterialChannel?

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
    public init(sceneGraph: SceneGraph, camera: SceneGraph.Node? = nil, cameraMatrix: simd_float4x4? = nil, aspectRatio: Float, renderers: [any SceneGraphMaterialRenderer], defaultCamera: Camera? = nil, cameraOverride: Camera? = nil, defaultLight: Light? = nil, shadows: SceneGraphShadows? = nil, storesDepth: Bool = false, decorations: ((SceneGraphRenderContext) throws -> AnyElement?)? = nil, debugMode: SceneGraphDebugMode? = nil, materialChannel: SceneGraphMaterialChannel? = nil) {
        self.debugMode = debugMode
        self.materialChannel = materialChannel
        self.cameraOverride = cameraOverride
        self.storesDepth = storesDepth
        self.decorations = decorations
        self.sceneGraph = sceneGraph
        self.camera = camera
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
            guard var context = makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: cameraMatrix, aspectRatio: aspectRatio, defaultCamera: defaultCamera, cameraOverride: cameraOverride, defaultLight: defaultLight) else {
                return EmptyElement().eraseToAnyElement()
            }
            let cameraPosition = context.cameraMatrix.columns.3.xyz
            context.materialChannel = debugMode == nil ? materialChannel : nil
            var entries = applyLevelsOfDetail(sceneGraph.meshEntries().filter { $0.node.categoryBitMask & context.categoryBitMask != 0 }, cameraPosition: cameraPosition)
            if let debugMode {
                entries = entries.map { entry in
                    var entry = entry
                    entry.material = SceneGraphDebugMaterial(mode: debugMode)
                    return entry
                }
            }
            // The shadow mask and fog passes read and write the view's textures, so they need the right usage.
            let postTargets: (color: MTLTexture, depth: MTLTexture)? = {
                guard let color = renderPassDescriptor?.colorAttachments[0].texture, let depth = renderPassDescriptor?.depthAttachment.texture,
                      color.usage.isSuperset(of: SceneGraphShadows.requiredColorUsage), depth.usage.isSuperset(of: SceneGraphShadows.requiredDepthUsage),
                      depth.storageMode != .memoryless
                else {
                    return nil
                }
                return (color, depth)
            }()
            // Prepared before the renderers, which sample it while shading.
            let shadowFrame = try postTargets.flatMap { targets in
                try shadows?.prepare(entries: entries, context: context, bounds: sceneGraph.bounds, viewSize: (targets.color.width, targets.color.height))
            }
            if let shadows, let shadowFrame {
                context.shadow = SceneGraphShadows.Sampling(shadowMap: shadowFrame.shadowMap, intensity: shadows.intensity, color: shadows.color, softness: shadows.softness)
                context.lightShadowSlices = shadowFrame.lightSlices
            }
            var prePasses: [AnyElement] = []
            // Morphs and skins on the GPU for renderers that draw plain vertex buffers (#298). The renderers below pick
            // up the results from the nodes.
            let deformationJobs = GPUDeformation.prepare(entries: entries, revision: context.revision, submissionIndex: submissionIndex)
            if !deformationJobs.isEmpty {
                prePasses.append(DeformationPass(jobs: deformationJobs).eraseToAnyElement())
            }
            if let color = renderPassDescriptor?.colorAttachments[0].texture {
                for (renderer, rendererEntries) in zip(renderers, partitionMeshEntries(entries, renderers: renderers)) {
                    guard let prePassRenderer = renderer as? any SceneGraphPrePassRenderer, !rendererEntries.isEmpty else {
                        continue
                    }
                    let frameContext = context
                    let materialType = renderer.materialType
                    if let prePass = try prePassRenderer.makePrePassElement(entries: rendererEntries, context: frameContext, viewSize: (color.width, color.height), otherOpaqueContent: {
                        try makeOpaqueContent(entries: entries, context: frameContext, excluding: materialType)
                    }) {
                        prePasses.append(prePass)
                    }
                }
            }
            var elements: [AnyElement] = []
            if case let .gradient(gradient) = context.environment.background {
                elements.append(SkyGradientBackground(gradient: gradient, viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix).eraseToAnyElement())
            }
            if case .environment = context.environment.background {
                for case let renderer as any SceneGraphBackgroundRenderer in renderers {
                    if let background = try renderer.makeBackgroundElement(context: context) {
                        elements.append(background)
                        break
                    }
                }
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
            // Particles simulate in their own compute pass before the scene pass, then draw after the meshes.
            let particleSimulations = try sceneGraph.allParticleSystems().map { try $0.simulate(view: context.viewMatrix).eraseToAnyElement() }
            prePasses = particleSimulations + prePasses
            let visibleParticleSystems = sceneGraph.visibleParticleSystems()
            // Soft particles read the scene's depth, so they draw in a second pass after a depth copy. That needs depth
            // that can be stored and read, and no MSAA resolve (the second pass would have to reload the samples).
            let softParticleDepth: (scene: MTLTexture, copy: MTLTexture)? = try {
                guard let postTargets, visibleParticleSystems.contains(where: \.isSoft), renderPassDescriptor?.colorAttachments[0].resolveTexture == nil else {
                    return nil
                }
                let copy = try ParticleDepthShaders.sceneDepthTexture(device: postTargets.depth.device, width: postTargets.depth.width, height: postTargets.depth.height)
                return (postTargets.depth, copy)
            }()
            var particleElements: [AnyElement] = []
            for system in visibleParticleSystems {
                // Sprite draws inherit the scene pass's depth state, which writes depth; blended sprites must not.
                particleElements.append(try system.runtime().render(projection: context.projectionMatrix, view: context.viewMatrix, sceneDepth: softParticleDepth?.copy).depthCompare(function: .greater, writes: false).eraseToAnyElement())
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
            let fog = postTargets == nil ? nil : sceneGraph.fog
            let postProcessing = postTargets == nil ? nil : sceneGraph.postProcessing
            let ambientOcclusion = postProcessing?.ambientOcclusion
            let adjustsColor = postProcessing?.adjustsColor ?? false
            let hasPostPasses = shadowFrame != nil || fog != nil || ambientOcclusion != nil || adjustsColor
            let scenePass = try MetalSprockets.Group {
                try makeScenePass(elements: elements, clearColor: clearColor, storesDepth: storesDepth || hasPostPasses || softParticleDepth != nil)
                if let softParticleDepth {
                    ParticleDepthCopyPass(depthTexture: softParticleDepth.scene, output: softParticleDepth.copy)
                    try makeParticlePass(elements: particleElements, storesDepth: storesDepth || hasPostPasses)
                }
            }
            guard let postTargets, hasPostPasses else {
                if prePasses.isEmpty {
                    return scenePass.eraseToAnyElement()
                }
                return try MetalSprockets.Group {
                    ForEach(Array(prePasses.enumerated()), id: \.offset) { _, prePass in
                        prePass
                    }
                    scenePass
                }
                .eraseToAnyElement()
            }
            // Post passes rebuild positions from depth in camera-relative space (camera at the origin), so they stay
            // precise far from the world origin (#257). Shadow views are camera-relative too.
            let relativeViewProjection = context.projectionMatrix * context.viewMatrix.rotationOnlyView
            // The shadow and post passes open their own encoders, so they are siblings of the scene pass.
            return try MetalSprockets.Group {
                if let shadowFrame {
                    ShadowCasterDepthPass(frame: shadowFrame)
                }
                ForEach(Array(prePasses.enumerated()), id: \.offset) { _, prePass in
                    prePass
                }
                scenePass
                if let shadows, let shadowFrame, !shadowFrame.masksEverything {
                    SceneShadowMaskPass(
                        frame: shadowFrame,
                        sceneDepthTexture: postTargets.depth,
                        outputTexture: postTargets.color,
                        viewProjection: relativeViewProjection,
                        intensity: shadows.intensity,
                        color: shadows.color,
                        radius: shadows.softness
                    )
                }
                // Occlusion darkens geometry before fog covers it; color adjustment comes last.
                if let ambientOcclusion {
                    AmbientOcclusionPass(settings: ambientOcclusion, depthTexture: postTargets.depth, colorTexture: postTargets.color, viewProjection: relativeViewProjection, cameraPosition: .zero)
                }
                if let fog {
                    FogPass(fog: fog, depthTexture: postTargets.depth, colorTexture: postTargets.color, inverseViewProjection: relativeViewProjection.inverse, cameraPosition: .zero)
                }
                if let postProcessing, adjustsColor {
                    ColorAdjustPass(settings: postProcessing, colorTexture: postTargets.color)
                }
            }
            .eraseToAnyElement()
        }
    }

    // Opaque batches of every renderer except the one for `excluding`, with reversed depth.
    private func makeOpaqueContent(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext, excluding: any SceneSprockets.Material.Type) throws -> AnyElement? {
        var elements: [AnyElement] = []
        for batch in renderBatches(entries.filter { !$0.isTransparent }, context: context) {
            let partitions = partitionMeshEntries(batch.entries, renderers: renderers)
            for (renderer, entries) in zip(renderers, partitions) where !entries.isEmpty && ObjectIdentifier(renderer.materialType) != ObjectIdentifier(excluding) {
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

    private func makeScenePass(elements: [AnyElement], clearColor: MTLClearColor?, storesDepth: Bool) throws -> some Element {
        // Reversed depth (near 1, far 0) for every renderer, because MetalSprocketsPBR requires it.
        try RenderPass {
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
                descriptor.depthAttachment.storeAction = .store
            }
            if let clearColor {
                descriptor.colorAttachments[0].clearColor = clearColor
                descriptor.colorAttachments[0].loadAction = .clear
            }
        }
    }
}

func makeRenderContext(sceneGraph: SceneGraph, camera: SceneGraph.Node?, cameraMatrix: simd_float4x4?, aspectRatio: Float, defaultCamera: Camera? = nil, cameraOverride: Camera? = nil, defaultLight: Light? = nil) -> SceneGraphRenderContext? {
    let cameras = sceneGraph.cameraNodes()
    let entry = camera.map { camera in cameras.first { $0.node === camera } } ?? cameras.first
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
    let cameraMatrix = resolved.worldTransform
    let lightNodes = sceneGraph.lightNodes()
    var lights = lightNodes.map { (worldTransform: $0.worldTransform, light: $0.light) }
    var lightMasks = lightNodes.map(\.node.lightCategoryBitMask)
    if lights.isEmpty, let defaultLight {
        lights = [(cameraMatrix, defaultLight)]
        lightMasks = [.max]
    }
    return SceneGraphRenderContext(
        viewMatrix: cameraMatrix.inverse,
        projectionMatrix: .reverseZ * resolved.camera.projection.projectionMatrix(aspectRatio: aspectRatio),
        cameraMatrix: cameraMatrix,
        lights: lights,
        revision: sceneGraph.revision,
        environment: sceneGraph.environment,
        categoryBitMask: resolved.camera.categoryBitMask,
        lightCategoryBitMasks: lightMasks
    )
}

/// Groups entries by rendering order (ascending), then opaque before transparent, then by the lights whose masks
/// match, keeping first-seen order. Transparent entries are sorted farthest first. Each batch's context holds only
/// its lights.
public func renderBatches(_ entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) -> [(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext)] {
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
            return mask & entry.node.categoryBitMask != 0
        }
        let key = Key(order: entry.node.renderingOrder, isTransparent: entry.isTransparent, lights: lights)
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
func partitionMeshEntries(_ entries: [SceneGraph.MeshEntry], renderers: [any SceneGraphMaterialRenderer]) -> [[SceneGraph.MeshEntry]] {
    var indexByType: [ObjectIdentifier: Int] = [:]
    for (index, renderer) in renderers.enumerated() {
        indexByType[ObjectIdentifier(renderer.materialType)] = index
    }
    var partitions = Array(repeating: [SceneGraph.MeshEntry](), count: renderers.count)
    for entry in entries {
        if let index = indexByType[ObjectIdentifier(type(of: entry.material))] {
            partitions[index].append(entry)
        }
    }
    return partitions
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
public func groupedByVertexDescriptor<Entry>(_ entries: [Entry], vertexDescriptor: (Entry) -> VertexDescriptor) -> [(vertexDescriptor: VertexDescriptor, entries: [Entry])] {
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
