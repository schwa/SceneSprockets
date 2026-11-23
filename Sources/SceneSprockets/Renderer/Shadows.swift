import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsLighting
import MetalSprocketsSupport
import MetalSupport
import ModelIO
import SceneSprocketsShaders
import simd
import SwiftMesh

/// A renderer whose entries are not drawn as their mesh, such as raymarched shapes, and that draws their depth into the
/// shadow map itself. Entries with `castsShadow` are drawn by ``makeShadowCasterElement(entries:context:)`` instead of
/// as their mesh.
public protocol ShadowCasterRenderer: MaterialRenderer {
    /// Returns an element that draws the entries' depth into one shadow map slice. It is called once per slice.
    ///
    /// The element draws inside a render pass with no color attachment and a `depth32Float` attachment. Depth is
    /// reversed (near is 1); the pass sets a greater-equal depth test with writes and a hardware depth bias. Positions
    /// are camera-relative, as in the scene pass.
    func makeShadowCasterElement(entries: [SceneGraph.MeshEntry], context: ShadowCasterContext) throws -> AnyElement
}

/// What a ``ShadowCasterRenderer`` needs to draw one shadow map slice.
public struct ShadowCasterContext {
    /// Camera-relative world positions (world minus ``renderOrigin``) to the slice's clip space. Directional light
    /// views already push depth away from the light. The hardware depth bias does not apply to depth written by a
    /// fragment shader, so such shaders need their own bias for spot and point lights.
    public var viewProjection: simd_float4x4
    /// The world position that is the origin of camera-relative space: the camera position.
    public var renderOrigin: SIMD3<Float>
    /// The width and height of the slice, in texels.
    public var resolution: Int
}

/// Materials whose renderer samples the shadow map per light while shading (Blinn-Phong, PBR, and shader materials that
/// opt in). The screen-space mask skips their pixels.
public protocol SamplesShadowsInShader {
    /// Whether this material samples shadows in its shader. Defaults to true.
    var samplesShadowsInShader: Bool { get }
}

public extension SamplesShadowsInShader {
    var samplesShadowsInShader: Bool {
        true
    }
}

/// How a see-through material cuts holes in its shadow (#541). A shadow map holds one depth per texel, so a caster
/// either blocks the light at a point or not: points where `opacity` times the texture's alpha is below `cutoff` cast
/// no shadow.
public struct ShadowCasterAlpha {
    /// A constant alpha. Node opacity multiplies it.
    public var opacity: Float
    /// Points with less alpha than this cast no shadow.
    public var cutoff: Float
    /// A texture whose alpha multiplies `opacity`, or nil.
    public var texture: MTLTexture?
    /// The sampler for `texture`, or nil for linear filtering with repeat.
    public var sampler: MTLSamplerState?
    /// Which texture coordinate set of the mesh to read.
    public var texCoordIndex: Int
    /// A transform applied to the texture coordinates, as in KHR_texture_transform.
    public var texCoordTransform: simd_float3x3

    public init(opacity: Float = 1, cutoff: Float = 0.5, texture: MTLTexture? = nil, sampler: MTLSamplerState? = nil, texCoordIndex: Int = 0, texCoordTransform: simd_float3x3 = matrix_identity_float3x3) {
        self.opacity = opacity
        self.cutoff = cutoff
        self.texture = texture
        self.sampler = sampler
        self.texCoordIndex = texCoordIndex
        self.texCoordTransform = texCoordTransform
    }
}

/// Materials that can be partly see-through. Their shadow casters drop the points that ``shadowCasterAlpha`` makes
/// transparent; other materials cast solid shadows.
public protocol ShadowCasterAlphaMaterial {
    /// Nil when the material is opaque.
    var shadowCasterAlpha: ShadowCasterAlpha? { get }
}

/// Shadow-mapped shadows from directional, spot and point lights, for every renderer: casters are drawn into a shadow
/// map from each light. Blinn-Phong, PBR and shader materials with `samplesShadows` sample it per light while shading,
/// so a light only darkens what it lights; other materials are darkened in screen space after the scene pass, by every
/// light's shadow at once. Keep one instance across frames (it holds the shadow map and caster buffers) and pass it to
/// SceneGraphElement or SceneView.
/// 
/// The shadow map has ``maximumSliceCount`` slices (8 by default): a directional or spot light uses one, a point light
/// six. ``lightPriority`` picks which lights get them; a light that does not fit casts none and is counted in
/// `droppedLightCount`. Meshes with `castsShadow: false` cast none; meshes with
/// `receivesShadow: false` receive none.
/// The view's color texture needs `.shaderWrite` and its depth texture `.shaderRead` usage (see
/// `requiredColorUsage`); otherwise no shadows are drawn.
///
/// You can change the settings and read ``droppedLightCount`` on one thread while a view draws with the object on its
/// render thread.
public final class Shadows {
    /// Usage the view's color texture needs: the shadow and post-processing passes write it from compute.
    public static let requiredColorUsage: MTLTextureUsage = [.renderTarget, .shaderRead, .shaderWrite]
    /// Usage the view's depth texture needs: the passes sample it.
    public static let requiredDepthUsage: MTLTextureUsage = [.renderTarget, .shaderRead]

    // What the app sets and the render thread reads, and the count that goes the other way.
    struct Settings {
        var intensity: Float
        var color: SIMD3<Float>
        var softness: Int
        var resolution: Int
        var depthBias: Float
        var slopeScale: Float
        var depthOffsetTexels: Float
        var maximumSliceCount = 8
        var lightPriority = LightPriority.sceneOrder
        var droppedLightCount = 0
    }

