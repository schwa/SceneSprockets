import Foundation
import Metal
import MetalSprockets
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import SceneSprockets
import simd
import SwiftMesh

/// A physically based material for scene graph meshes.
///
/// The material wraps a MetalSprocketsPBR `PBRMaterial`: metallic-roughness with most glTF material extensions. A
/// ``PBRMaterialRenderer`` draws it.
///
/// It is a class, like SceneKit's `SCNMaterial`: nodes that use the same instance share it, and a change shows on all
/// of them (#375).
///
/// You can change the material on one thread while a view draws it on its render thread (#479). `PBRMaterial` is
/// immutable, so a change replaces it with a copy; the change shows on the next frame.
public final class PBRSceneMaterial: SceneMaterial, SamplesShadowsInShader, @unchecked Sendable {
    private let lock = NSLock()
    private var storedMaterial: PBRMaterial

    /// The MetalSprocketsPBR material.
    public var pbrMaterial: PBRMaterial {
        get { lock.withLock { storedMaterial } }
        set { lock.withLock { storedMaterial = newValue } }
    }

    /// Creates a scene material that wraps a PBR material.
    public init(_ pbrMaterial: PBRMaterial) {
        storedMaterial = pbrMaterial
    }

    /// The material's shader uniforms. Stored on ``pbrMaterial``.
    public var uniforms: PBRMaterialUniforms {
        get { pbrMaterial.uniforms }
        set { update { $0.with(uniforms: newValue) } }
    }

    /// Texture transforms, keyed by the producer's name for the texture. Stored on ``pbrMaterial``.
    public var textureTransforms: [String: PBRMaterial.TextureTransform] {
        get { pbrMaterial.textureTransforms }
        set { update { $0.with(textureTransforms: newValue) } }
    }

    private func update(_ change: (PBRMaterial) -> PBRMaterial) {
        lock.withLock { storedMaterial = change(storedMaterial) }
    }

    public var isTransparent: Bool {
        pbrMaterial.isBlended
    }

    public var appliesNodeOpacity: Bool {
        true
    }

    /// The blend mode, depth test and write, color write mask and fill mode. Stored on ``pbrMaterial``.
    public var renderState: PBRRenderState {
        get { pbrMaterial.renderState }
        set { update { $0.with(renderState: newValue) } }
    }

    // A blended copy of `material` with base color alpha scaled by `opacity`. Masked materials lose their cutoff while
    // fading.
    static func faded(_ material: PBRMaterial, opacity: Float) -> PBRMaterial {
        var uniforms = material.uniforms
        uniforms.alphaMode = .blend
        uniforms.baseColorFactor.w *= opacity
        return material.with(uniforms: uniforms)
    }

