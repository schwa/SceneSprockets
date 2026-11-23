import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import simd

extension SceneGraph {
    /// Makes a node a planar mirror (#531); see ``SceneGraph/Node/planarReflector``.
    public struct PlanarReflector: Sendable, Equatable, Codable {
        /// The size of the reflection image as a fraction of the view's size, from 0.1 to 1.
        public var resolutionScale: Float

        public init(resolutionScale: Float = 0.5) {
            self.resolutionScale = resolutionScale
        }
    }
}

/// This frame's planar reflection (#531): the scene seen from the camera mirrored in the reflector's plane.
public struct PlanarReflectionContext {
    /// The node whose meshes show the reflection.
    public var nodeID: SceneGraph.Node.ID
    /// Linear radiance, rendered with x flipped so it keeps the scene's winding: a `.type2DArray` texture with one
    /// slice and mipmaps. A pixel's reflection is at its own screen position with x mirrored.
    public var texture: MTLTexture
}

enum PlanarReflection {
    // The reflection about the plane through `point` with unit `normal`.
    static func mirror(point: SIMD3<Float>, normal: SIMD3<Float>) -> simd_float4x4 {
        let distance = simd_dot(point, normal)
        let linear = matrix_identity_float3x3 - 2 * simd_float3x3(columns: (normal * normal.x, normal * normal.y, normal * normal.z))
        return simd_float4x4(columns: (SIMD4(linear.columns.0, 0), SIMD4(linear.columns.1, 0), SIMD4(linear.columns.2, 0), SIMD4(2 * distance * normal, 1)))
    }

    // `context` seen in the mirror. The projection flips x, which undoes the mirror's change of winding. Lights keep
    // their places; shadows, clusters and screen-space inputs of the main view do not apply.
    static func mirroredContext(_ context: RenderContext, mirror: simd_float4x4) -> RenderContext {
        var mirrored = context
        mirrored.viewMatrix = context.viewMatrix * mirror
        mirrored.cameraMatrix = mirror * context.cameraMatrix
        var flipX = matrix_identity_float4x4
        flipX.columns.0.x = -1
        mirrored.projectionMatrix = flipX * context.projectionMatrix
        mirrored.outputIsLinear = true
        mirrored.shadow = nil
        mirrored.lightShadowSlices = []
        mirrored.lightClusters = nil
        mirrored.ambientOcclusion = nil
        mirrored.contactShadowLight = nil
        mirrored.sceneDepth = nil
        mirrored.planarReflection = nil
        return mirrored
    }

    // Whether any corner of `entry`'s world bounds is in front of the plane, so it can show in the mirror.
    static func isInFront(_ entry: SceneGraph.MeshEntry, point: SIMD3<Float>, normal: SIMD3<Float>) -> Bool {
        guard let bounds = entry.meshBounds else {
            return true
        }
        return (0..<8).contains { corner in
            let local = SIMD3<Float>(corner & 1 == 0 ? bounds.min.x : bounds.max.x, corner & 2 == 0 ? bounds.min.y : bounds.max.y, corner & 4 == 0 ? bounds.min.z : bounds.max.z)
            let world = (entry.worldTransform * SIMD4(local, 1)).xyz
            return simd_dot(world - point, normal) > -1e-4
        }
    }

    struct Targets {
        var color: MTLTexture
        var depth: MTLTexture
    }

    nonisolated(unsafe) private static var cached: [SIMD3<Int>: Targets] = [:]
    private static let lock = NSLock()

    static func targets(device: MTLDevice, width: Int, height: Int, colorFormat: MTLPixelFormat) throws -> Targets {
        lock.lock()
        defer { lock.unlock() }
        let key = SIMD3(width, height, Int(colorFormat.rawValue))
        if let targets = cached[key], targets.color.device === device {
            return targets
        }
        let colorDescriptor = MTLTextureDescriptor()
        colorDescriptor.textureType = .type2DArray
        colorDescriptor.pixelFormat = colorFormat
        colorDescriptor.width = width
        colorDescriptor.height = height
        colorDescriptor.arrayLength = 1
        colorDescriptor.mipmapLevelCount = Int(log2(Double(max(width, height)))) + 1
        colorDescriptor.usage = [.renderTarget, .shaderRead]
        colorDescriptor.storageMode = .private
        let depthDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        depthDescriptor.usage = .renderTarget
        depthDescriptor.storageMode = .private
        guard let color = device.makeTexture(descriptor: colorDescriptor), let depth = device.makeTexture(descriptor: depthDescriptor) else {
            throw CocoaError(.featureUnsupported)
        }
        color.label = "Planar Reflection"
        depth.label = "Planar Reflection Depth"
        let targets = Targets(color: color, depth: depth)
        cached = [key: targets]
        return targets
    }
}

// Draws the mirrored scene into the reflection target and builds its mip chain.
struct PlanarReflectionPass: Element {
    var targets: PlanarReflection.Targets
    var content: [AnyElement]

    var body: some Element {
        get throws {
            let color = targets.color
            return try Group {
                try RenderPass(label: "Planar Reflection") {
                    // The previous frame's main pass may still be sampling the target.
                    QueueBarrier(after: [.fragment, .blit], before: .fragment)
                    ForEach(Array(content.enumerated()), id: \.offset) { _, element in
                        element
                    }
                }
                .renderPassDescriptorModifier { descriptor in
                    descriptor.colorAttachments[0].texture = color
                    descriptor.colorAttachments[0].resolveTexture = nil
                    descriptor.colorAttachments[0].loadAction = .clear
                    descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                    descriptor.colorAttachments[0].storeAction = .store
                    descriptor.depthAttachment.texture = targets.depth
                    descriptor.depthAttachment.resolveTexture = nil
                    descriptor.depthAttachment.loadAction = .clear
                    descriptor.depthAttachment.clearDepth = 0
                    descriptor.depthAttachment.storeAction = .dontCare
                    descriptor.stencilAttachment.texture = nil
                }
                try ComputePass(label: "Planar Reflection Mipmaps") {
                    QueueBarrier(after: .fragment, before: .blit)
                    ComputeCommand { encoder in
                        encoder.generateMipmaps(texture: color)
                    }
                    .useComputeResource(color, usage: [.read, .write])
                }
                .barrierAfterPass(after: .blit, beforeQueueStages: [.vertex, .fragment, .dispatch])
            }
        }
    }
}
