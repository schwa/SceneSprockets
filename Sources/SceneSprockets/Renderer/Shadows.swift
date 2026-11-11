import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSupport
import ModelIO
import SceneSprocketsShaders
import simd
import SwiftMesh

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

/// Shadow-mapped shadows from directional, spot and point lights, for every renderer: casters are drawn into a shadow
/// map from each light. Blinn-Phong, PBR and shader materials with `samplesShadows` sample it per light while shading,
/// so a light only darkens what it lights; other materials are darkened in screen space after the scene pass, by every
/// light's shadow at once. Keep one instance across frames (it holds the shadow map and caster buffers) and pass it to
/// SceneGraphElement or SceneView.
/// 
/// The shadow map has 8 slices: a directional or spot light uses one, a point light six; a light that does not fit
/// casts none and is counted in `droppedLightCount`. Meshes with `castsShadow: false` cast none; meshes with
/// `receivesShadow: false` receive none.
/// The view's color texture needs `.shaderWrite` and its depth texture `.shaderRead` usage (see
/// `requiredColorUsage`); otherwise no shadows are drawn.
public final class SceneGraphShadows {
    /// Usage the view's color texture needs: the shadow and post-processing passes write it from compute.
    public static let requiredColorUsage: MTLTextureUsage = [.renderTarget, .shaderRead, .shaderWrite]
    /// Usage the view's depth texture needs: the passes sample it.
    public static let requiredDepthUsage: MTLTextureUsage = [.renderTarget, .shaderRead]

    /// 0 leaves shadowed pixels unchanged, 1 multiplies them by `color`.
    public var intensity: Float
    /// Linear RGB multiplied into shadowed pixels, like SCNLight.shadowColor; black darkens.
    public var color: SIMD3<Float>
    /// Soft-shadow filter half-size in shadow map texels, like SCNLight.shadowRadius: 1 filters 3x3, 0 is hard.
    /// Cost grows with (2 * softness + 1)^2 per light.
    public var softness: Int
    /// The width and height of each shadow map slice, in texels.
    public var resolution: Int
    /// The constant depth bias when the shadow map is drawn.
    public var depthBias: Float
    /// The depth bias that increases with the slope of the surface, per texel of `softness`.
    public var slopeScale: Float
    /// World-space push of directional-light casters away from the light, in shadow map texels. The hardware
    /// constant bias is tiny with depth32Float, so this is what stops acne on lit faces (#60).
    public var depthOffsetTexels: Float
    /// Lights that cast no shadow in the last frame because their views did not fit in the 8 slices.
    public private(set) var droppedLightCount = 0

    private var shadowMap: SceneGraphShadowMap?
    private var positionBuffers: [PositionKey: MTLBuffer] = [:]
    private var influenceBuffers: [InfluenceKey: MTLBuffer] = [:]
    // One per frame in flight, like the shadow map's depth textures.
    private var receiverMasks: [MTLTexture] = []

    /// Creates shadow settings. Keep one instance for each view, because it keeps the shadow map between frames.
    public init(intensity: Float = 0.6, color: SIMD3<Float> = .zero, softness: Int = 1, resolution: Int = 2_048, depthBias: Float = 2, slopeScale: Float = 2, depthOffsetTexels: Float = 1.5) {
        self.depthOffsetTexels = depthOffsetTexels
        self.intensity = intensity
        self.color = color
        self.softness = softness
        self.resolution = resolution
        self.depthBias = depthBias
        self.slopeScale = slopeScale
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
    }