    /// Creates a material without textures.
    ///
    /// Traps if Metal cannot allocate the material's small uniform buffer.
    ///
    /// - Parameters:
    ///   - baseColor: The base color in linear RGB.
    ///   - opacity: The base color's alpha, from 0 to 1.
    ///   - metallic: The metalness, from 0 (dielectric) to 1 (metal).
    ///   - roughness: The roughness, from 0 (smooth) to 1 (rough).
    public init(baseColor: SIMD3<Float> = [1, 1, 1], opacity: Float = 1, metallic: Float = 0, roughness: Float = 0.5) {
        let device = _MTLCreateSystemDefaultDevice()
        var uniforms = PBRMaterialUniforms.defaults(baseColor: SIMD4(baseColor, opacity), metallic: metallic, roughness: roughness)
        // Opaque materials ignore alpha, so opacity below 1 blends, as it does for Blinn-Phong (#409).
        if opacity < 1 {
            uniforms.alphaMode = .blend
        }
        do {
            storedMaterial = try PBRMaterial(uniforms: uniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
        } catch {
            fatalError("Could not create a PBR material: \(error)")
        }
    }

    /// The common glTF texture slots. `MaterialTexture` loads textures from images.
    public struct Textures {
        /// Base color in sRGB, multiplied by the base color factor. Alpha is opacity.
        public var baseColor: MTLTexture?
        /// Roughness in green and metalness in blue, multiplied by the roughness and metallic factors.
        public var metallicRoughness: MTLTexture?
        /// A tangent-space normal map.
        public var normal: MTLTexture?
        /// Ambient occlusion in red.
        public var occlusion: MTLTexture?
        /// Emitted light in sRGB.
        public var emissive: MTLTexture?

        /// Creates a set of textures. Slots left `nil` use the material's factors only.
        public init(baseColor: MTLTexture? = nil, metallicRoughness: MTLTexture? = nil, normal: MTLTexture? = nil, occlusion: MTLTexture? = nil, emissive: MTLTexture? = nil) {
            self.baseColor = baseColor
            self.metallicRoughness = metallicRoughness
            self.normal = normal
            self.occlusion = occlusion
            self.emissive = emissive
        }
    }

    /// Creates a material with textures.
    ///
    /// - Parameters:
    ///   - baseColor: The base color factor in linear RGB. It multiplies the base color texture.
    ///   - opacity: The opacity, from 0 to 1. It multiplies the base color texture's alpha.
    ///   - metallic: The metalness factor.
    ///   - roughness: The roughness factor.
    ///   - textures: The textures. An emissive texture sets the emissive factor to 1.
    ///   - sampler: The sampler for every texture, or `nil` for linear filtering with repeat.
    /// - Throws: An error if a texture cannot be bound with the sampler.
    public init(baseColor: SIMD3<Float> = [1, 1, 1], opacity: Float = 1, metallic: Float = 0, roughness: Float = 0.5, textures: Textures, sampler: MTLSamplerDescriptor? = nil) throws {
        let device = _MTLCreateSystemDefaultDevice()
        var uniforms = PBRMaterialUniforms.defaults(baseColor: SIMD4(baseColor, opacity), metallic: metallic, roughness: roughness)
        let placeholder = try PBRMaterial.placeholderBinding(device: device)
        var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
        let slots: [(MTLTexture?, PBRMaterialTextureIndex, WritableKeyPath<PBRMaterialUniforms, PBRTextureSlot>)] = [
            (textures.baseColor, kPBRTextureBaseColor, \.baseColor),
            (textures.metallicRoughness, kPBRTextureMetallicRoughness, \.metallicRoughness),
            (textures.normal, kPBRTextureNormal, \.normal),
            (textures.occlusion, kPBRTextureOcclusion, \.occlusion),
            (textures.emissive, kPBRTextureEmissive, \.emissive)
        ]
        for (texture, index, slot) in slots {
            guard let texture else {
                continue
            }
            bindings[Int(index.rawValue)] = try .init(texture: texture, samplerDescriptor: sampler ?? placeholder.samplerDescriptor, device: device)
            uniforms[keyPath: slot].enabled = 1
        }
        if textures.emissive != nil {
            uniforms.emissiveFactor = [1, 1, 1]
        }
        storedMaterial = PBRMaterial(uniforms: uniforms, textureBindings: bindings, device: device)
    }
}

/// The map from scene graph nodes to node indices in a `PBRModel`.
///
/// The mesh entries come first, so index `N` is `entries[N]`. The joints of the skins come after them.
public struct PBRNodeLayout {
    /// The mesh entries, in node index order.
    public var entries: [SceneGraph.MeshEntry]
    /// The joint node IDs of the skins, after the entries in node index order.
    public private(set) var jointIDs: [SceneGraph.Node.ID] = []
    /// The joints' world transforms, parallel to ``jointIDs``.
    public private(set) var jointWorldTransforms: [simd_float4x4] = []
    /// The skins that the entries use, each one time.
    public private(set) var skins: [SceneGraph.SkinPose] = []
    private var jointIndices: [SceneGraph.Node.ID: Int] = [:]
    private var skinIndices: [ObjectIdentifier: Int] = [:]

