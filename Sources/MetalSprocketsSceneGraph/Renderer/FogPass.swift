import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSceneGraphShaders
import simd

// Screen-space fog over already-drawn geometry; a sibling of the scene pass (it opens its own compute encoder).
struct FogPass: Element {
    var fog: SceneGraph.Fog
    var depthTexture: MTLTexture
    var colorTexture: MTLTexture
    var inverseViewProjection: simd_float4x4
    var cameraPosition: SIMD3<Float>

    var body: some Element {
        get throws {
            let uniforms = FogUniforms(
                inverseViewProjection: inverseViewProjection,
                cameraPosition: cameraPosition,
                color: fog.color,
                startDistance: fog.startDistance,
                endDistance: fog.endDistance,
                densityExponent: fog.densityExponent
            )
            return try ComputePass(label: "Fog") {
                // Wait for the scene (and the shadow mask) to finish writing color and depth.
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "Fog", computeKernel: try FogShaders.shared()) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: colorTexture.width, height: colorTexture.height, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                    .parameter("sceneDepth", texture: depthTexture)
                    .parameter("outputTexture", texture: colorTexture)
                    .parameter("uniforms", value: uniforms)
                }
            }
        }
    }
}

enum FogShaders {
    nonisolated(unsafe) private static var cached: ComputeKernel?
    private static let lock = NSLock()

    static func shared() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .metalSprocketsSceneGraphShaders()).namespaced("Fog")
        let kernel: ComputeKernel = try library.fog_compute
        cached = kernel
        return kernel
    }
}
