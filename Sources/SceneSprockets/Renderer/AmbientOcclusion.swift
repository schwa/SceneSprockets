import Foundation
import Metal
import MetalSprockets

/// Materials whose renderer multiplies only its ambient light by ``RenderContext/ambientOcclusion`` (Blinn-Phong, PBR).
/// Other materials are darkened as a whole after the scene pass (#136).
public protocol AppliesAmbientOcclusionInShader {}

// Per-frame textures for ambient occlusion, cached by size and format.
enum AmbientOcclusionTargets {
    struct Targets {
        // Depth of every opaque mesh; the visibility is computed from it.
        var depth: MTLTexture
        // Depth of the in-shader materials alone.
        var inShaderDepth: MTLTexture
        var visibility: MTLTexture
        // The pre-pass draws with the renderers' own pipelines, which need a color target like the scene's.
        var scratchColor: MTLTexture
    }

    private struct Key: Hashable {
        var width: Int
        var height: Int
        var colorFormat: MTLPixelFormat
        var depthFormat: MTLPixelFormat
    }

    nonisolated(unsafe) private static var cached: [Key: Targets] = [:]
    private static let lock = NSLock()

    static func targets(device: MTLDevice, width: Int, height: Int, colorFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) throws -> Targets {
        lock.lock()
        defer { lock.unlock() }
        let key = Key(width: width, height: height, colorFormat: colorFormat, depthFormat: depthFormat)
        if let targets = cached[key], targets.depth.device === device {
            return targets
        }
        func make(_ format: MTLPixelFormat, usage: MTLTextureUsage, label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.usage = usage
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw CocoaError(.featureUnsupported)
            }
            texture.label = label
            return texture
        }
        let targets = Targets(
            depth: try make(depthFormat, usage: [.renderTarget, .shaderRead], label: "Ambient Occlusion Depth"),
            inShaderDepth: try make(depthFormat, usage: [.renderTarget, .shaderRead], label: "Ambient Occlusion In-Shader Depth"),
            visibility: try make(.r16Float, usage: [.shaderRead, .shaderWrite], label: "Ambient Occlusion"),
            scratchColor: try make(colorFormat, usage: .renderTarget, label: "Ambient Occlusion Scratch Color")
        )
        cached = [key: targets]
        return targets
    }
}

// Draws `content` with the scene's pipelines into `depth`, for ambient occlusion before shading.
struct AmbientOcclusionDepthPass<Content: Element>: Element {
    var label: String
    var depth: MTLTexture
    var scratchColor: MTLTexture
    var content: Content

    var body: some Element {
        get throws {
            try RenderPass(label: label) {
                content
            }
            .renderPassDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].texture = scratchColor
                descriptor.colorAttachments[0].resolveTexture = nil
                descriptor.colorAttachments[0].loadAction = .dontCare
                descriptor.colorAttachments[0].storeAction = .dontCare
                descriptor.depthAttachment.texture = depth
                descriptor.depthAttachment.resolveTexture = nil
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.clearDepth = 0
                descriptor.depthAttachment.storeAction = .store
                descriptor.stencilAttachment.texture = nil
            }
            .barrierAfterPass(after: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch])
        }
    }
}
