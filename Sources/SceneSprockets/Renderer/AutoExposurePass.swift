import Foundation
import Metal
import MetalSprockets
import SceneSprocketsShaders

// Meters the finished frame into `buffer` for AutoExposure (#508); a sibling of the scene pass, after the post passes.
struct AutoExposurePass: Element {
    var colorTexture: MTLTexture
    var depthTexture: MTLTexture
    var buffer: MTLBuffer

    var body: some Element {
        get throws {
            try ComputePass(label: "Auto Exposure Metering") {
                // Wait for the scene and post passes to finish writing color and depth.
                QueueBarrier(after: [.fragment, .dispatch], before: .dispatch)
                try ComputePipeline(label: "Auto Exposure Metering", computeKernel: try AutoExposureShaders.shared()) {
                    try ComputeDispatch(
                        threadsPerGrid: MTLSize(width: 1_024, height: 1, depth: 1),
                        threadsPerThreadgroup: MTLSize(width: 1_024, height: 1, depth: 1)
                    )
                    .parameter("color", texture: colorTexture)
                    .parameter("sceneDepth", texture: depthTexture)
                    .parameter("result", buffer: buffer)
                }
            }
        }
    }
}

enum AutoExposureShaders {
    nonisolated(unsafe) private static var cached: ComputeKernel?
    private static let lock = NSLock()

    static func shared() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("AutoExposure")
        let kernel: ComputeKernel = try library.meter
        cached = kernel
        return kernel
    }
}
