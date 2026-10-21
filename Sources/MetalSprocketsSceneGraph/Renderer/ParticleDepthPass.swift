import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSceneGraphShaders

// Copies the scene's stored depth into `output` (r32Float) so soft particles can read it while the depth attachment is
// bound for testing.
struct ParticleDepthCopyPass: Element {
    var depthTexture: MTLTexture
    var output: MTLTexture

    var body: some Element {
        get throws {
            try ComputePass(label: "Particle Scene Depth") {
                // Wait for the scene pass to write depth, and for last frame's particles to stop reading `output`.
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "Particle Scene Depth", computeKernel: try ParticleDepthShaders.shared()) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: output.width, height: output.height, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                    .parameter("sceneDepth", texture: depthTexture)
                    .parameter("output", texture: output)
                }
            }
        }
    }
}

enum ParticleDepthShaders {
    nonisolated(unsafe) private static var cached: ComputeKernel?
    nonisolated(unsafe) private static var textures: [SIMD2<Int>: MTLTexture] = [:]
    private static let lock = NSLock()

    static func shared() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .metalSprocketsSceneGraphShaders()).namespaced("SceneDepthCopy")
        let kernel: ComputeKernel = try library.copy_depth
        cached = kernel
        return kernel
    }

    // One texture per size. Frames in flight share it; the copy pass's barrier orders them.
    static func sceneDepthTexture(device: MTLDevice, width: Int, height: Int) throws -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }
        let key = SIMD2(width, height)
        if let texture = textures[key], texture.device === device {
            return texture
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        descriptor.storageMode = .private
        guard let made = device.makeTexture(descriptor: descriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        made.label = "Particle Scene Depth"
        textures[key] = made
        return made
    }
}