    /// Creates the layout for mesh entries and the joints of their skins.
    public init(entries: [SceneGraph.MeshEntry]) {
        self.entries = entries
        for entry in entries {
            guard let skin = entry.skin, skinIndices[skin.skinID] == nil else {
                continue
            }
            skinIndices[skin.skinID] = skins.count
            skins.append(skin)
            for (joint, worldTransform) in zip(skin.jointIDs, skin.jointWorldTransforms) where jointIndices[joint] == nil {
                jointIndices[joint] = entries.count + jointIDs.count
                jointIDs.append(joint)
                jointWorldTransforms.append(worldTransform)
            }
        }
    }

    func skinIndex(of entry: SceneGraph.MeshEntry) -> Int? {
        entry.skin.flatMap { skinIndices[$0.skinID] }
    }

    var pbrSkins: [PBRModel.Skin] {
        skins.map { skin in
            let joints = skin.jointIDs.map { joint in
                guard let index = jointIndices[joint] else {
                    fatalError("Skin joint \(joint) has no joint index")
                }
                return index
            }
            return PBRModel.Skin(joints: joints, inverseBindMatrices: skin.inverseBindMatrices)
        }
    }

    /// `cameraPosition` is subtracted from every matrix (in Double), for camera-relative rendering (#254).
    public func pose(cameraPosition: SIMD3<Float> = .zero) -> PBRPose {
        PBRPose(
            worldMatrices: (entries.map(\.worldTransform) + jointWorldTransforms).map { $0.cameraRelative(to: cameraPosition) },
            morphWeights: entries.map(\.morphWeights) + jointIDs.map { _ in [] }
        )
    }
}

/// A builder that converts scene graph mesh entries into a MetalSprocketsPBR `PBRModel`.
///
/// ``PBRMaterialRenderer`` uses it. Use it directly to draw scene graph meshes with your own MetalSprocketsPBR pipeline.
public struct PBRSceneGraphModelBuilder {
    /// Creates a model builder.
    public init() {}

    /// Returns a model for the entries, with the default node layout.
    ///
    /// Entries whose material is not a ``PBRSceneMaterial`` are not drawn.
    ///
    /// - Throws: An error if the geometry or the model cannot be built.
    public func makeModel(entries: [SceneGraph.MeshEntry]) throws -> PBRModel {
        try makeModel(entries: entries, layout: PBRNodeLayout(entries: entries))
    }

    /// Returns a model for the entries, with a node layout that you made.
    ///
    /// - Throws: An error if the geometry or the model cannot be built.
    public func makeModel(entries: [SceneGraph.MeshEntry], layout: PBRNodeLayout) throws -> PBRModel {
        try makeModelAndKeys(entries: entries, layout: layout).model
    }