    /// Which lights get shadow map slices first when not all fit.
    public enum LightPriority: Sendable {
        /// In scene order.
        case sceneOrder
        /// Highest intensity times brightest color channel first.
        case brightest
        /// Nearest to the camera first. Directional lights count as at the camera.
        case nearestToCamera
    }

    /// The most slices the shaders support; ``maximumSliceCount`` is clamped to it.
    public static let sliceCountLimit = Int(kLightingMaxShadowSliceCount)

    // Guards `storedSettings`: the app changes settings on one thread while a view's render thread reads them (#478).
    private let lock = NSLock()
    private var storedSettings: Settings

    // A consistent copy of every setting, for one frame.
    var settings: Settings {
        lock.withLock { storedSettings }
    }

    private func read<Value>(_ keyPath: KeyPath<Settings, Value>) -> Value {
        lock.withLock { storedSettings[keyPath: keyPath] }
    }

    private func write<Value>(_ keyPath: WritableKeyPath<Settings, Value>, _ value: Value) {
        lock.withLock { storedSettings[keyPath: keyPath] = value }
    }

    /// 0 leaves shadowed pixels unchanged, 1 multiplies them by `color`.
    public var intensity: Float {
        get { read(\.intensity) }
        set { write(\.intensity, newValue) }
    }

    /// Linear RGB multiplied into shadowed pixels, like SCNLight.shadowColor; black darkens.
    public var color: SIMD3<Float> {
        get { read(\.color) }
        set { write(\.color, newValue) }
    }

    /// Soft-shadow filter half-size in shadow map texels, like SCNLight.shadowRadius: 1 filters 3x3, 0 is hard.
    /// Cost grows with (2 * softness + 1)^2 per light.
    public var softness: Int {
        get { read(\.softness) }
        set { write(\.softness, newValue) }
    }

    /// The width and height of each shadow map slice, in texels.
    public var resolution: Int {
        get { read(\.resolution) }
        set { write(\.resolution, newValue) }
    }

    /// The constant depth bias when the shadow map is drawn.
    public var depthBias: Float {
        get { read(\.depthBias) }
        set { write(\.depthBias, newValue) }
    }

    /// The depth bias that increases with the slope of the surface, per texel of `softness`.
    public var slopeScale: Float {
        get { read(\.slopeScale) }
        set { write(\.slopeScale, newValue) }
    }

    /// World-space push of directional-light casters away from the light, in shadow map texels. The hardware
    /// constant bias is tiny with depth32Float, so this is what stops acne on lit faces (#60).
    public var depthOffsetTexels: Float {
        get { read(\.depthOffsetTexels) }
        set { write(\.depthOffsetTexels, newValue) }
    }

    /// The number of shadow map slices, from 1 to ``sliceCountLimit``. The map only allocates the slices that lights
    /// use; each one at the default resolution is 16 MB per frame in flight.
    public var maximumSliceCount: Int {
        get { read(\.maximumSliceCount) }
        set { write(\.maximumSliceCount, min(max(newValue, 1), Self.sliceCountLimit)) }
    }

    /// Which lights get slices first when not all fit.
    public var lightPriority: LightPriority {
        get { read(\.lightPriority) }
        set { write(\.lightPriority, newValue) }
    }

    /// Lights that cast no shadow in the last frame because their views did not fit in ``maximumSliceCount`` slices.
    public var droppedLightCount: Int {
        read(\.droppedLightCount)
    }

    // The caches below belong to the thread that draws with this object.
    private var shadowMap: SceneGraphShadowMap?
    private var positionBuffers: [PositionKey: MTLBuffer] = [:]
    private var texCoordBuffers: [TexCoordKey: MTLBuffer] = [:]
    private var influenceBuffers: [InfluenceKey: MTLBuffer] = [:]
    // One per frame in flight, like the shadow map's depth textures.
    private var receiverMasks: [MTLTexture] = []

    /// Creates shadow settings. Keep one instance for each view, because it keeps the shadow map between frames.
    public init(intensity: Float = 0.6, color: SIMD3<Float> = .zero, softness: Int = 1, resolution: Int = 2_048, depthBias: Float = 2, slopeScale: Float = 2, depthOffsetTexels: Float = 1.5, maximumSliceCount: Int = 8, lightPriority: LightPriority = .sceneOrder) {
        storedSettings = Settings(intensity: intensity, color: color, softness: softness, resolution: resolution, depthBias: depthBias, slopeScale: slopeScale, depthOffsetTexels: depthOffsetTexels, maximumSliceCount: min(max(maximumSliceCount, 1), Self.sliceCountLimit), lightPriority: lightPriority)
    }

    /// What an in-shader renderer needs to sample the shadow map.
    public struct Sampling {
        /// The shadow map of the frame.
        public internal(set) var shadowMap: SceneGraphShadowMap
        /// The shadow strength, from 0 to 1.
        public internal(set) var intensity: Float
        /// The color that multiplies shadowed pixels, in linear RGB.
        public internal(set) var color: SIMD3<Float>
        /// The filter half-size, in shadow map texels.
        public internal(set) var softness: Int

