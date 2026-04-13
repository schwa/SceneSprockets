import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphShaders
import ModelIO
import SwiftMesh
import simd

// Shadow-mapped shadows from directional, spot and point lights, for every renderer: casters are drawn into a shadow map from each
// light, then shadowed pixels are darkened in screen space after the scene pass. Keep one instance across frames
// (it holds the shadow map and caster buffers) and pass it to SceneGraphElement or SceneView.
//
// The shadow map has 8 slices: a directional or spot light uses one, a point light six; lights past that cast
// none. Meshes with `castsShadow: false` cast none. `receivesShadow` is not
// honored: the screen-space mask darkens every surface behind a caster.
// The view's color texture needs `.shaderWrite` and its depth texture `.shaderRead` usage (see
// `ShadowContext.requiredColorUsage`); otherwise no shadows are drawn.
public final class SceneGraphShadows {
    // 0 leaves shadowed pixels unchanged, 1 makes them black.
    public var intensity: Float
    public var resolution: Int
    public var depthBias: Float
    public var slopeScale: Float

    private var shadowMap: ShadowMap?
    private var positionBuffers: [PositionKey: MTLBuffer] = [:]
    private var influenceBuffers: [InfluenceKey: MTLBuffer] = [:]

    public init(intensity: Float = 0.6, resolution: Int = 2_048, depthBias: Float = 2, slopeScale: Float = 2) {
        self.intensity = intensity
        self.resolution = resolution
        self.depthBias = depthBias
        self.slopeScale = slopeScale
    }

    struct Caster {
        enum Placement {
            case model(simd_float4x4)
            // Skinned on the GPU: rest positions moved by these joint matrices (joint world * inverse bind).
            case skinned(influences: MTLBuffer, jointMatrices: [simd_float4x4])
        }

        var positions: MTLBuffer
        var submesh: MetalMesh.Submesh
        var placement: Placement
    }

    struct Frame {
        var shadowMap: ShadowMap
        var casters: [Caster]
    }

    // Nil when nothing casts or there is no light.
    func prepare(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext, bounds: BoundingBox?) throws -> Frame? {
        guard let bounds else {
            return nil
        }
        let views = shadowViews(lights: context.lights, bounds: bounds)
        guard !views.isEmpty else {
            return nil
        }
        var usedKeys = Set<PositionKey>()
        var usedInfluences = Set<InfluenceKey>()
        var casters: [Caster] = []
        for entry in entries where entry.castsShadow {
            // Skin on the GPU when there is a valid skin and no active morph; otherwise use CPU-deformed positions.
            let skin = gpuSkin(of: entry)
            let deformed = skin == nil ? entry.deformed(revision: context.revision) : nil
            let mesh = deformed?.mesh ?? entry.mesh
            let submesh = mesh.submeshes[entry.submeshIndex]
            guard submesh.primitiveType == .triangle || submesh.primitiveType == .triangleStrip else {
                continue
            }
            let key = PositionKey(mesh)
            usedKeys.insert(key)
            guard let positions = positionBuffer(for: mesh, key: key) else {
                continue
            }
            if let skin {
                let influenceKey = InfluenceKey(node: ObjectIdentifier(entry.node), revision: entry.node.revision.structure)
                usedInfluences.insert(influenceKey)
                guard let influences = influenceBuffer(for: entry.node, key: influenceKey, device: mesh.vertexBuffer.device) else {
                    continue
                }
                casters.append(Caster(positions: positions, submesh: submesh, placement: .skinned(influences: influences, jointMatrices: skin.jointMatrices())))
            } else {
                casters.append(Caster(positions: positions, submesh: submesh, placement: .model(deformed?.modelMatrix ?? entry.worldTransform)))
            }
        }
        positionBuffers = positionBuffers.filter { usedKeys.contains($0.key) }
        influenceBuffers = influenceBuffers.filter { usedInfluences.contains($0.key) }
        guard !casters.isEmpty else {
            return nil
        }

        if shadowMap?.lightCount != views.count || shadowMap?.resolution != resolution {
            shadowMap = try ShadowMap(resolution: resolution, lightCount: views.count)
        }
        guard var shadowMap else {
            return nil
        }
        shadowMap.depthBias = depthBias
        shadowMap.slopeScale = slopeScale
        shadowMap.lightViewProjectionMatrices = views
        self.shadowMap = shadowMap
        return Frame(shadowMap: shadowMap, casters: casters)
    }

