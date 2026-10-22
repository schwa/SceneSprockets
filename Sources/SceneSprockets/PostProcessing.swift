import Foundation
import Metal
import MetalSprockets
import SceneSprocketsShaders
import simd

extension SceneGraph {
    // Screen-space effects after the scene, like SCNCamera's colorGrading, vignetting and screenSpaceAmbientOcclusion
    // settings. Applied by SceneGraphElement on the view's own (low dynamic range) color, so there is no HDR, bloom or
    // tone mapping. Like fog, it needs a readable depth texture and a writable color texture.
    public struct PostProcessing: Sendable, Equatable {
        // In stops: 1 doubles brightness.
        public var exposure: Float
        // 1 leaves color unchanged; above 1 pushes away from mid grey.
        public var contrast: Float
        // 0 is grey, 1 unchanged.
        public var saturation: Float
        // Darkening at the corners, 0...1.
        public var vignetteIntensity: Float
        // Fraction of the center-to-corner distance where the vignette starts.
        public var vignetteRadius: Float
        // Nil turns ambient occlusion off.
        public var ambientOcclusion: AmbientOcclusion?

        public init(exposure: Float = 0, contrast: Float = 1, saturation: Float = 1, vignetteIntensity: Float = 0, vignetteRadius: Float = 0.6, ambientOcclusion: AmbientOcclusion? = nil) {
            self.exposure = exposure
            self.contrast = contrast
            self.saturation = saturation
            self.vignetteIntensity = vignetteIntensity
            self.vignetteRadius = vignetteRadius
            self.ambientOcclusion = ambientOcclusion
        }

        var adjustsColor: Bool {
            exposure != 0 || contrast != 1 || saturation != 1 || vignetteIntensity > 0
        }
    }

    // Screen-space ambient occlusion: creases and contacts get darker.
    public struct AmbientOcclusion: Sendable, Equatable {
        // World units searched around each pixel.
        public var radius: Float
        // 0...1.
        public var intensity: Float
        // Samples per pixel; more is smoother and slower.
        public var sampleCount: Int

        public init(radius: Float = 0.5, intensity: Float = 0.8, sampleCount: Int = 12) {
            self.radius = radius
            self.intensity = intensity
            self.sampleCount = sampleCount
        }
    }
}

struct AmbientOcclusionPass: Element {
    var settings: SceneGraph.AmbientOcclusion
    var depthTexture: MTLTexture
    var colorTexture: MTLTexture
    var viewProjection: simd_float4x4
    var cameraPosition: SIMD3<Float>

    var body: some Element {
        get throws {
            let uniforms = AmbientOcclusionUniforms(
                inverseViewProjection: viewProjection.inverse,
                viewProjection: viewProjection,
                cameraPosition: cameraPosition,
                radius: settings.radius,
                intensity: settings.intensity,
                sampleCount: Int32(max(settings.sampleCount, 1))
            )
            return try ComputePass(label: "Ambient Occlusion") {
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "Ambient Occlusion", computeKernel: try PostProcessingShaders.kernel("ambient_occlusion")) {
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

struct ColorAdjustPass: Element {
    var settings: SceneGraph.PostProcessing
    var colorTexture: MTLTexture

    var body: some Element {
        get throws {
            let uniforms = ColorAdjustUniforms(
                exposureScale: pow(2, settings.exposure),
                contrast: settings.contrast,
                saturation: settings.saturation,
                vignetteIntensity: settings.vignetteIntensity,
                vignetteRadius: settings.vignetteRadius
            )
            return try ComputePass(label: "Color Adjust") {
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "Color Adjust", computeKernel: try PostProcessingShaders.kernel("color_adjust")) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: colorTexture.width, height: colorTexture.height, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                    )
                    .parameter("outputTexture", texture: colorTexture)
                    .parameter("uniforms", value: uniforms)
                }
            }
        }
    }
}

enum PostProcessingShaders {
    nonisolated(unsafe) private static var cached: [String: ComputeKernel] = [:]
    private static let lock = NSLock()

    static func kernel(_ name: String) throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let kernel = cached[name] {
            return kernel
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("PostProcessing")
        let kernel = try library.function(named: name, type: ComputeKernel.self)
        cached[name] = kernel
        return kernel
    }
}
