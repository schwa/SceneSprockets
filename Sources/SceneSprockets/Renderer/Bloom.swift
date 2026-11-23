import Foundation
import Metal
import MetalSprockets
import MetalSprocketsLighting
import MetalSprocketsSupport
import MetalSupport
import SceneSprocketsShaders

// The HDR scene path (#640): the scene's linear color, and the bloom chain, cached by size.
enum HDRTargets {
    struct Targets {
        var scene: MTLTexture
        // Half-size and smaller, one texture per level.
        var bloomLevels: [MTLTexture]
    }

    nonisolated(unsafe) private static var cached: [SIMD3<Int>: Targets] = [:]
    private static let lock = NSLock()

    static func targets(device: MTLDevice, width: Int, height: Int, levels: Int) throws -> Targets {
        lock.lock()
        defer { lock.unlock() }
        let key = SIMD3(width, height, levels)
        if let targets = cached[key], targets.scene.device === device {
            return targets
        }
        func make(width: Int, height: Int, usage: MTLTextureUsage, label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: max(width, 1), height: max(height, 1), mipmapped: false)
            descriptor.usage = usage
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw CocoaError(.featureUnsupported)
            }
            texture.label = label
            return texture
        }
        let scene = try make(width: width, height: height, usage: [.renderTarget, .shaderRead, .shaderWrite], label: "HDR Scene")
        let bloomLevels = try (1...max(levels, 1)).map { level in
            try make(width: width >> level, height: height >> level, usage: [.shaderRead, .shaderWrite], label: "Bloom \(level)")
        }
        let targets = Targets(scene: scene, bloomLevels: bloomLevels)
        cached = [key: targets]
        return targets
    }

    static let sampler: MTLSamplerState? = {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        return _MTLCreateSystemDefaultDevice().makeSamplerState(descriptor: descriptor)
    }()
}

// Bloom from the HDR scene, then exposure and tone mapping into the view's color.
struct BloomPass: Element {
    var settings: SceneGraph.PostProcessing.Bloom
    var targets: HDRTargets.Targets
    var output: MTLTexture
    var exposure: Float
    var toneMapping: LightingToneMapping

    var body: some Element {
        get throws {
            guard let sampler = HDRTargets.sampler else {
                throw MetalSprocketsError.resourceCreationFailure("Bloom sampler")
            }
            let uniforms = BloomUniforms(exposure: exposure, threshold: settings.threshold, intensity: settings.intensity, toneMapping: Int32(toneMapping.shaderValue.rawValue))
            let levels = targets.bloomLevels
            let scene = targets.scene
            func dispatch(_ texture: MTLTexture) throws -> ComputeDispatch {
                try ComputeDispatch(threadsPerGrid: MTLSize(width: texture.width, height: texture.height, depth: 1), threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1))
            }
            return try ComputePass(label: "Bloom") {
                // Wait for the scene (and the transparency composite) to finish writing.
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "Bloom Prefilter", computeKernel: try PostProcessingShaders.kernel("bloom_prefilter")) {
                    try dispatch(levels[0])
                        .parameter("scene", texture: scene)
                        .parameter("output", texture: levels[0])
                        .parameter("linear", samplerState: sampler)
                        .parameter("uniforms", value: uniforms)
                }
                ForEach(Array(levels.indices.dropFirst()), id: \.self) { index in
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                    try ComputePipeline(label: "Bloom Downsample", computeKernel: try PostProcessingShaders.kernel("bloom_downsample")) {
                        try dispatch(levels[index])
                            .parameter("source", texture: levels[index - 1])
                            .parameter("output", texture: levels[index])
                            .parameter("linear", samplerState: sampler)
                    }
                }
                ForEach(Array(levels.indices.dropLast().reversed()), id: \.self) { index in
                    EncoderBarrier(after: .dispatch, before: .dispatch)
                    try ComputePipeline(label: "Bloom Upsample", computeKernel: try PostProcessingShaders.kernel("bloom_upsample")) {
                        try dispatch(levels[index])
                            .parameter("smaller", texture: levels[index + 1])
                            .parameter("output", texture: levels[index])
                            .parameter("linear", samplerState: sampler)
                    }
                }
                EncoderBarrier(after: .dispatch, before: .dispatch)
                try ComputePipeline(label: "Bloom Composite", computeKernel: try PostProcessingShaders.kernel("bloom_composite")) {
                    try dispatch(output)
                        .parameter("scene", texture: scene)
                        .parameter("bloom", texture: levels[0])
                        .parameter("output", texture: output)
                        .parameter("linear", samplerState: sampler)
                        .parameter("uniforms", value: uniforms)
                }
            }
            .barrierAfterPass(after: .dispatch, beforeQueueStages: [.vertex, .fragment, .dispatch])
        }
    }
}