    // One view-projection per shadow map slice, up to MAX_SHADOW_LIGHTS: directional lights get an orthographic view
    // fitted to `bounds`, spot lights a perspective view of their outer cone, point lights six 90° views. All use
    // reversed depth, like ShadowMap's default.
    func shadowViews(lights: [(worldTransform: simd_float4x4, light: Light)], bounds: BoundingBox) -> [simd_float4x4] {
        let center = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 0.01)
        var views: [simd_float4x4] = []
        for (transform, light) in lights {
            let position = SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
            let forward = simd_normalize(-SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z))
            // Far enough to reach the whole scene from the light.
            let far = max(simd_distance(position, center) + radius, 0.1)
            let near = max(far * 0.001, 0.01)
            switch light.type {
            case .directional:
                let eye = center - forward * radius * 2
                views.append(orthographic(halfSize: radius, near: radius * 0.5, far: radius * 3.5) * viewMatrix(eye: eye, forward: forward))
            case .spot:
                let fieldOfView = min(max(light.outerConeAngle * 2, 0.01), .pi * 0.95)
                views.append(perspective(fieldOfView: fieldOfView, near: near, far: far) * viewMatrix(eye: position, forward: forward))
            case .point:
                let faces: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
                for face in faces {
                    views.append(perspective(fieldOfView: .pi / 2, near: near, far: far) * viewMatrix(eye: position, forward: face))
                }
            default:
                continue
            }
        }
        return Array(views.prefix(Int(MAX_SHADOW_LIGHTS)))
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

// World to view space for a viewer at `eye` looking along `forward` (view -Z).
func viewMatrix(eye: SIMD3<Float>, forward: SIMD3<Float>) -> simd_float4x4 {
    let up: SIMD3<Float> = abs(forward.y) > 0.99 ? [0, 0, 1] : [0, 1, 0]
    let back = -simd_normalize(forward)
    let right = simd_normalize(simd_cross(up, back))
    let trueUp = simd_cross(back, right)
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(trueUp, 0), SIMD4(back, 0), SIMD4(eye, 1))).inverse
}

// Reversed depth: near maps to 1, far to 0.
func perspective(fieldOfView: Float, near: Float, far: Float) -> simd_float4x4 {
    let scale = 1 / tan(fieldOfView / 2)
    let a = near / (far - near)
    return simd_float4x4(columns: ([scale, 0, 0, 0], [0, scale, 0, 0], [0, 0, a, -1], [0, 0, a * far, 0]))
}