        /// The shadow uniforms that every renderer's shaders read through `Lighting::shadow`. Slices are
        /// camera-relative, like the shading positions.
        public var uniforms: LightingShadowUniforms {
            var uniforms = LightingShadowUniforms()
            uniforms.enabled = 1
            uniforms.mapSize = Float(shadowMap.resolution)
            uniforms.intensity = intensity
            uniforms.color = color
            uniforms.radius = Int32(max(softness, 0))
            withUnsafeMutableBytes(of: &uniforms.sliceViewProjections) { buffer in
                let slices = buffer.bindMemory(to: simd_float4x4.self)
                for (index, matrix) in shadowMap.lightViewProjectionMatrices.prefix(slices.count).enumerated() {
                    slices[index] = matrix
                }
            }
            withUnsafeMutableBytes(of: &uniforms.sliceCascades) { buffer in
                let cascades = buffer.bindMemory(to: SIMD4<Float>.self)
                for (index, cascade) in shadowMap.sliceCascades.prefix(cascades.count).enumerated() {
                    cascades[index] = cascade
                }
            }
            return uniforms
        }
    }

    struct Caster {
        enum Placement {
            case model(simd_float4x4)
            /// Skinned on the GPU: rest positions moved by these joint matrices (joint world * inverse bind).
            case skinned(influences: MTLBuffer, jointMatrices: [simd_float4x4])
        }

        var positions: MTLBuffer
        var submesh: MetalMesh.Submesh
        var placement: Placement
        // See-through casters: their alpha and texture coordinates.
        var alpha: (alpha: ShadowCasterAlpha, texCoords: MTLBuffer)?
    }

    struct Frame {
        var shadowMap: SceneGraphShadowMap
        var casters: [Caster]
        // Entries that ShadowCasterRenderers draw themselves.
        var customCasters: [(renderer: any ShadowCasterRenderer, entries: [SceneGraph.MeshEntry])] = []
        var renderOrigin: SIMD3<Float> = .zero
        // Parallel to the shadow map's light view-projections, with the caster depth offset applied.
        var casterViewProjections: [simd_float4x4] = []
        // Meshes the screen-space mask skips (non-receivers and in-shader shadowing); nil when there are none.
        var nonReceivers: (casters: [Caster], masks: [MTLTexture])?
        // Parallel to the context's lights: each light's shadow map slices.
        var lightSlices: [Range<Int>] = []
        // True when every mesh is skipped, so the screen-space mask pass has nothing to do.
        var masksEverything = false
    }