    // Also returns each entry's primitive key and the unfaded material it was built with (nil for non-PBR entries),
    // for per-frame material overrides. Entries that fade are built with a blended material so they draw in the
    // blended pass.
    func makeModelAndKeys(entries: [SceneGraph.MeshEntry], layout: PBRNodeLayout) throws -> BuiltPBRModel {
        let device = _MTLCreateSystemDefaultDevice()
        var geometry = PBRGeometryBuilder(device: device)
        var attributeCache: [ObjectIdentifier: [MetalMesh.VertexAttributeData]] = [:]
        var primitiveIDs: [Int] = []
        for entry in entries {
            let key = ObjectIdentifier(entry.mesh.vertexBuffer)
            let attributes = attributeCache[key] ?? entry.mesh.cpuReadable().vertexAttributeData()
            attributeCache[key] = attributes
            let input = pbrPrimitiveInput(entry: entry, attributes: attributes, skinned: layout.skinIndex(of: entry) != nil)
            primitiveIDs.append(try geometry.add(attributes: input.attributes, indices: input.indices, primitiveType: input.primitiveType, morphTargets: input.morphTargets, label: entry.mesh.label))
        }
        let primitives = try geometry.build()
        var builder = PBRModelBuilder(device: device, restPose: layout.pose())
        builder.skins = layout.pbrSkins
        var keys: [PBRModel.Primitive.Key?] = []
        var materials: [PBRMaterial?] = Array(repeating: nil, count: entries.count)
        for (index, entry) in entries.enumerated() {
            guard let material = entry.material as? PBRSceneMaterial else {
                keys.append(nil)
                continue
            }
            let primitive = primitives[primitiveIDs[index]]
            let base = material.pbrMaterial
            builder.addInstance(primitive, material: entry.opacity < 1 ? PBRSceneMaterial.faded(base, opacity: entry.opacity) : base, node: index, skin: layout.skinIndex(of: entry))
            keys.append(primitive.key)
            materials[index] = base
        }
        return BuiltPBRModel(model: try builder.build(), keys: keys, materials: materials)
    }
}

/// The renderer that draws every mesh with a ``PBRSceneMaterial``.
///
/// The renderer caches its model and rebuilds it only when the scene structure changes. Keep one instance across frames,
/// for example in `@State`. Instances are equal only to themselves, because `SceneView` only needs to know whether the
/// renderer is the same.
///
/// You can change ``environment`` and ``environmentIntensity`` on one thread while a view draws with
/// the renderer on its render thread.
public final class PBRMaterialRenderer: MaterialRenderer, Equatable {
    public static func == (lhs: PBRMaterialRenderer, rhs: PBRMaterialRenderer) -> Bool {
        lhs === rhs
    }

    struct Settings {
        var environment: LightingEnvironment
        var environmentIntensity: Float
    }

    // Guards `storedSettings`: the app changes settings on one thread while a view's render thread reads them (#479).
    private let lock = NSLock()
    private var storedSettings: Settings

    // A consistent copy of every setting.
    var settings: Settings {
        lock.withLock { storedSettings }
    }

    /// The image-based lighting that the renderer uses when the scene graph's environment has no map.
    public var environment: LightingEnvironment {
        get { lock.withLock { storedSettings.environment } }
        set { lock.withLock { storedSettings.environment = newValue } }
    }

    /// The strength of ``environment``.
    public var environmentIntensity: Float {
        get { lock.withLock { storedSettings.environmentIntensity } }
        set { lock.withLock { storedSettings.environmentIntensity = newValue } }
    }

    // The caches below belong to the thread that draws with this renderer.
    // One model per entry set (SceneGraphElement may split entries into batches), for the current structure.
    private var cachedModels: [EntrySetKey: BuiltPBRModel] = [:]
    private var cachedRevision: Int?
    // Faded copies from the last frame, reused while a node's opacity holds still. Each keeps its source material, so
    // the source's ObjectIdentifier in the key cannot be reused by a new material.
    private var fadedMaterials: [FadeKey: (source: PBRMaterial, faded: PBRMaterial)] = [:]
    // Reused while the view size holds still.
    private var transmissionTarget: PBRTransmissionTarget?
    // Set by the pre-pass when this frame has transmissive entries; the batches' renderers refract it.
    private var frameTransmissionTarget: PBRTransmissionTarget?

    /// Creates a PBR renderer.
    ///
    /// - Parameters:
    ///   - environment: The lighting to use when the scene graph's environment has no map.
    ///   - environmentIntensity: The strength of `environment`.
    ///
    /// Exposure and tone mapping come from the scene graph's environment, the same for every renderer.
    public init(environment: LightingEnvironment = .studio, environmentIntensity: Float = 1) {
        storedSettings = Settings(environment: environment, environmentIntensity: environmentIntensity)
    }

    public var materialType: any SceneMaterial.Type {
        PBRSceneMaterial.self
    }