// Reversed depth: near maps to 1, far to 0.
func orthographic(halfSize: Float, near: Float, far: Float) -> simd_float4x4 {
    let depth = far - near
    return simd_float4x4(columns: ([1 / halfSize, 0, 0, 0], [0, 1 / halfSize, 0, 0], [0, 0, 1 / depth, 0], [0, 0, far / depth, 1]))
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

// Draws casters into each light's slice of the shadow map, like ShadowMapDepthPass, but with a second pipeline that
// skins vertices on the GPU.
struct ShadowCasterDepthPass: Element {
    var frame: SceneGraphShadows.Frame

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let shaders = try ShadowCasterShaders.shared()
            let shadowMap = frame.shadowMap
            let inverseZ = shadowMap.useInverseZ
            let depthBias = inverseZ ? -shadowMap.depthBias : shadowMap.depthBias
            let slopeScale = inverseZ ? -shadowMap.slopeScale : shadowMap.slopeScale
            let depthTexture = shadowMap.depthTexture(forSubmission: submissionIndex)
            let staticCasters = frame.casters.filter { if case .model = $0.placement { true } else { false } }
            let skinnedCasters = frame.casters.filter { if case .skinned = $0.placement { true } else { false } }
            return ForEach(Array(0..<shadowMap.lightCount), id: \.self) { lightIndex in
                let lightViewProjection = shadowMap.lightViewProjectionMatrices[lightIndex]
                try RenderPass(label: "Shadow Casters [\(lightIndex)]") {
                    if !staticCasters.isEmpty {
                        try pipeline("Shadow Casters", vertexShader: shaders.staticVertex, fragmentShader: shaders.fragment, vertexDescriptor: shaders.staticDescriptor, casters: staticCasters, lightViewProjection: lightViewProjection)
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: inverseZ ? .greaterEqual : .lessEqual, enabled: true)
                    }
                    if !skinnedCasters.isEmpty {
                        try pipeline("Skinned Shadow Casters", vertexShader: shaders.skinnedVertex, fragmentShader: shaders.fragment, vertexDescriptor: shaders.skinnedDescriptor, casters: skinnedCasters, lightViewProjection: lightViewProjection)
                            .depthBias(depthBias, slopeScale: slopeScale)
                            .depthCompare(function: inverseZ ? .greaterEqual : .lessEqual, enabled: true)
                    }
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].texture = nil
                    descriptor.colorAttachments[0].loadAction = .dontCare
                    descriptor.colorAttachments[0].storeAction = .dontCare
                    descriptor.depthAttachment.texture = depthTexture
                    descriptor.depthAttachment.slice = lightIndex
                    descriptor.depthAttachment.loadAction = .clear
                    descriptor.depthAttachment.clearDepth = inverseZ ? 0 : 1
                    descriptor.depthAttachment.storeAction = .store
                    descriptor.renderTargetArrayLength = 1
                }
                // The mask pass samples the shadow map.
                .barrierAfterPass(after: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch])
            }
        }
    }

    private func pipeline(_ label: String, vertexShader: VertexShader, fragmentShader: FragmentShader, vertexDescriptor: MTLVertexDescriptor, casters: [SceneGraphShadows.Caster], lightViewProjection: simd_float4x4) throws -> some Element {
        try RenderPipeline(label: label, vertexShader: vertexShader, fragmentShader: fragmentShader) {
            ForEach(Array(casters.enumerated()), id: \.offset) { _, caster in
                try draw(caster)
            }
            .parameter("lightViewProjection", functionType: .vertex, value: lightViewProjection)
        }
        .vertexDescriptor(vertexDescriptor)
        .renderPipelineDescriptorTransformer { descriptor in
            descriptor.colorAttachments[0].pixelFormat = .invalid
            descriptor.inputPrimitiveTopology = .triangle
        }
    }

    private func draw(_ caster: SceneGraphShadows.Caster) throws -> AnyElement {
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
}

// From ShadowCasters.metal in MetalSprocketsSceneGraphShaders, loaded once.
struct ShadowCasterShaders {
    var staticVertex: VertexShader
    var skinnedVertex: VertexShader
    var fragment: FragmentShader
    var staticDescriptor: MTLVertexDescriptor
    var skinnedDescriptor: MTLVertexDescriptor

    nonisolated(unsafe) private static var cached: ShadowCasterShaders?
    private static let lock = NSLock()

    static func shared() throws -> ShadowCasterShaders {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .metalSprocketsSceneGraphShaders()).namespaced("ShadowCasters")
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
        let shaders = ShadowCasterShaders(
            staticVertex: try library.vertex_static,
            skinnedVertex: try library.vertex_skinned,
            fragment: try library.fragment_depth,
            staticDescriptor: staticDescriptor,
            skinnedDescriptor: skinnedDescriptor
        )
        cached = shaders
        return shaders
    }
}