    struct Frame {
        var shadowMap: SceneGraphShadowMap
        var casters: [Caster]
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
    func prepare(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext, bounds: BoundingBox3D?, viewSize: (width: Int, height: Int)? = nil) throws -> Frame? {
        guard let bounds else {
            return nil
        }
        // Everything here is camera-relative (#257): lights, bounds and casters are shifted by the camera position in
        // Double, so the light views map camera-relative positions and stay precise far from the world origin.
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let relativeBounds = BoundingBox3D(min: cameraRelative(bounds.min, to: cameraPosition), max: cameraRelative(bounds.max, to: cameraPosition))
        let relativeLights = context.lights.map { (worldTransform: $0.worldTransform.cameraRelative(to: cameraPosition), light: $0.light) }
        let (views, dropped, slices) = shadowViewsAndDroppedLights(lights: relativeLights, bounds: relativeBounds)
        droppedLightCount = dropped
        guard !views.isEmpty else {
            return nil
        }
        var usedKeys = Set<PositionKey>()
        var usedInfluences = Set<InfluenceKey>()
        var casters: [Caster] = []
        var nonReceivers: [Caster] = []
        // Position-only geometry for `entry`, as drawn this frame.
        func caster(for entry: SceneGraph.MeshEntry) -> Caster? {
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
                return Caster(positions: positions, submesh: submesh, placement: .model((deformed?.modelMatrix ?? entry.worldTransform).cameraRelative(to: cameraPosition)))
            }
            let influenceKey = InfluenceKey(node: ObjectIdentifier(entry.node), revision: entry.node.revision.structure)
            usedInfluences.insert(influenceKey)
            guard let influences = influenceBuffer(for: entry.node, key: influenceKey, device: mesh.vertexBuffer.device) else {
                return nil
            }
            return Caster(positions: positions, submesh: submesh, placement: .skinned(influences: influences, jointMatrices: skin.jointMatrices().map { $0.cameraRelative(to: cameraPosition) }))
        }
        // Materials that sample shadows themselves are kept out of the screen-space mask, like non-receivers.
        let skipsMask = { (entry: SceneGraph.MeshEntry) in !entry.receivesShadow || (entry.material as? any SamplesShadowsInShader)?.samplesShadowsInShader == true }
        let masksEverything = entries.allSatisfy(skipsMask)
        for entry in entries {
            if entry.castsShadow, let caster = caster(for: entry) {
                casters.append(caster)
            }
            if !masksEverything, skipsMask(entry), let caster = caster(for: entry) {
                nonReceivers.append(caster)
            }
        }
        positionBuffers = positionBuffers.filter { usedKeys.contains($0.key) }
        influenceBuffers = influenceBuffers.filter { usedInfluences.contains($0.key) }
        guard !casters.isEmpty else {
            return nil
        }

        if shadowMap?.lightCount != views.count || shadowMap?.resolution != resolution {
            shadowMap = try SceneGraphShadowMap(resolution: resolution, lightCount: views.count)
        }
        guard var shadowMap else {
            return nil
        }
        shadowMap.depthBias = depthBias
        // The PCF kernel compares one receiver depth against texels up to `softness` away, so a sloped receiver needs a
        // slope bias that grows with it, or it shadows itself (#366).
        shadowMap.slopeScale = slopeScale * Float(max(softness, 1))
        shadowMap.lightViewProjectionMatrices = views
        self.shadowMap = shadowMap
        let casterViews = views.map(casterViewProjection)
        guard !nonReceivers.isEmpty, let viewSize else {
            return Frame(shadowMap: shadowMap, casters: casters, casterViewProjections: casterViews, lightSlices: slices, masksEverything: masksEverything)
        }
        return Frame(shadowMap: shadowMap, casters: casters, casterViewProjections: casterViews, nonReceivers: (nonReceivers, try receiverMasks(width: viewSize.width, height: viewSize.height, count: shadowMap.depthTextures.count)), lightSlices: slices, masksEverything: masksEverything)
    }

