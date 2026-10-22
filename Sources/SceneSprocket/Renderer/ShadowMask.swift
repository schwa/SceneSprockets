import Foundation
import Metal
import MetalSprockets
import SceneSprocketShaders
import simd

// Darkens shadowed pixels after the scene pass, skipping meshes that do not receive shadows. Siblings of the scene
// pass: the receiver mask is a render pass and the mask a compute pass.
struct SceneShadowMaskPass: Element {
    var frame: SceneGraphShadows.Frame
    var sceneDepthTexture: MTLTexture
    var outputTexture: MTLTexture
    var viewProjection: simd_float4x4
    var intensity: Float
    var color: SIMD3<Float>
    var radius: Int

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let shadowMap = frame.shadowMap
            var uniforms = SceneShadowMaskUniforms()
            uniforms.inverseViewProjection = viewProjection.inverse
            uniforms.sliceCount = Int32(min(shadowMap.lightCount, Int(SCENE_SHADOW_MAX_SLICES)))
            uniforms.mapSize = Float(shadowMap.resolution)
            uniforms.intensity = intensity
            uniforms.color = color
            uniforms.radius = Int32(max(radius, 0))
            withUnsafeMutableBytes(of: &uniforms.sliceViewProjections) { buffer in
                let slices = buffer.bindMemory(to: simd_float4x4.self)
                for (index, matrix) in shadowMap.lightViewProjectionMatrices.prefix(slices.count).enumerated() {
                    slices[index] = matrix
                }
            }
            let mask = frame.nonReceivers.map { $0.masks[Int(submissionIndex % UInt64($0.masks.count))] }
            let kernel = try SceneShadowMaskShaders.kernel(hasReceiverMask: mask != nil)
            return try MetalSprockets.Group {
                if let nonReceivers = frame.nonReceivers, let mask {
                    try receiverMaskPass(casters: nonReceivers.casters, mask: mask)
                }
                try ComputePass(label: "Shadow Mask") {
                    // Wait for the scene (and the receiver mask) to finish writing.
                    QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                    try ComputePipeline(label: "Shadow Mask", computeKernel: kernel) {
                        let dispatch = try ComputeDispatch(
                            threadsPerGrid: MTLSize(width: outputTexture.width, height: outputTexture.height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                        )
                        .parameter("sceneDepth", texture: sceneDepthTexture)
                        .parameter("shadowMap", texture: shadowMap.depthTexture(forSubmission: submissionIndex))
                        .parameter("outputTexture", texture: outputTexture)
                        .parameter("shadowSampler", samplerState: shadowMap.sampler)
                        .parameter("uniforms", value: uniforms)
                        if let mask {
                            dispatch.parameter("receiverMask", texture: mask)
                        } else {
                            dispatch
                        }
                    }
                }
            }
        }
    }

    // Marks the visible pixels of non-receivers: drawn against the scene depth (not written), nudged towards the
    // camera so they pass where they are the front surface.
    private func receiverMaskPass(casters: [SceneGraphShadows.Caster], mask: MTLTexture) throws -> some Element {
        let shaders = try ShadowCasterShaders.shared()
        let staticCasters = casters.filter { if case .model = $0.placement { true } else { false } }
        let skinnedCasters = casters.filter { if case .skinned = $0.placement { true } else { false } }
        return try RenderPass(label: "Shadow Receiver Mask") {
            QueueBarrier(after: [.fragment, .dispatch], before: [.vertex, .fragment])
            if !staticCasters.isEmpty {
                try casterPipeline("Non-Receivers", vertexShader: shaders.staticVertex, fragmentShader: shaders.mark, vertexDescriptor: shaders.staticDescriptor, casters: staticCasters, viewProjection: viewProjection, colorPixelFormat: mask.pixelFormat)
                    .depthBias(Self.depthBias, slopeScale: Self.slopeScale)
                    .depthCompare(function: .greaterEqual, writes: false)
            }
            if !skinnedCasters.isEmpty {
                try casterPipeline("Skinned Non-Receivers", vertexShader: shaders.skinnedVertex, fragmentShader: shaders.mark, vertexDescriptor: shaders.skinnedDescriptor, casters: skinnedCasters, viewProjection: viewProjection, colorPixelFormat: mask.pixelFormat)
                    .depthBias(Self.depthBias, slopeScale: Self.slopeScale)
                    .depthCompare(function: .greaterEqual, writes: false)
            }
        }
        .renderPassDescriptorModifier { descriptor in
            descriptor.colorAttachments[0].texture = mask
            descriptor.colorAttachments[0].loadAction = .clear
            descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
            descriptor.colorAttachments[0].storeAction = .store
            descriptor.depthAttachment.texture = sceneDepthTexture
            descriptor.depthAttachment.loadAction = .load
            descriptor.depthAttachment.storeAction = .store
        }
    }

    // Reversed depth: positive bias moves towards the camera.
    private static let depthBias: Float = 4
    private static let slopeScale: Float = 2
}

enum SceneShadowMaskShaders {
    nonisolated(unsafe) private static var cached: [Bool: ComputeKernel] = [:]
    private static let lock = NSLock()

    static func kernel(hasReceiverMask: Bool) throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let kernel = cached[hasReceiverMask] {
            return kernel
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketShaders()).namespaced("SceneShadowMask")
        var constants = FunctionConstants()
        constants["HAS_RECEIVER_MASK"] = .bool(hasReceiverMask)
        let kernel = try library.function(named: "shadow_mask_compute", type: ComputeKernel.self, constants: constants)
        cached[hasReceiverMask] = kernel
        return kernel
    }
}
