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
public final class PBRSceneMaterial: SceneMaterial, SamplesShadowsInShader {
    /// The MetalSprocketsPBR material.
    public var pbrMaterial: PBRMaterial

    /// Creates a scene material that wraps a PBR material.
    public init(_ pbrMaterial: PBRMaterial) {
        self.pbrMaterial = pbrMaterial
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
        set { pbrMaterial.renderState = newValue }
    }

    // A blended copy with base color alpha scaled by `opacity`. Masked materials lose their cutoff while fading.
    func faded(_ opacity: Float) throws -> PBRMaterial {
        var uniforms = pbrMaterial.uniforms
        uniforms.alphaMode = .blend
        uniforms.baseColorFactor.w *= opacity
        let material = try PBRMaterial(name: pbrMaterial.name, uniforms: uniforms, doubleSided: pbrMaterial.doubleSided, textureBindings: pbrMaterial.textureBindings, device: _MTLCreateSystemDefaultDevice())
        material.textureTransforms = pbrMaterial.textureTransforms
        material.renderState = pbrMaterial.renderState
        return material
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
        let uniforms = PBRMaterialUniforms.defaults(baseColor: SIMD4(baseColor, opacity), metallic: metallic, roughness: roughness)
        do {
            pbrMaterial = try PBRMaterial(uniforms: uniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
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
    ///   - baseColor: The base color factor in linear RGB, with alpha in `w`. It multiplies the base color texture.
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
        pbrMaterial = try PBRMaterial(uniforms: uniforms, textureBindings: bindings, device: device)
    }
}

/// The map from scene graph nodes to node indices in a `PBRModel`.
///
/// The mesh entries come first, so index `N` is `entries[N]`. The joints of the skins come after them.
public struct PBRNodeLayout {
    /// The mesh entries, in node index order.
    public var entries: [SceneGraph.MeshEntry]
    /// The joint nodes of the skins, after the entries in node index order.
    public private(set) var jointNodes: [SceneGraph.Node] = []
    /// The skins that the entries use, each one time.
    public private(set) var skins: [SceneGraph.Skin] = []
    private var jointIndices: [ObjectIdentifier: Int] = [:]
    private var skinIndices: [ObjectIdentifier: Int] = [:]

    /// Creates the layout for mesh entries and the joints of their skins.
    public init(entries: [SceneGraph.MeshEntry]) {
        self.entries = entries
        for entry in entries {
            guard let skin = validSkin(of: entry), skinIndices[ObjectIdentifier(skin)] == nil else {
                continue
            }
            skinIndices[ObjectIdentifier(skin)] = skins.count
            skins.append(skin)
            for joint in skin.joints where jointIndices[ObjectIdentifier(joint)] == nil {
                jointIndices[ObjectIdentifier(joint)] = entries.count + jointNodes.count
                jointNodes.append(joint)
            }
        }
    }

    func skinIndex(of entry: SceneGraph.MeshEntry) -> Int? {
        validSkin(of: entry).flatMap { skinIndices[ObjectIdentifier($0)] }
    }

    var pbrSkins: [PBRModel.Skin] {
        skins.map { skin in
            let joints = skin.joints.map { joint in
                guard let index = jointIndices[ObjectIdentifier(joint)] else {
                    fatalError("Skin joint '\(joint.label ?? "")' has no joint index")
                }
                return index
            }
            return PBRModel.Skin(joints: joints, inverseBindMatrices: skin.inverseBindMatrices)
        }
    }

    /// `cameraPosition` is subtracted from every matrix (in Double), for camera-relative rendering (#254).
    public func pose(cameraPosition: SIMD3<Float> = .zero) -> PBRPose {
        PBRPose(
            worldMatrices: (entries.map(\.worldTransform) + jointNodes.map(\.worldTransform)).map { $0.cameraRelative(to: cameraPosition) },
            morphWeights: entries.map(\.node.morphWeights) + jointNodes.map { _ in [] }
        )
    }
}

// A skin is used only if its arrays line up with the mesh and each other.
func validSkin(of entry: SceneGraph.MeshEntry) -> SceneGraph.Skin? {
    guard let skin = entry.node.skin,
          skin.joints.count == skin.inverseBindMatrices.count,
          entry.node.skinVertices.count == entry.mesh.vertexCount
    else {
        return nil
    }
    return skin
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

    // Also returns each entry's primitive key (nil for non-PBR entries), for per-frame material overrides. Entries
    // that fade are built with a blended material so they draw in the blended pass.
    func makeModelAndKeys(entries: [SceneGraph.MeshEntry], layout: PBRNodeLayout) throws -> (model: PBRModel, keys: [PBRModel.Primitive.Key?]) {
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
        for (index, entry) in entries.enumerated() {
            guard let material = entry.material as? PBRSceneMaterial else {
                keys.append(nil)
                continue
            }
            let primitive = primitives[primitiveIDs[index]]
            let pbrMaterial = entry.opacity < 1 ? try material.faded(entry.opacity) : material.pbrMaterial
            builder.addInstance(primitive, material: pbrMaterial, node: index, skin: layout.skinIndex(of: entry))
            keys.append(primitive.key)
        }
        return (try builder.build(), keys)
    }
}

/// The renderer that draws every mesh with a ``PBRSceneMaterial``.
///
/// The renderer caches its model and rebuilds it only when the scene structure changes. Keep one instance across frames,
/// for example in `@State`. Instances are equal only to themselves, because `SceneView` only needs to know whether the
/// renderer is the same.
public final class PBRMaterialRenderer: MaterialRenderer, Equatable {
    public static func == (lhs: PBRMaterialRenderer, rhs: PBRMaterialRenderer) -> Bool {
        lhs === rhs
    }

    /// The image-based lighting that the renderer uses when the scene graph's environment has no map.
    public var environment: PBREnvironment
    /// The strength of ``environment``.
    public var environmentIntensity: Float
    /// The exposure, as a multiplier of the light before tone mapping.
    public var exposure: Float
    // One model per entry set (SceneGraphElement may split entries into batches), for the current structure.
    private var cachedModels: [EntrySetKey: (model: PBRModel, keys: [PBRModel.Primitive.Key?])] = [:]
    private var cachedRevision: Int?
    // Faded copies from the last frame, reused while a node's opacity holds still.
    private var fadedMaterials: [FadeKey: PBRMaterial] = [:]
    // Reused while the view size holds still.
    private var transmissionTarget: PBRTransmissionTarget?
    // Set by the pre-pass when this frame has transmissive entries; the batches' renderers refract it.
    private var frameTransmissionTarget: PBRTransmissionTarget?

    /// Creates a PBR renderer.
    ///
    /// - Parameters:
    ///   - environment: The lighting to use when the scene graph's environment has no map.
    ///   - environmentIntensity: The strength of `environment`.
    ///   - exposure: The exposure, as a multiplier of the light before tone mapping.
    public init(environment: PBREnvironment = .studio, environmentIntensity: Float = 1, exposure: Float = 1) {
        self.environment = environment
        self.environmentIntensity = environmentIntensity
        self.exposure = exposure
    }

    public var materialType: any SceneMaterial.Type {
        PBRSceneMaterial.self
    }

    // Rebuilds the model only on structure changes (meshes, materials, skins, morph targets, hierarchy);
    // transform and weight changes go through the pose.
    // Node opacity changes only rebuild when an entry starts or stops fading (it changes pass); otherwise
    // `materialOverrides(for:keys:)` applies the current opacity.
    func modelAndKeys(for entries: [SceneGraph.MeshEntry], layout: PBRNodeLayout, structureRevision: Int) throws -> (model: PBRModel, keys: [PBRModel.Primitive.Key?]) {
        if cachedRevision != structureRevision {
            cachedModels.removeAll()
            cachedRevision = structureRevision
        }
        let key = EntrySetKey(entries)
        if let cached = cachedModels[key] {
            return cached
        }
        let built = try PBRSceneGraphModelBuilder().makeModelAndKeys(entries: entries, layout: layout)
        cachedModels[key] = built
        return built
    }

    func model(for entries: [SceneGraph.MeshEntry], structureRevision: Int) throws -> PBRModel {
        try modelAndKeys(for: entries, layout: PBRNodeLayout(entries: entries), structureRevision: structureRevision).model
    }

    func materialOverrides(for entries: [SceneGraph.MeshEntry], keys: [PBRModel.Primitive.Key?]) throws -> PBRModel.MaterialOverrides {
        var overrides: PBRModel.MaterialOverrides = [:]
        var materials: [FadeKey: PBRMaterial] = [:]
        for (entry, key) in zip(entries, keys) {
            guard entry.opacity < 1, let key, let material = entry.material as? PBRSceneMaterial else {
                continue
            }
            let fadeKey = FadeKey(material: ObjectIdentifier(material.pbrMaterial), opacity: entry.opacity)
            let faded = try materials[fadeKey] ?? fadedMaterials[fadeKey] ?? material.faded(entry.opacity)
            materials[fadeKey] = faded
            overrides[key] = faded
        }
        fadedMaterials = materials
        return overrides
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: RenderContext) throws -> AnyElement {
        let renderer = try makeRenderer(entries: entries, context: context, transmissionTarget: frameTransmissionTarget)
        return PBRShadowedElement(shadow: context.shadow) { shadows in
            var renderer = renderer
            renderer.lighting.shadows = shadows
            return renderer.eraseToAnyElement()
        }
        .eraseToAnyElement()
    }

    func makeRenderer(entries: [SceneGraph.MeshEntry], context: RenderContext, transmissionTarget: PBRTransmissionTarget?) throws -> PBRRenderer {
        let layout = PBRNodeLayout(entries: entries)
        let (model, keys) = try modelAndKeys(for: entries, layout: layout, structureRevision: context.revision.structure)
        // Camera-relative (#254): poses and lights are shifted by the camera position and the view keeps only its
        // rotation, so the PBR shaders work on small values far from the world origin.
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let lighting = lighting(context: context, cameraPosition: cameraPosition)
        var renderer = PBRRenderer(
            model: model,
            viewMatrix: context.viewMatrix.rotationOnlyView,
            projectionMatrix: context.projectionMatrix,
            lighting: lighting,
            pose: layout.pose(cameraPosition: cameraPosition),
            transmissionTarget: transmissionTarget
        )
        renderer.materialOverrides = try materialOverrides(for: entries, keys: keys)
        if let channel = context.materialChannel {
            renderer.debugView = Self.debugView(for: channel)
        }
        return renderer
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
        guard hasTransmission, viewSize.width > 0, viewSize.height > 0 else {
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
private struct PBRShadowedElement: Element {
    var shadow: Shadows.Sampling?
    var content: (PBRShadows?) throws -> AnyElement

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let shadows = shadow.map { shadow in
                PBRShadows(
                    map: shadow.shadowMap.depthTexture(forSubmission: submissionIndex),
                    // Camera-relative, like the PBR positions.
                    sliceViewProjections: shadow.shadowMap.lightViewProjectionMatrices,
                    filterRadius: max(shadow.softness, 0),
                    sampler: shadow.shadowMap.sampler,
                    intensity: shadow.intensity,
                    color: shadow.color
                )
            }
            return try content(shadows)
        }
    }
}

private struct EntrySetKey: Hashable {
    var nodes: [ObjectIdentifier]
    var submeshes: [Int]
    // Levels of detail swap meshes without a structure change.
    var meshes: [ObjectIdentifier]
    // Fading entries draw in the blended pass, so starting or stopping a fade needs a new model.
    var fading: [Bool]

    init(_ entries: [SceneGraph.MeshEntry]) {
        nodes = entries.map { ObjectIdentifier($0.node) }
        submeshes = entries.map(\.submeshIndex)
        meshes = entries.map { ObjectIdentifier($0.mesh.vertexBuffer) }
        fading = entries.map { $0.opacity < 1 }
    }
}

private struct FadeKey: Hashable {
    var material: ObjectIdentifier
    var opacity: Float
}

extension PBREnvironment: EnvironmentMap {}

extension PBRMaterialRenderer: BackgroundRenderer {
    // The scene's environment map when it is a PBREnvironment, otherwise `environment`; intensities multiply.
    // Light positions are shifted by `cameraPosition` for camera-relative rendering.
    func lighting(context: RenderContext, cameraPosition: SIMD3<Float> = .zero) -> PBRLighting {
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
            environment: context.environment.map as? PBREnvironment ?? environment,
            environmentIntensity: environmentIntensity * context.environment.intensity,
            exposure: exposure
        )
        lighting.environmentRotation = context.environment.rotation
        return lighting
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func makeBackgroundElement(context: RenderContext) throws -> AnyElement? {
        guard case let .environment(blur) = context.environment.background else {
            return nil
        }
        return PBREnvironmentBackground(lighting: lighting(context: context), viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, blur: blur)
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
        let skinVertices = entry.node.skinVertices
        attributes.append(.init(semantic: .jointIndices(0), format: .ushort4, values: skinVertices.map(\.joints)))
        attributes.append(.init(semantic: .jointWeights(0), format: .float4, values: skinVertices.map(\.weights)))
    }
    // Invalid targets are dropped as a whole, so target indices stay aligned with weights only when all are valid.
    let targets = entry.node.morphTargets
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
func pbrLight(worldTransform: simd_float4x4, light: Light) -> PBRLight {
    var result = PBRLight()
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