    // `view` with caster depth pushed `depthOffsetTexels` texels away from the light. Only orthographic (directional)
    // views; perspective views are returned unchanged and rely on the hardware bias.
    func casterViewProjection(_ view: simd_float4x4) -> simd_float4x4 {
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

    // One view-projection per shadow map slice, up to SCENE_SHADOW_MAX_SLICES: directional lights get an orthographic view
    // fitted to `bounds`, spot lights a perspective view of their outer cone, point lights six 90° views. All use
    // reversed depth, like ShadowMap's default.
    func shadowViews(lights: [(worldTransform: simd_float4x4, light: Light)], bounds: BoundingBox3D) -> [simd_float4x4] {
        shadowViewsAndDroppedLights(lights: lights, bounds: bounds).views
    }

    // A light whose views do not all fit in the remaining slices is dropped whole; later lights may still fit.
    // `slices` is parallel to `lights`: the slices of each light's views, empty for lights that cast none.
    func shadowViewsAndDroppedLights(lights: [(worldTransform: simd_float4x4, light: Light)], bounds: BoundingBox3D) -> (views: [simd_float4x4], dropped: Int, slices: [Range<Int>]) {
        let center = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 0.01)
        var views: [simd_float4x4] = []
        var dropped = 0
        var slices: [Range<Int>] = []
        for (transform, light) in lights {
            guard light.castsShadow else {
                slices.append(0..<0)
                continue
            }
            var lightViews: [simd_float4x4] = []
            let position = transform.columns.3.xyz
            let forward = simd_normalize(-transform.columns.2.xyz)
            // Far enough to reach the whole scene from the light.
            let far = max(simd_distance(position, center) + radius, 0.1)
            let near = max(far * 0.001, 0.01)
            switch light.type {
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
            if views.count + lightViews.count <= Int(SCENE_SHADOW_MAX_SLICES) {
                slices.append(views.count..<(views.count + lightViews.count))
                views += lightViews
            } else {
                slices.append(0..<0)
                dropped += 1
            }
        }
        return (views, dropped, slices)
    }

    private func gpuSkin(of entry: SceneGraph.MeshEntry) -> SceneGraph.Skin? {
        let node = entry.node
        guard let skin = node.skin, skin.joints.count == skin.inverseBindMatrices.count, node.skinVertices.count == entry.mesh.vertexCount else {
            return nil
        }
        let hasMorphs = node.morphTargets.contains { $0.isValid(vertexCount: entry.mesh.vertexCount) } && node.morphWeights.contains { $0 != 0 }
        return hasMorphs ? nil : skin
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

    // Joints (as floats) and weights per vertex, laid out as two float4s.
    private func influenceBuffer(for node: SceneGraph.Node, key: InfluenceKey, device: MTLDevice) -> MTLBuffer? {
        if let buffer = influenceBuffers[key] {
            return buffer
        }
        let influences = node.skinVertices.flatMap { [SIMD4<Float>($0.joints), $0.weights] }
        guard let buffer = device.makeBuffer(bytes: influences, length: influences.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "Shadow Caster Skin Influences"
        influenceBuffers[key] = buffer
        return buffer
    }
}

private struct Packed3 {
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

private struct InfluenceKey: Hashable {
    var node: ObjectIdentifier
    var revision: Int
}

// Draws casters into each light's slice of the shadow map, with a second pipeline that
// skins vertices on the GPU.
struct ShadowCasterDepthPass: Element {
    var frame: SceneGraphShadows.Frame

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let shaders = try ShadowCasterShaders.shared()
            let shadowMap = frame.shadowMap
            // Reversed depth: bias pushes towards 0.
            let depthBias = -shadowMap.depthBias
            let slopeScale = -shadowMap.slopeScale
            let depthTexture = shadowMap.depthTexture(forSubmission: submissionIndex)
            let staticCasters = frame.casters.filter { if case .model = $0.placement { true } else { false } }
            let skinnedCasters = frame.casters.filter { if case .skinned = $0.placement { true } else { false } }
            return ForEach(Array(0..<shadowMap.lightCount), id: \.self) { lightIndex in
                let lightViewProjection = frame.casterViewProjections.indices.contains(lightIndex) ? frame.casterViewProjections[lightIndex] : shadowMap.lightViewProjectionMatrices[lightIndex]
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

    private func pipeline(_ label: String, vertexShader: VertexShader, fragmentShader: FragmentShader, vertexDescriptor: MTLVertexDescriptor, casters: [SceneGraphShadows.Caster], lightViewProjection: simd_float4x4) throws -> some Element {
        try casterPipeline(label, vertexShader: vertexShader, fragmentShader: fragmentShader, vertexDescriptor: vertexDescriptor, casters: casters, viewProjection: lightViewProjection, colorPixelFormat: .invalid)
    }
}

// Draws position-only geometry with `viewProjection`; shared by the shadow map and the receiver mask.
func casterPipeline(_ label: String, vertexShader: VertexShader, fragmentShader: FragmentShader, vertexDescriptor: MTLVertexDescriptor, casters: [SceneGraphShadows.Caster], viewProjection: simd_float4x4, colorPixelFormat: MTLPixelFormat) throws -> some Element {
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

private func drawCaster(_ caster: SceneGraphShadows.Caster) -> AnyElement {
    let draw = Draw(
        primitiveType: caster.submesh.primitiveType,
        indexBuffer: caster.submesh.indexBuffer,
        indexType: caster.submesh.indexType,
        indexCount: caster.submesh.indexCount,
        indexBufferOffset: caster.submesh.indexBufferOffset
    )
    .vertexBuffer(caster.positions, index: 0)
    switch caster.placement {
    case .model(let modelMatrix):
        return draw.parameter("modelMatrix", functionType: .vertex, value: modelMatrix).eraseToAnyElement()
    case let .skinned(influences, jointMatrices):
        return draw
            .vertexBuffer(influences, index: 1)
            .parameter("jointMatrices", functionType: .vertex, values: jointMatrices)
            .eraseToAnyElement()
    }
}

// From ShadowCasters.metal in SceneSprocketsShaders, loaded once.
struct ShadowCasterShaders {
    var staticVertex: VertexShader
    var skinnedVertex: VertexShader
    var fragment: FragmentShader
    var mark: FragmentShader
    var staticDescriptor: MTLVertexDescriptor
    var skinnedDescriptor: MTLVertexDescriptor

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
        let shaders = Self(
            staticVertex: try library.vertex_static,
            skinnedVertex: try library.vertex_skinned,
            fragment: try library.fragment_depth,
            mark: try library.fragment_mark,
            staticDescriptor: staticDescriptor,
            skinnedDescriptor: skinnedDescriptor
        )
        cached = shaders
        return shaders
    }
}