    // Rebuilds the model only on structure changes (meshes, materials, skins, morph targets, hierarchy);
    // transform and weight changes go through the pose.
    // Node opacity changes only rebuild when an entry starts or stops fading (it changes pass); otherwise
    // `materialOverrides(for:built:current:)` applies the current opacity.
    // A PBRSceneMaterial whose PBRMaterial was replaced draws through an override, unless the new one draws in other
    // passes (blending, transmission, render state), which needs a new model.
    func modelAndKeys(for entries: [SceneGraph.MeshEntry], current: [PBRMaterial?], layout: PBRNodeLayout, structureRevision: Int) throws -> BuiltPBRModel {
        if cachedRevision != structureRevision {
            cachedModels.removeAll()
            cachedRevision = structureRevision
        }
        let key = EntrySetKey(entries)
        if let cached = cachedModels[key], zip(cached.materials, current).allSatisfy({ built, current in Self.canDraw(current, inPlaceOf: built) }) {
            return cached
        }
        let built = try PBRSceneGraphModelBuilder().makeModelAndKeys(entries: entries, layout: layout)
        cachedModels[key] = built
        return built
    }

    private static func canDraw(_ current: PBRMaterial?, inPlaceOf built: PBRMaterial?) -> Bool {
        guard let current, let built else {
            return current == nil && built == nil
        }
        return current === built || built.canOverride(current)
    }

    // Each entry's PBR material, read once so a frame sees one consistent value.
    static func currentMaterials(of entries: [SceneGraph.MeshEntry]) -> [PBRMaterial?] {
        entries.map { ($0.material as? PBRSceneMaterial)?.pbrMaterial }
    }

    func model(for entries: [SceneGraph.MeshEntry], structureRevision: Int) throws -> PBRModel {
        try modelAndKeys(for: entries, current: Self.currentMaterials(of: entries), layout: PBRNodeLayout(entries: entries), structureRevision: structureRevision).model
    }

    func materialOverrides(for entries: [SceneGraph.MeshEntry], built: BuiltPBRModel, current: [PBRMaterial?]) -> PBRModel.MaterialOverrides {
        var overrides: PBRModel.MaterialOverrides = [:]
        var fades: [FadeKey: (source: PBRMaterial, faded: PBRMaterial)] = [:]
        for (index, entry) in entries.enumerated() {
            guard let key = built.keys[index], let material = current[index] else {
                continue
            }
            guard entry.opacity < 1 else {
                if material !== built.materials[index] {
                    overrides[key] = material
                }
                continue
            }
            let fadeKey = FadeKey(material: ObjectIdentifier(material), opacity: entry.opacity)
            let fade = fades[fadeKey] ?? fadedMaterials[fadeKey] ?? (material, PBRSceneMaterial.faded(material, opacity: entry.opacity))
            fades[fadeKey] = fade
            overrides[key] = fade.faded
        }
        fadedMaterials = fades
        return overrides
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: RenderContext) throws -> AnyElement {
        let renderer = try makeRenderer(entries: entries, context: context, transmissionTarget: frameTransmissionTarget)
        return PBRShadowedElement(shadow: context.shadow) { shadows in
            var renderer = renderer
            renderer.lighting.shadows = shadows
            return renderer.eraseToAnyElement()
        }
        .vertexAmplification(count: context.viewCount)
        .eraseToAnyElement()
    }

