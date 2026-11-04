import Metal
import MetalSprocketsSupport
import MetalSupport
import simd

// Depth array textures with one slice per shadow view, and the matrices and bias to render and sample them.
// Reversed depth: the depth test and the comparison sampler use greater-equal.
public struct SceneGraphShadowMap {
    // One texture per in-flight submission, so a frame never clears a map an earlier frame still samples.
    let depthTextures: [MTLTexture]
    public let sampler: MTLSamplerState
    // Camera-relative: they take world position minus the camera position (#257).
    public internal(set) var lightViewProjectionMatrices: [simd_float4x4]
    var depthBias: Float
    var slopeScale: Float
    public let resolution: Int
    // Number of slices (shadow views).
    let lightCount: Int

    init(resolution: Int, lightCount: Int, depthBias: Float = 2, slopeScale: Float = 2, slotCount: Int = 3) throws {
        self.resolution = resolution
        self.lightCount = lightCount
        self.depthBias = depthBias
        self.slopeScale = slopeScale
        lightViewProjectionMatrices = Array(repeating: .identity, count: lightCount)
        let device = _MTLCreateSystemDefaultDevice()
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2DArray
        descriptor.pixelFormat = .depth32Float
        descriptor.width = resolution
        descriptor.height = resolution
        descriptor.arrayLength = lightCount
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        depthTextures = try (0..<max(slotCount, 1)).map { slot in
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw MetalSupportError.resourceCreationFailure("Failed to create shadow map depth array texture")
            }
            texture.label = "Shadow Map Depth Array [\(slot)]"
            return texture
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.compareFunction = .greaterEqual
        samplerDescriptor.sAddressMode = .clampToBorderColor
        samplerDescriptor.tAddressMode = .clampToBorderColor
        // Outside the map counts as lit (depth 0 is the far plane).
        samplerDescriptor.borderColor = .opaqueBlack
        samplerDescriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create shadow map sampler")
        }
        self.sampler = sampler
    }

    // The texture for a submission (MSEnvironmentValues.submissionIndex).
    public func depthTexture(forSubmission submissionIndex: UInt64) -> MTLTexture {
        depthTextures[Int(submissionIndex % UInt64(depthTextures.count))]
    }
}
