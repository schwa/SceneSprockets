import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsSupport
import SceneSprockets
import simd

// Outlines nodes (and their descendants) with MetalSprocketsAddOns' jump flood outline (#166). Objects in front hide the
// outline unless `xray`; that needs the scene depth kept after the scene pass (SceneView does this when it has an
// `overlay`). Use from SceneView's `overlay`. Keeps its mask and seed textures between frames, so keep one instance per
// view.
public final class SelectionOutline {
    public var color: SIMD4<Float>
    // Pixels.
    public var width: Float
    // Draw over everything instead of hiding behind objects in front.
    public var xray = false

    private var mask: MTLTexture?
    private var seeds: MTLTexture?

    public init(color: SIMD4<Float> = [1, 0.6, 0.1, 1], width: Float = 3) {
        self.color = color
        self.width = width
    }

    public func element(nodes: [SceneGraph.Node], sceneGraph: SceneGraph, viewport: SceneViewport) throws -> AnyElement? {
        guard !nodes.isEmpty, width > 0 else {
            return nil
        }
        let instances = Self.instances(of: nodes, in: sceneGraph)
        guard !instances.isEmpty else {
            return nil
        }
        let (mask, seeds) = try textures(width: Int(viewport.drawableSize.x), height: Int(viewport.drawableSize.y))
        return OutlinePasses(
            instances: instances,
            // The scene draws with reversed depth; the viewport's projection is standard.
            viewProjection: .reversedDepth * viewport.projectionMatrix * viewport.viewMatrix,
            mask: mask,
            seeds: seeds,
            color: color,
            width: width,
            xray: xray
        )
        .eraseToAnyElement()
    }

    // One instance per mesh node in the nodes' subtrees; a node's submeshes share one mesh.
    static func instances(of nodes: [SceneGraph.Node], in sceneGraph: SceneGraph) -> [SilhouetteMaskRenderPipeline.Instance] {
        var seen = Set<ObjectIdentifier>()
        return sceneGraph.meshEntries().compactMap { entry in
            guard entry.node.isVisible, nodes.contains(where: { $0 === entry.node || $0.isAncestor(of: entry.node) }), seen.insert(entry.node.id).inserted else {
                return nil
            }
            return SilhouetteMaskRenderPipeline.Instance(mesh: entry.mesh, transform: entry.worldTransform)
        }
    }

    private func textures(width: Int, height: Int) throws -> (mask: MTLTexture, seeds: MTLTexture) {
        let width = max(width, 1)
        let height = max(height, 1)
        if let mask, let seeds, mask.width == width, mask.height == height {
            return (mask, seeds)
        }
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw MetalSprocketsError.resourceCreationFailure("No Metal device for the selection outline")
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        guard let mask = device.makeTexture(descriptor: descriptor) else {
            throw MetalSprocketsError.resourceCreationFailure("Could not create the selection outline mask")
        }
        mask.label = "Selection Outline Mask"
        let seeds = try JumpFloodPipeline.makeSeedTexture(device: device, width: width, height: height)
        self.mask = mask
        self.seeds = seeds
        return (mask, seeds)
    }
}

// Mask, flood, then outline over the drawable.
private struct OutlinePasses: Element {
    var instances: [SilhouetteMaskRenderPipeline.Instance]
    var viewProjection: simd_float4x4
    var mask: MTLTexture
    var seeds: MTLTexture
    var color: SIMD4<Float>
    var width: Float
    var xray: Bool

    var body: some Element {
        get throws {
            try RenderPass(label: "Selection Mask") {
                // `mask` is kept between frames: the previous frame's jump flood (dispatch) and outline (fragment)
                // may still read it while this pass clears and writes it. Metal 4 does not order passes (#214).
                QueueBarrier(after: [.dispatch, .fragment], before: .fragment)
                SilhouetteMaskRenderPipeline(instances: instances, viewProjection: viewProjection)
            }
            .renderPassDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].texture = mask
                descriptor.colorAttachments[0].resolveTexture = nil
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].storeAction = .store
                descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                descriptor.depthAttachment.texture = nil
                descriptor.stencilAttachment.texture = nil
            }
            // Waits for the mask (and, transitively, the scene pass) and makes the outline pass wait for it.
            JumpFloodPipeline(mask: mask, seeds: seeds, maximumDistance: width)
            try RenderPass(label: "Selection Outline") {
                // Reversed depth: nearer is greater.
                JumpFloodOutlineRenderPipeline(mask: mask, seeds: seeds, color: color, width: width, depthCompareFunction: xray ? .always : .greaterEqual)
            }
            .renderPassDescriptorModifier { [xray] descriptor in
                descriptor.colorAttachments[0].loadAction = .load
                descriptor.depthAttachment.loadAction = xray ? .clear : .load
                descriptor.depthAttachment.storeAction = .dontCare
            }
        }
    }
}
