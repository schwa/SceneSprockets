import Foundation
import Metal
import MetalSprockets
import MetalSprocketsLighting
import MetalSupport
import SceneSprocketsShaders
import simd

// Screen-space fog over already-drawn geometry; a sibling of the scene pass (it opens its own compute encoder).
struct FogPass: Element {
    var fog: SceneGraph.Fog
    var depthTexture: MTLTexture
    var colorTexture: MTLTexture
    var inverseViewProjection: simd_float4x4
    var cameraPosition: SIMD3<Float>
    /// For `fog.scattering` (#540): the lights, relative to `cameraPosition`, and the frame's shadow map.
    var lights: [LightingLight] = []
    var shadow: Shadows.Sampling?

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

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
                if let scattering = fog.scattering {
                    try ComputePipeline(label: "Volumetric Fog", computeKernel: try FogShaders.scatter()) {
                        try scatterDispatch(uniforms: uniforms, scattering: scattering)
                    }
                } else {
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

    private func scatterDispatch(uniforms: FogUniforms, scattering: SceneGraph.Fog.Scattering) throws -> some Element {
        let placeholder = try FogShaders.shadowPlaceholder()
        var shadowUniforms = shadow?.uniforms ?? LightingShadowUniforms()
        // One shadow tap per step (fog_scatter_compute does not filter): the march averages the noise.
        shadowUniforms.radius = 0
        let scatteringUniforms = FogScatteringUniforms(
            density: max(scattering.density, 0),
            intensity: scattering.intensity,
            anisotropy: scattering.anisotropy,
            maximumDistance: max(scattering.maximumDistance, 0),
            stepCount: Int32(max(scattering.stepCount, 1)),
            lightCount: Int32(lights.count)
        )
        return try ComputeDispatch(
            threadsPerGrid: MTLSize(width: colorTexture.width, height: colorTexture.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
        )
        .parameter("sceneDepth", texture: depthTexture)
        .parameter("outputTexture", texture: colorTexture)
        .parameter("shadowMap", texture: shadow.map { $0.shadowMap.depthTexture(forSubmission: submissionIndex) } ?? placeholder.map)
        .parameter("shadowSampler", samplerState: shadow?.shadowMap.sampler ?? placeholder.sampler)
        .parameter("uniforms", value: uniforms)
        .parameter("scattering", value: scatteringUniforms)
        // Never empty: Metal needs a buffer even when lightCount is 0.
        .parameter("lights", values: lights.isEmpty ? [LightingLight()] : lights)
        .parameter("shadow", value: shadowUniforms)
    }
}

enum FogShaders {
    nonisolated(unsafe) private static var cached: ComputeKernel?
    nonisolated(unsafe) private static var cachedScatter: ComputeKernel?
    nonisolated(unsafe) private static var cachedShadowPlaceholder: (map: MTLTexture, sampler: MTLSamplerState)?
    private static let lock = NSLock()

    static func shared() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("Fog")
        let kernel: ComputeKernel = try library.fog_compute
        cached = kernel
        return kernel
    }

    static func scatter() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cachedScatter {
            return cachedScatter
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("Fog")
        let kernel: ComputeKernel = try library.fog_scatter_compute
        cachedScatter = kernel
        return kernel
    }

    // Bound when the frame has no shadows; the kernel does not sample it then (shadow.enabled is 0).
    static func shadowPlaceholder() throws -> (map: MTLTexture, sampler: MTLSamplerState) {
        lock.lock()
        defer { lock.unlock() }
        if let cachedShadowPlaceholder {
            return cachedShadowPlaceholder
        }
        let device = _MTLCreateSystemDefaultDevice()
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false)
        textureDescriptor.textureType = .type2DArray
        textureDescriptor.usage = .shaderRead
        textureDescriptor.storageMode = .private
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.compareFunction = .greaterEqual
        guard let map = device.makeTexture(descriptor: textureDescriptor), let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create fog shadow placeholder")
        }
        map.label = "Fog Shadow Placeholder"
        cachedShadowPlaceholder = (map, sampler)
        return (map, sampler)
    }
}