    // Nil when nothing casts or there is no light.
    func prepare(entries: [SceneGraph.MeshEntry], context: RenderContext, bounds: BoundingBox3D?, viewSize: (width: Int, height: Int)? = nil, renderers: [any MaterialRenderer] = []) throws -> Frame? {
        guard let bounds else {
            return nil
        }
        // Decals and other depth readers draw onto other surfaces; they neither cast nor receive (#397).
        let entries = entries.filter { !($0.material is any ReadsSceneDepth) }
        // Everything here is camera-relative (#257): lights, bounds and casters are shifted by the camera position in
        // Double, so the light views map camera-relative positions and stay precise far from the world origin.
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let relativeBounds = BoundingBox3D(min: cameraRelative(bounds.min, to: cameraPosition), max: cameraRelative(bounds.max, to: cameraPosition))
        let relativeLights = context.lights.map { (worldTransform: $0.worldTransform.cameraRelative(to: cameraPosition), light: $0.light) }
        let (shadowSlices, dropped, slices) = shadowSlices(lights: relativeLights, bounds: relativeBounds)
        let views = shadowSlices.map(\.view)
        write(\.droppedLightCount, dropped)
        // One copy for the whole frame, so a change in the middle does not mix old and new values.
        let settings = self.settings
        guard !views.isEmpty else {
            return nil
        }
        var usedKeys = Set<PositionKey>()
        var usedTexCoords = Set<TexCoordKey>()
        var usedInfluences = Set<InfluenceKey>()
        var casters: [Caster] = []
        var nonReceivers: [Caster] = []
        // Position-only geometry for `entry`, as drawn this frame. With `alpha`, see-through materials get their
        // alpha, or no caster when nothing of them reaches the cutoff.
        func caster(for entry: SceneGraph.MeshEntry, alpha usesAlpha: Bool = false) -> Caster? {
            var alpha: (alpha: ShadowCasterAlpha, texCoords: MTLBuffer)?
            if usesAlpha {
                var materialAlpha = (entry.material as? any ShadowCasterAlphaMaterial)?.shadowCasterAlpha
                if entry.opacity < 1, entry.material.appliesNodeOpacity {
                    materialAlpha = materialAlpha ?? ShadowCasterAlpha()
                    materialAlpha?.opacity *= entry.opacity
                }
                if let materialAlpha {
                    if materialAlpha.opacity < materialAlpha.cutoff {
                        return nil
                    }
                    if materialAlpha.texture != nil {
                        let texCoordKey = TexCoordKey(position: PositionKey(entry.mesh), index: materialAlpha.texCoordIndex)
                        usedTexCoords.insert(texCoordKey)
                        // Without texture coordinates the texture cannot be read; the constant alpha still applies.
                        if let texCoords = texCoordBuffer(for: entry.mesh, key: texCoordKey) {
                            alpha = (materialAlpha, texCoords)
                        }
                    }
                }
            }
            // Skin on the GPU when there is a valid skin and no active morph; otherwise use CPU-deformed positions.
            let skin = gpuSkin(of: entry)
            let deformed = skin == nil ? entry.deformed(revision: context.revision) : nil
            let mesh = deformed?.mesh ?? entry.mesh
            let submesh = mesh.submeshes[entry.submeshIndex]
            guard submesh.primitiveType == .triangle || submesh.primitiveType == .triangleStrip else {
                return nil
            }
            let key = PositionKey(mesh)
            usedKeys.insert(key)
            guard let positions = positionBuffer(for: mesh, key: key) else {
                return nil
            }
            guard let skin else {
                return Caster(positions: positions, submesh: submesh, placement: .model((deformed?.modelMatrix ?? entry.worldTransform).cameraRelative(to: cameraPosition)), alpha: alpha)
            }
            let influenceKey = InfluenceKey(node: entry.nodeID, revision: context.revision.structure)
            usedInfluences.insert(influenceKey)
            guard let influences = influenceBuffer(for: entry, key: influenceKey, device: mesh.vertexBuffer.device) else {
                return nil
            }
            return Caster(positions: positions, submesh: submesh, placement: .skinned(influences: influences, jointMatrices: skin.jointMatrices().map { $0.cameraRelative(to: cameraPosition) }), alpha: alpha)
        }
        // Materials that sample shadows themselves are kept out of the screen-space mask, like non-receivers.
        let skipsMask = { (entry: SceneGraph.MeshEntry) in !entry.receivesShadow || (entry.material as? any SamplesShadowsInShader)?.samplesShadowsInShader == true }
        let masksEverything = entries.allSatisfy(skipsMask)
        let casterRenderers = renderers.compactMap { $0 as? any ShadowCasterRenderer }
        var customEntries: [[SceneGraph.MeshEntry]] = Array(repeating: [], count: casterRenderers.count)
        for entry in entries {
            if let index = casterRenderers.firstIndex(where: { ObjectIdentifier($0.materialType) == ObjectIdentifier(type(of: entry.material)) }) {
                if entry.castsShadow {
                    customEntries[index].append(entry)
                }
            } else if entry.castsShadow, let caster = caster(for: entry, alpha: true) {
                casters.append(caster)
            }
            if !masksEverything, skipsMask(entry), let caster = caster(for: entry) {
                nonReceivers.append(caster)
            }
        }
        positionBuffers = positionBuffers.filter { usedKeys.contains($0.key) }
        texCoordBuffers = texCoordBuffers.filter { usedTexCoords.contains($0.key) }
        influenceBuffers = influenceBuffers.filter { usedInfluences.contains($0.key) }
        let customCasters = zip(casterRenderers, customEntries).filter { !$0.1.isEmpty }.map { (renderer: $0.0, entries: $0.1) }
        guard !casters.isEmpty || !customCasters.isEmpty else {
            return nil
        }

        if shadowMap?.lightCount != views.count || shadowMap?.resolution != settings.resolution {
            shadowMap = try SceneGraphShadowMap(resolution: settings.resolution, lightCount: views.count)
        }
        guard var shadowMap else {
            return nil
        }
        shadowMap.depthBias = settings.depthBias
        // The PCF kernel compares one receiver depth against texels up to `softness` away, so a sloped receiver needs a
        // slope bias that grows with it, or it shadows itself (#366).
        shadowMap.slopeScale = settings.slopeScale * Float(max(settings.softness, 1))
        shadowMap.lightViewProjectionMatrices = views
        shadowMap.sliceCascades = shadowSlices.map(\.cascade)
        // The slope bias grows with softness, as above.
        shadowMap.sliceRenders = shadowSlices.map { SceneGraphShadowMap.SliceRender(size: $0.render.size, depthBias: $0.render.depthBias, slopeScale: $0.render.slopeScale * Float(max(settings.softness, 1))) }
        self.shadowMap = shadowMap
        let casterViews = views.map { casterViewProjection($0, settings: settings) }
        guard !nonReceivers.isEmpty, let viewSize else {
            return Frame(shadowMap: shadowMap, casters: casters, customCasters: customCasters, renderOrigin: cameraPosition, casterViewProjections: casterViews, lightSlices: slices, masksEverything: masksEverything)
        }
        return Frame(shadowMap: shadowMap, casters: casters, customCasters: customCasters, renderOrigin: cameraPosition, casterViewProjections: casterViews, nonReceivers: (nonReceivers, try receiverMasks(width: viewSize.width, height: viewSize.height, count: shadowMap.depthTextures.count)), lightSlices: slices, masksEverything: masksEverything)
    }

    // `view` with caster depth pushed `depthOffsetTexels` texels away from the light. Only orthographic (directional)
    // views; perspective views are returned unchanged and rely on the hardware bias.
    func casterViewProjection(_ view: simd_float4x4, settings: Settings? = nil) -> simd_float4x4 {
        let settings = settings ?? self.settings
        let depthOffsetTexels = settings.depthOffsetTexels
        let resolution = settings.resolution
        let rowW = SIMD3(view[0][3], view[1][3], view[2][3])
        guard simd_length(rowW) < 1e-6, depthOffsetTexels != 0 else {
            return view
        }
        let rowX = SIMD3(view[0][0], view[1][0], view[2][0])
        let rowZ = SIMD3(view[0][2], view[1][2], view[2][2])
        let texel = 2 / simd_length(rowX) / Float(resolution)
        // Reversed depth: further from the light is smaller z.
        var offset = matrix_identity_float4x4
        offset[3][2] = -depthOffsetTexels * texel * simd_length(rowZ)
        return offset * view
    }

    private func receiverMasks(width: Int, height: Int, count: Int) throws -> [MTLTexture] {
        if receiverMasks.count == count, receiverMasks.allSatisfy({ $0.width == width && $0.height == height }) {
            return receiverMasks
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let device = _MTLCreateSystemDefaultDevice()
        receiverMasks = try (0..<count).map { index in
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw MetalSupportError.resourceCreationFailure("Failed to create shadow receiver mask")
            }
            texture.label = "Shadow Receiver Mask \(index)"
            return texture
        }
        return receiverMasks
    }