    func makeRenderer(entries: [SceneGraph.MeshEntry], context: RenderContext, transmissionTarget: PBRTransmissionTarget?) throws -> PBRRenderer {
        let layout = PBRNodeLayout(entries: entries)
        let current = Self.currentMaterials(of: entries)
        let built = try modelAndKeys(for: entries, current: current, layout: layout, structureRevision: context.revision.structure)
        // Camera-relative (#254): poses and lights are shifted by the camera position and the view keeps only its
        // rotation, so the PBR shaders work on small values far from the world origin.
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let lighting = lighting(context: context, cameraPosition: cameraPosition)
        var renderer = PBRRenderer(
            model: built.model,
            viewMatrix: context.viewMatrix.rotationOnlyView,
            projectionMatrix: context.projectionMatrix,
            lighting: lighting,
            pose: layout.pose(cameraPosition: cameraPosition),
            transmissionTarget: transmissionTarget
        )
        renderer.materialOverrides = materialOverrides(for: entries, built: built, current: current)
        renderer.stereo = context.stereoViews.map { Self.relativeStereoViews($0, origin: cameraPosition) }
        if let channel = context.materialChannel {
            renderer.debugView = Self.debugView(for: channel)
        }
        return renderer
    }

    // The views relative to the render origin, matching the camera-relative poses and lights.
    static func relativeStereoViews(_ views: StereoViews, origin: SIMD3<Float>) -> StereoViews {
        let relative = views.viewMatrices.map { view in
            var translated = view
            translated.columns.3 = view * SIMD4(origin, 1)
            return translated
        }
        return StereoViews(viewMatrices: relative, projectionMatrices: views.projectionMatrices, viewports: views.viewports)
    }

    static func debugView(for channel: MaterialChannel) -> PBRDebugView {
        switch channel {
        case .baseColor: .baseColor
        case .alpha: .alpha
        case .metallic: .metallic
        case .roughness: .roughness
        case .specular: .specularF0
        case .emission: .emissive
        }
    }
}

extension PBRMaterialRenderer: PrePassRenderer {
    /// Draws the opaque scene behind transmissive surfaces, so glass refracts it: PBR with the same batches (lights,
    /// fades) as the main pass, then the other renderers' opaque batches. Their output must be linear (not tone-mapped).
    public func makePrePassElement(entries: [SceneGraph.MeshEntry], context: RenderContext, viewSize: (width: Int, height: Int), otherOpaqueContent: () throws -> AnyElement?) throws -> AnyElement? {
        frameTransmissionTarget = nil
        let hasTransmission = entries.contains { ($0.material as? PBRSceneMaterial)?.pbrMaterial.isTransmissive ?? false }
        // In stereo, PBR draws transmission as coverage instead (no pre-pass).
        guard hasTransmission, context.stereoViews == nil, viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let target: PBRTransmissionTarget
        if let transmissionTarget, transmissionTarget.width == viewSize.width, transmissionTarget.height == viewSize.height {
            target = transmissionTarget
        } else {
            target = try PBRTransmissionTarget(device: _MTLCreateSystemDefaultDevice(), width: viewSize.width, height: viewSize.height)
            transmissionTarget = target
        }
        frameTransmissionTarget = target
        let renderers = try renderBatches(entries, context: context).map { batch in
            try makeRenderer(entries: batch.entries, context: batch.context, transmissionTarget: target)
        }
        let showsBackground = if case .environment = context.environment.background { true } else { false }
        let additionalContent = try otherOpaqueContent()
        return PBRShadowedElement(shadow: context.shadow) { shadows in
            let renderers = renderers.map { renderer in
                var renderer = renderer
                renderer.lighting.shadows = shadows
                return renderer
            }
            return PBRTransmissionPass(renderers: renderers, target: target, showsBackground: showsBackground) {
                if let additionalContent {
                    additionalContent
                }
            }
            .eraseToAnyElement()
        }
        .eraseToAnyElement()
    }
}

// Binds this frame's shadow map, which is chosen by submission index, so only known while building the frame.
public extension PBRMaterialRenderer {
    /// The frame inputs of `PBR::shade` for a renderer whose shaders build their own `PBR::Fragment`, such as
    /// raymarched surfaces, so they are lit like PBR meshes. Positions are camera-relative: the render origin is the
    /// camera position. Read `submissionIndex` from the element environment (`MSEnvironment(\.submissionIndex)`).
    func frameBindings(context: RenderContext, submissionIndex: UInt64) throws -> PBRFrameBindings {
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        var lighting = lighting(context: context, cameraPosition: cameraPosition)
        lighting.shadows = context.shadow?.pbrShadows(submissionIndex: submissionIndex)
        let viewProjections = context.stereoViews?.relativeViewProjections(origin: cameraPosition) ?? [context.projectionMatrix * context.viewMatrix.rotationOnlyView]
        let cameraPositions = context.stereoViews?.cameraPositions.map { $0 - cameraPosition } ?? [.zero]
        return try PBRFrameBindings(
            lighting: lighting,
            viewProjections: viewProjections,
            cameraPositions: cameraPositions,
            debugView: context.materialChannel.map(Self.debugView) ?? .lit,
            usesAmbientOcclusion: context.stereoViews == nil
        )
    }
}

public extension Shadows.Sampling {
    /// The frame's shadow map as PBR shaders sample it. Read the submission index from the element environment
    /// (`MSEnvironment(\.submissionIndex)`): the shadow map has one texture per frame in flight.
    func pbrShadows(submissionIndex: UInt64) -> PBRShadows {
        PBRShadows(
            map: shadowMap.depthTexture(forSubmission: submissionIndex),
            // Camera-relative, like the PBR positions.
            sliceViewProjections: shadowMap.lightViewProjectionMatrices,
            filterRadius: max(softness, 0),
            sampler: shadowMap.sampler,
            intensity: intensity,
            color: color
        )
    }
}

private struct PBRShadowedElement: Element {
    var shadow: Shadows.Sampling?
    var content: (PBRShadows?) throws -> AnyElement

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            try content(shadow?.pbrShadows(submissionIndex: submissionIndex))
        }
    }
}

