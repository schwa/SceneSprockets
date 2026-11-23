import Foundation
import Metal
import MetalSprockets

// Weighted blended order-independent transparency (#494): accumulation and revealage targets, cached by size.
enum WeightedTransparencyTargets {
    struct Targets {
        var accumulation: MTLTexture
        var revealage: MTLTexture
    }

    nonisolated(unsafe) private static var cached: [SIMD2<Int>: Targets] = [:]
    private static let lock = NSLock()

    static func targets(device: MTLDevice, width: Int, height: Int) throws -> Targets {
        lock.lock()
        defer { lock.unlock() }
        let key = SIMD2(width, height)
        if let targets = cached[key], targets.accumulation.device === device {
            return targets
        }
        func make(_ format: MTLPixelFormat, label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw CocoaError(.featureUnsupported)
            }
            texture.label = label
            return texture
        }
        let targets = Targets(accumulation: try make(.rgba16Float, label: "Transparency Accumulation"), revealage: try make(.r16Float, label: "Transparency Revealage"))
        cached = [key: targets]
        return targets
    }
}

// Draws the weighted transparent entries over the scene's depth, then resolves them into the view's color.
struct WeightedTransparencyPass: Element {
    var targets: WeightedTransparencyTargets.Targets
    var colorTexture: MTLTexture
    var depthTexture: MTLTexture
    var content: [AnyElement]
    var storesDepth: Bool

    var body: some Element {
        get throws {
            let targets = targets
            let colorTexture = colorTexture
            return try Group {
                try RenderPass(label: "Weighted Transparency") {
                    // Wait for the previous frame's composite to finish reading the targets.
                    QueueBarrier(after: [.dispatch, .fragment], before: .fragment)
                    ForEach(Array(content.enumerated()), id: \.offset) { _, element in
                        element
                    }
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].texture = targets.accumulation
                    descriptor.colorAttachments[0].resolveTexture = nil
                    descriptor.colorAttachments[0].loadAction = .clear
                    descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                    descriptor.colorAttachments[0].storeAction = .store
                    descriptor.colorAttachments[1].texture = targets.revealage
                    descriptor.colorAttachments[1].loadAction = .clear
                    descriptor.colorAttachments[1].clearColor = MTLClearColor(red: 1, green: 1, blue: 1, alpha: 1)
                    descriptor.colorAttachments[1].storeAction = .store
                    descriptor.depthAttachment.texture = depthTexture
                    descriptor.depthAttachment.resolveTexture = nil
                    descriptor.depthAttachment.loadAction = .load
                    descriptor.depthAttachment.storeAction = storesDepth ? .store : .dontCare
                    descriptor.stencilAttachment.texture = nil
                }
                try ComputePass(label: "Composite Transparency") {
                    QueueBarrier(after: .fragment, before: .dispatch)
                    try ComputePipeline(label: "Composite Transparency", computeKernel: try PostProcessingShaders.kernel("composite_weighted_transparency")) {
                        try ComputeDispatch(
                            threadsPerGrid: MTLSize(width: colorTexture.width, height: colorTexture.height, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 8, height: 8, depth: 1)
                        )
                        .parameter("accumulation", texture: targets.accumulation)
                        .parameter("revealage", texture: targets.revealage)
                        .parameter("outputTexture", texture: colorTexture)
                    }
                }
                .barrierAfterPass(after: .dispatch, beforeQueueStages: [.vertex, .fragment, .dispatch])
            }
        }
    }
}