    // One view-projection per shadow map slice, up to `maximumSliceCount`: directional lights get an orthographic view
    // fitted to `bounds`, spot lights a perspective view of their outer cone, point lights six 90° views. All use
    // reversed depth, like ShadowMap's default.
    func shadowViews(lights: [(worldTransform: simd_float4x4, light: Light)], bounds: BoundingBox3D) -> [simd_float4x4] {
        shadowViewsAndDroppedLights(lights: lights, bounds: bounds).views
    }

    // A light whose views do not all fit in the remaining slices is dropped whole; later lights may still fit.
    // `slices` is parallel to `lights`: the slices of each light's views, empty for lights that cast none.
    func shadowViewsAndDroppedLights(lights: [(worldTransform: simd_float4x4, light: Light)], bounds: BoundingBox3D) -> (views: [simd_float4x4], dropped: Int, slices: [Range<Int>]) {
        let result = shadowSlices(lights: lights, bounds: bounds)
        return (result.slices.map(\.view), result.dropped, result.lightSlices)
    }

    // One shadow map slice: its view, and how it is drawn and sampled (#88).
    struct Slice {
        var view: simd_float4x4
        var cascade = SIMD4<Float>.zero
        var render: SceneGraphShadowMap.SliceRender
    }

    // Positions are camera-relative, so the camera is at the origin.
    func shadowSlices(lights: [(worldTransform: simd_float4x4, light: Light)], bounds: BoundingBox3D) -> (slices: [Slice], dropped: Int, lightSlices: [Range<Int>]) {
        let center = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 0.01)
        let settings = self.settings
        var allSlices: [Slice] = []
        var dropped = 0
        var slices = Array(repeating: 0..<0, count: lights.count)
        let order: [Int] = switch settings.lightPriority {
        case .sceneOrder:
            Array(lights.indices)
        case .brightest:
            lights.indices.sorted { index, other in
                let brightness = { (light: Light) in light.intensity * light.color.max() }
                let (value, otherValue) = (brightness(lights[index].light), brightness(lights[other].light))
                return value != otherValue ? value > otherValue : index < other
            }
        case .nearestToCamera:
            // Positions are camera-relative, so the camera is at the origin.
            lights.indices.sorted { index, other in
                let distance = { (entry: (worldTransform: simd_float4x4, light: Light)) in entry.light.type == .directional ? 0 : simd_length(entry.worldTransform.columns.3.xyz) }
                let (value, otherValue) = (distance(lights[index]), distance(lights[other]))
                return value != otherValue ? value < otherValue : index < other
            }
        }
        for lightIndex in order {
            let (transform, light) = lights[lightIndex]
            guard light.castsShadow else {
                continue
            }
            var lightViews: [simd_float4x4] = []
            var cascades: [SIMD4<Float>] = []
            let lightSettings = light.shadowSettings ?? Light.ShadowSettings()
            let scale = min(max(lightSettings.resolutionScale, 1 / Float(max(settings.resolution, 1))), 1)
            let size = max(Int((Float(settings.resolution) * scale).rounded()), 1)
            let position = transform.columns.3.xyz
            let forward = simd_normalize(-transform.columns.2.xyz)
            // Far enough to reach the whole scene from the light.
            let far = max(simd_distance(position, center) + radius, 0.1)
            let near = max(far * 0.001, 0.01)
            switch light.type {
            case .ambient, .area:
                // Ambient lights have no direction; area light shadows are not drawn yet (#509).
                continue
            case .directional where lightSettings.cascadeCount > 1:
                for (view, cascade) in cascadeViews(forward: forward, bounds: bounds, count: lightSettings.cascadeCount, splitFactor: lightSettings.splitFactor, resolution: size) {
                    lightViews.append(view)
                    cascades.append(cascade)
                }
            case .directional:
                let eye = center - forward * radius * 2
                let projection = OrthographicProjection(halfHeight: radius, depthMode: .reversed(zClip: radius * 0.5 ... radius * 3.5))
                lightViews.append(projection.projectionMatrix(aspectRatio: 1) * .viewMatrix(eye: eye, forward: forward))
            case .spot:
                let fieldOfView = min(max(light.outerConeAngle * 2, 0.01), .pi * 0.95)
                let projection = PerspectiveProjection(verticalAngleOfView: .radians(fieldOfView), depthMode: .reversed(zClip: near ... far))
                lightViews.append(projection.projectionMatrix(aspectRatio: 1) * .viewMatrix(eye: position, forward: forward))
            case .point:
                let faces: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
                let projection = PerspectiveProjection(verticalAngleOfView: .degrees(90), depthMode: .reversed(zClip: near ... far))
                for face in faces {
                    lightViews.append(projection.projectionMatrix(aspectRatio: 1) * .viewMatrix(eye: position, forward: face))
                }
            }
            if allSlices.count + lightViews.count <= settings.maximumSliceCount {
                slices[lightIndex] = allSlices.count..<(allSlices.count + lightViews.count)
                let render = SceneGraphShadowMap.SliceRender(size: size, depthBias: lightSettings.depthBias ?? settings.depthBias, slopeScale: lightSettings.slopeScale ?? settings.slopeScale)
                let extent = Float(size) / Float(max(settings.resolution, 1))
                for (index, view) in lightViews.enumerated() {
                    var cascade = cascades.indices.contains(index) ? cascades[index] : .zero
                    cascade.z = extent < 1 ? extent : 0
                    allSlices.append(Slice(view: Self.subRectangle(scale: extent) * view, cascade: cascade, render: render))
                }
            } else {
                dropped += 1
            }
        }
        return (allSlices, dropped, slices)
    }

    // Maps clip space to the top-left `scale` of the slice, so a light can use fewer texels than the slice has.
    static func subRectangle(scale: Float) -> simd_float4x4 {
        guard scale < 1 else {
            return matrix_identity_float4x4
        }
        return simd_float4x4(columns: ([scale, 0, 0, 0], [0, scale, 0, 0], [0, 0, 1, 0], [scale - 1, 1 - scale, 0, 1]))
    }

    // Cascaded orthographic views for a directional light (#88). Cascade i covers the scene within split distance d_i
    // of the camera (the origin): d_i mixes even and logarithmic spacing by `splitFactor`, and the last reaches the
    // farthest point of `bounds`. Every view keeps the whole scene's depth range, so casters outside a cascade still
    // shadow into it. Each view is moved in whole texels so shadows do not crawl as the camera moves.
    func cascadeViews(forward: SIMD3<Float>, bounds: BoundingBox3D, count: Int, splitFactor: Float, resolution: Int) -> [(view: simd_float4x4, cascade: SIMD4<Float>)] {
        let sceneCenter = (bounds.min + bounds.max) / 2
        let sceneRadius = max(simd_length(bounds.max - bounds.min) / 2, 0.01)
        let corners = (0..<8).map { corner in
            SIMD3<Float>(corner & 1 == 0 ? bounds.min.x : bounds.max.x, corner & 2 == 0 ? bounds.min.y : bounds.max.y, corner & 4 == 0 ? bounds.min.z : bounds.max.z)
        }
        let far = max(corners.map { simd_length($0) }.max() ?? 0, 0.01)
        let near = max(simd_length(simd_clamp(SIMD3<Float>.zero, bounds.min, bounds.max)), far * 0.01)
        let factor = min(max(splitFactor, 0), 1)
        let lightView = simd_float4x4.viewMatrix(eye: .zero, forward: forward)
        var previous: Float = 0
        return (1...count).map { index in
            let fraction = Float(index) / Float(count)
            let even = near + (far - near) * fraction
            let logarithmic = near * pow(far / near, fraction)
            let split = index == count ? far : even + (logarithmic - even) * factor
            let box = BoundingBox3D(min: simd_max(bounds.min, SIMD3(repeating: -split)), max: simd_min(bounds.max, SIMD3(repeating: split)))
            let radius = max(simd_length(box.max - box.min) / 2, 0.01)
            let texel = 2 * radius / Float(max(resolution, 1))
            var local = (lightView * SIMD4((box.min + box.max) / 2, 1)).xyz
            local.x = (local.x / texel).rounded() * texel
            local.y = (local.y / texel).rounded() * texel
            let center = (lightView.inverse * SIMD4(local, 1)).xyz
            let offset = simd_distance(center, sceneCenter)
            let eye = center - forward * sceneRadius * 2
            let projection = OrthographicProjection(halfHeight: radius, depthMode: .reversed(zClip: max(sceneRadius - offset, sceneRadius * 0.01) ... (sceneRadius * 3 + offset)))
            let cascade = SIMD4<Float>(split, split - (split - previous) * 0.1, 0, 0)
            previous = split
            return (projection.projectionMatrix(aspectRatio: 1) * .viewMatrix(eye: eye, forward: forward), cascade)
        }
    }

    private func gpuSkin(of entry: SceneGraph.MeshEntry) -> SceneGraph.SkinPose? {
        entry.hasMorphs ? nil : entry.skin
    }

    private func positionBuffer(for mesh: MetalMesh, key: PositionKey) -> MTLBuffer? {
        if let buffer = positionBuffers[key] {
            return buffer
        }
        let positions = mesh.positions()
        guard !positions.isEmpty, let buffer = mesh.vertexBuffer.device.makeBuffer(bytes: positions.map { Packed3($0) }, length: positions.count * MemoryLayout<Packed3>.stride, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "Shadow Caster Positions"
        positionBuffers[key] = buffer
        return buffer
    }

    // Texture coordinates of the undeformed mesh; deformation moves positions only.
    private func texCoordBuffer(for mesh: MetalMesh, key: TexCoordKey) -> MTLBuffer? {
        if let buffer = texCoordBuffers[key] {
            return buffer
        }
        guard let texCoords = mesh.float2Values(.texcoord(key.index)), !texCoords.isEmpty, let buffer = mesh.vertexBuffer.device.makeBuffer(bytes: texCoords, length: texCoords.count * MemoryLayout<SIMD2<Float>>.stride, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "Shadow Caster Texture Coordinates"
        texCoordBuffers[key] = buffer
        return buffer
    }

    // Joints (as floats) and weights per vertex, laid out as two float4s.
    private func influenceBuffer(for entry: SceneGraph.MeshEntry, key: InfluenceKey, device: MTLDevice) -> MTLBuffer? {
        if let buffer = influenceBuffers[key] {
            return buffer
        }
        let influences = entry.skinVertices.flatMap { [SIMD4<Float>($0.joints), $0.weights] }
        guard let buffer = device.makeBuffer(bytes: influences, length: influences.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "Shadow Caster Skin Influences"
        influenceBuffers[key] = buffer
        return buffer
    }
}

struct Packed3 {
    var x, y, z: Float

    init(_ value: SIMD3<Float>) {
        x = value.x
        y = value.y
        z = value.z
    }
}

// Vertex buffers identify a mesh's data; deformed meshes get new buffers, so they get new keys.
private struct PositionKey: Hashable {
    var buffers: [ObjectIdentifier]
    var offsets: [Int]
    var vertexCount: Int

    init(_ mesh: MetalMesh) {
        let sorted = mesh.vertexBuffers.sorted { $0.key < $1.key }
        buffers = sorted.map { ObjectIdentifier($0.value) }
        offsets = sorted.map { mesh.vertexBufferOffsets[$0.key] ?? 0 }
        vertexCount = mesh.vertexCount
    }
}

private struct TexCoordKey: Hashable {
    var position: PositionKey
    var index: Int
}

private struct InfluenceKey: Hashable {
    var node: SceneGraph.Node.ID
    var revision: Int
}

// Draws casters into each light's slice of the shadow map, with a second pipeline that
// skins vertices on the GPU.
struct ShadowCasterDepthPass: Element {
    var frame: Shadows.Frame

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let shaders = try ShadowCasterShaders.shared()
            let shadowMap = frame.shadowMap
            let depthTexture = shadowMap.depthTexture(forSubmission: submissionIndex)
            let isStatic = { (caster: Shadows.Caster) in if case .model = caster.placement { true } else { false } }
            let staticCasters = frame.casters.filter { isStatic($0) && $0.alpha == nil }
            let skinnedCasters = frame.casters.filter { !isStatic($0) && $0.alpha == nil }
            let staticAlphaCasters = frame.casters.filter { isStatic($0) && $0.alpha != nil }
            let skinnedAlphaCasters = frame.casters.filter { !isStatic($0) && $0.alpha != nil }
            return ForEach(Array(0..<shadowMap.lightCount), id: \.self) { lightIndex in
                let lightViewProjection = frame.casterViewProjections.indices.contains(lightIndex) ? frame.casterViewProjections[lightIndex] : shadowMap.lightViewProjectionMatrices[lightIndex]
                let sliceRender = shadowMap.sliceRenders.indices.contains(lightIndex) ? shadowMap.sliceRenders[lightIndex] : nil
                // Reversed depth: bias pushes towards 0.
                let depthBias = -(sliceRender?.depthBias ?? shadowMap.depthBias)
                let slopeScale = -(sliceRender?.slopeScale ?? shadowMap.slopeScale)
                try RenderPass(label: "Shadow Casters [\(lightIndex)]") {
                    if !staticCasters.isEmpty {
                        try pipeline("Shadow Casters", vertexShader: shaders.staticVertex, fragmentShader: shaders.fragment, vertexDescriptor: shaders.staticDescriptor, casters: staticCasters, lightViewProjection: lightViewProjection)
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: .greaterEqual, writes: true)
                    }
                    if !skinnedCasters.isEmpty {
                        try pipeline("Skinned Shadow Casters", vertexShader: shaders.skinnedVertex, fragmentShader: shaders.fragment, vertexDescriptor: shaders.skinnedDescriptor, casters: skinnedCasters, lightViewProjection: lightViewProjection)
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: .greaterEqual, writes: true)
                    }
                    if !staticAlphaCasters.isEmpty {
                        try pipeline("See-Through Shadow Casters", vertexShader: shaders.staticAlphaVertex, fragmentShader: shaders.alphaFragment, vertexDescriptor: shaders.staticAlphaDescriptor, casters: staticAlphaCasters, lightViewProjection: lightViewProjection)
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: .greaterEqual, writes: true)
                    }
                    if !skinnedAlphaCasters.isEmpty {
                        try pipeline("Skinned See-Through Shadow Casters", vertexShader: shaders.skinnedAlphaVertex, fragmentShader: shaders.alphaFragment, vertexDescriptor: shaders.skinnedAlphaDescriptor, casters: skinnedAlphaCasters, lightViewProjection: lightViewProjection)
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: .greaterEqual, writes: true)
                    }
                    let context = ShadowCasterContext(viewProjection: lightViewProjection, renderOrigin: frame.renderOrigin, resolution: shadowMap.resolution)
                    ForEach(Array(frame.customCasters.enumerated()), id: \.offset) { _, custom in
                        try custom.renderer.makeShadowCasterElement(entries: custom.entries, context: context)
                            .renderPipelineDescriptorTransformer { descriptor in
                                descriptor.colorAttachments[0].pixelFormat = .invalid
                            }
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: .greaterEqual, writes: true)
                    }
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].texture = nil
                    descriptor.colorAttachments[0].loadAction = .dontCare
                    descriptor.colorAttachments[0].storeAction = .dontCare
                    descriptor.depthAttachment.texture = depthTexture
                    descriptor.depthAttachment.slice = lightIndex
                    descriptor.depthAttachment.loadAction = .clear
                    descriptor.depthAttachment.clearDepth = 0
                    descriptor.depthAttachment.storeAction = .store
                    descriptor.renderTargetArrayLength = 1
                }
                // The mask pass samples the shadow map.
                .barrierAfterPass(after: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch])
            }
        }
    }

    private func pipeline(_ label: String, vertexShader: VertexShader, fragmentShader: FragmentShader, vertexDescriptor: MTLVertexDescriptor, casters: [Shadows.Caster], lightViewProjection: simd_float4x4) throws -> some Element {
        try casterPipeline(label, vertexShader: vertexShader, fragmentShader: fragmentShader, vertexDescriptor: vertexDescriptor, casters: casters, viewProjection: lightViewProjection, colorPixelFormat: .invalid)
    }
}