private struct EntrySetKey: Hashable {
    var nodes: [SceneGraph.Node.ID]
    var submeshes: [Int]
    // Levels of detail swap meshes without a structure change.
    var meshes: [ObjectIdentifier]
    // Fading entries draw in the blended pass, so starting or stopping a fade needs a new model.
    var fading: [Bool]

    init(_ entries: [SceneGraph.MeshEntry]) {
        nodes = entries.map(\.nodeID)
        submeshes = entries.map(\.submeshIndex)
        meshes = entries.map { ObjectIdentifier($0.mesh.vertexBuffer) }
        fading = entries.map { $0.opacity < 1 }
    }
}

struct BuiltPBRModel {
    var model: PBRModel
    var keys: [PBRModel.Primitive.Key?]
    var materials: [PBRMaterial?]
}

private struct FadeKey: Hashable {
    var material: ObjectIdentifier
    var opacity: Float
}

extension LightingEnvironment: EnvironmentMap {}

extension PBRSceneMaterial: AppliesAmbientOcclusionInShader {}

extension PBRMaterialRenderer: BackgroundRenderer {
    /// The lighting PBR meshes get in `context`, for renderers whose shaders call `PBR::shade` themselves: lights
    /// with their shadow slices, the environment (the scene's when it is a `LightingEnvironment`, otherwise
    /// ``environment``), exposure and screen-space occlusion. Light positions are relative to `cameraPosition`.
    /// `shadows` is nil; set it from `context.shadow` with `Shadows.Sampling.pbrShadows(submissionIndex:)`.
    public func lighting(context: RenderContext, cameraPosition: SIMD3<Float> = .zero) -> PBRLighting {
        let settings = self.settings
        var lighting = PBRLighting(
            lights: context.lights.enumerated().map { index, light in
                var result = pbrLight(worldTransform: light.worldTransform.cameraRelative(to: cameraPosition), light: light.light)
                // Each light samples only its own shadow slices.
                if context.shadow != nil, index < context.lightShadowSlices.count {
                    let slices = context.lightShadowSlices[index]
                    result.shadowSliceStart = Int32(slices.lowerBound)
                    result.shadowSliceCount = Int32(slices.count)
                }
                return result
            },
            environment: context.environment.map as? LightingEnvironment ?? settings.environment,
            environmentIntensity: settings.environmentIntensity * context.environment.intensity,
            exposure: context.environment.exposure,
            toneMapping: context.environment.toneMapping
        )
        lighting.environmentRotation = context.environment.rotation
        // Darkens only image-based light (#408). The visibility already includes the setting's intensity.
        lighting.ambientOcclusion = context.ambientOcclusion.map { LightingAmbientOcclusion(texture: $0) }
        return lighting
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func makeBackgroundElement(context: RenderContext) throws -> AnyElement? {
        guard case let .environment(blur) = context.environment.background else {
            return nil
        }
        var background = PBREnvironmentBackground(lighting: lighting(context: context), viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, blur: blur)
        background.stereo = context.stereoViews
        return background
            .vertexAmplification(count: context.viewCount)
            .eraseToAnyElement()
    }
}

func pbrPose(for entries: [SceneGraph.MeshEntry]) -> PBRPose {
    PBRNodeLayout(entries: entries).pose()
}

struct PBRPrimitiveInput {
    var attributes: [MetalMesh.VertexAttributeData]
    var indices: [UInt32]
    var primitiveType: MTLPrimitiveType
    var morphTargets: MetalMesh.MorphTargets?
}

func pbrPrimitiveInput(entry: SceneGraph.MeshEntry, attributes: [MetalMesh.VertexAttributeData], skinned: Bool) -> PBRPrimitiveInput {
    // Private-storage buffers are read through shared copies (#303).
    let mesh = entry.mesh.cpuReadable()
    let submesh = mesh.submeshes[entry.submeshIndex]
    var attributes = attributes
    if skinned {
        let skinVertices = entry.skinVertices
        attributes.append(.init(semantic: .jointIndices(0), format: .ushort4, values: skinVertices.map(\.joints)))
        attributes.append(.init(semantic: .jointWeights(0), format: .float4, values: skinVertices.map(\.weights)))
    }
    // Invalid targets are dropped as a whole, so target indices stay aligned with weights only when all are valid.
    let targets = entry.morphTargets
    var morphTargets: MetalMesh.MorphTargets?
    if !targets.isEmpty, targets.allSatisfy({ $0.isValid(vertexCount: mesh.vertexCount) }) {
        morphTargets = MetalMesh.MorphTargets(targets: targets.map { target in
            MetalMesh.MorphTargets.Target(
                positionOffsets: target.positionDeltas.isEmpty ? nil : target.positionDeltas,
                normalOffsets: target.normalDeltas.isEmpty ? nil : target.normalDeltas,
                tangentOffsets: target.tangentDeltas.isEmpty ? nil : target.tangentDeltas
            )
        })
    }
    return PBRPrimitiveInput(attributes: attributes, indices: submesh.indices, primitiveType: submesh.primitiveType, morphTargets: morphTargets)
}

// Lights point down the node's -Z axis.
func pbrLight(worldTransform: simd_float4x4, light: Light) -> LightingLight {
    var result = LightingLight()
    // Spelled out: MetalSprocketsPBR and GeometryLite3D both define SIMD4.xyz, which is ambiguous where both are imported.
    result.position = SIMD3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
    let forward = -SIMD3(worldTransform.columns.2.x, worldTransform.columns.2.y, worldTransform.columns.2.z)
    result.direction = simd_length(forward) > 0 ? simd_normalize(forward) : [0, 0, -1]
    result.color = light.color
    result.intensity = light.intensity
    result.range = light.range
    switch light.type {
    case .directional:
        result.type = .directional
    case .spot:
        result.type = .spot
        result.innerConeCos = cos(light.innerConeAngle)
        result.outerConeCos = cos(light.outerConeAngle)
    default:
        result.type = .point
    }
    return result
}