// Draws position-only geometry with `viewProjection`; shared by the shadow map and the receiver mask.
func casterPipeline(_ label: String, vertexShader: VertexShader, fragmentShader: FragmentShader, vertexDescriptor: MTLVertexDescriptor, casters: [Shadows.Caster], viewProjection: simd_float4x4, colorPixelFormat: MTLPixelFormat) throws -> some Element {
    try RenderPipeline(label: label, vertexShader: vertexShader, fragmentShader: fragmentShader) {
        ForEach(Array(casters.enumerated()), id: \.offset) { _, caster in
            drawCaster(caster)
        }
        .parameter("lightViewProjection", functionType: .vertex, value: viewProjection)
    }
    .vertexDescriptor(vertexDescriptor)
    .renderPipelineDescriptorTransformer { descriptor in
        descriptor.colorAttachments[0].pixelFormat = colorPixelFormat
        descriptor.inputPrimitiveTopology = .triangle
    }
}

private func drawCaster(_ caster: Shadows.Caster) -> AnyElement {
    let draw = Draw(
        primitiveType: caster.submesh.primitiveType,
        indexBuffer: caster.submesh.indexBuffer,
        indexType: caster.submesh.indexType,
        indexCount: caster.submesh.indexCount,
        indexBufferOffset: caster.submesh.indexBufferOffset
    )
    .vertexBuffer(caster.positions, index: 0)
    let placed = switch caster.placement {
    case .model(let modelMatrix):
        draw.parameter("modelMatrix", functionType: .vertex, value: modelMatrix).eraseToAnyElement()
    case let .skinned(influences, jointMatrices):
        draw
            .vertexBuffer(influences, index: 1)
            .parameter("jointMatrices", functionType: .vertex, values: jointMatrices)
            .eraseToAnyElement()
    }
    guard let (alpha, texCoords) = caster.alpha, let shaders = try? ShadowCasterShaders.shared() else {
        return placed
    }
    return placed
        .vertexBuffer(texCoords, index: ShadowCasterShaders.texCoordBufferIndex)
        .parameter("alpha", functionType: .fragment, value: SIMD4<Float>(alpha.opacity, alpha.cutoff, 0, 0))
        .parameter("uvTransform", functionType: .fragment, value: alpha.texCoordTransform)
        .parameter("alphaTexture", functionType: .fragment, texture: alpha.texture ?? shaders.whiteTexture)
        .parameter("alphaSampler", functionType: .fragment, samplerState: alpha.sampler ?? shaders.sampler)
        .eraseToAnyElement()
}

// From ShadowCasters.metal in SceneSprocketsShaders, loaded once.
struct ShadowCasterShaders {
    var staticVertex: VertexShader
    var skinnedVertex: VertexShader
    var fragment: FragmentShader
    var mark: FragmentShader
    var staticDescriptor: MTLVertexDescriptor
    var skinnedDescriptor: MTLVertexDescriptor
    var staticAlphaVertex: VertexShader
    var skinnedAlphaVertex: VertexShader
    var alphaFragment: FragmentShader
    var staticAlphaDescriptor: MTLVertexDescriptor
    var skinnedAlphaDescriptor: MTLVertexDescriptor
    var whiteTexture: MTLTexture
    var sampler: MTLSamplerState

    static let texCoordBufferIndex = 5

    nonisolated(unsafe) private static var cached: Self?
    private static let lock = NSLock()

    static func shared() throws -> Self {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("ShadowCasters")
        let staticDescriptor = MTLVertexDescriptor()
        staticDescriptor.attributes[0].format = .float3
        staticDescriptor.layouts[0].stride = 12
        let skinnedDescriptor = MTLVertexDescriptor()
        skinnedDescriptor.attributes[0].format = .float3
        skinnedDescriptor.layouts[0].stride = 12
        skinnedDescriptor.attributes[1].format = .float4
        skinnedDescriptor.attributes[1].bufferIndex = 1
        skinnedDescriptor.attributes[2].format = .float4
        skinnedDescriptor.attributes[2].bufferIndex = 1
        skinnedDescriptor.attributes[2].offset = 16
        skinnedDescriptor.layouts[1].stride = 32
        func withTexCoords(_ descriptor: MTLVertexDescriptor) -> MTLVertexDescriptor {
            // swiftlint:disable:next force_cast - MTLVertexDescriptor copies are always MTLVertexDescriptor
            let copy = descriptor.copy() as! MTLVertexDescriptor
            copy.attributes[3].format = .float2
            copy.attributes[3].bufferIndex = texCoordBufferIndex
            copy.layouts[texCoordBufferIndex].stride = 8
            return copy
        }
        let device = _MTLCreateSystemDefaultDevice()
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let whiteTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw MetalSprocketsError.resourceCreationFailure("Shadow caster white texture")
        }
        whiteTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8](repeating: 255, count: 4), bytesPerRow: 4)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .repeat
        samplerDescriptor.tAddressMode = .repeat
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MetalSprocketsError.resourceCreationFailure("Shadow caster sampler")
        }
        let shaders = Self(
            staticVertex: try library.vertex_static,
            skinnedVertex: try library.vertex_skinned,
            fragment: try library.fragment_depth,
            mark: try library.fragment_mark,
            staticDescriptor: staticDescriptor,
            skinnedDescriptor: skinnedDescriptor,
            staticAlphaVertex: try library.vertex_static_alpha,
            skinnedAlphaVertex: try library.vertex_skinned_alpha,
            alphaFragment: try library.fragment_alpha,
            staticAlphaDescriptor: withTexCoords(staticDescriptor),
            skinnedAlphaDescriptor: withTexCoords(skinnedDescriptor),
            whiteTexture: whiteTexture,
            sampler: sampler
        )
        cached = shaders
        return shaders
    }
}
