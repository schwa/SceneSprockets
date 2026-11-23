import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSupport
import MetalSupport
import SceneSprocketsShaders
import simd

/// Per-pixel view-space normals and screen-space velocity of the opaque meshes (#510), for effects such as temporal
/// anti-aliasing, motion blur and screen-space reflections. Off by default: give one to
/// ``SceneGraphElement/gBuffer(_:)`` to request it. Keep one instance per view across frames; it remembers last
/// frame's camera and mesh transforms, which velocity needs.
///
/// The targets come from a pre-pass that draws every opaque mesh once more with one shader. So material normal maps
/// and alpha cutouts are ignored, renderers that draw their own geometry (raymarched shapes, terrain, voxels, point
/// clouds) are missing, and skinned and morphed meshes get the camera's motion only. Not drawn in stereo or in debug
/// views, and only with readable view targets (see ``Shadows/requiredColorUsage``).
public final class GBuffer {
    /// `.rgba16Float`: the view-space normal (camera looks down -Z) in xyz, and 1 in alpha where a mesh was drawn
    /// (0 for the background). Nil before the first frame.
    public private(set) var normals: MTLTexture?
    /// `.rg16Float`: where each pixel is this frame minus where it was last frame, in texture coordinates (0...1 across
    /// the view, y down). Zero on the first frame and for the background.
    public private(set) var velocity: MTLTexture?
    /// The pre-pass's depth (`.depth32Float`, reversed: near is 1).
    public private(set) var depth: MTLTexture?

    struct Key: Hashable {
        var node: SceneGraph.Node.ID
        var instance: Int
    }

    // Last frame's camera-relative view-projection, camera position and mesh world transforms.
    private var previousViewProjection: simd_float4x4?
    private var previousCameraPosition = SIMD3<Float>.zero
    private var previousTransforms: [Key: simd_float4x4] = [:]

    public init() {}

    // This frame's targets, sized like the view.
    func targets(device: MTLDevice, width: Int, height: Int) throws -> (normals: MTLTexture, velocity: MTLTexture, depth: MTLTexture) {
        if let normals, let velocity, let depth, normals.width == width, normals.height == height, normals.device === device {
            return (normals, velocity, depth)
        }
        func make(_ format: MTLPixelFormat, label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw MetalSupportError.resourceCreationFailure("G-buffer \(label)")
            }
            texture.label = "G-Buffer \(label)"
            return texture
        }
        let made = (try make(.rgba16Float, label: "Normals"), try make(.rg16Float, label: "Velocity"), try make(.depth32Float, label: "Depth"))
        normals = made.0
        velocity = made.1
        depth = made.2
        return made
    }

    // Per-draw uniforms for this frame, and the history for the next one. Positions are camera-relative.
    func drawUniforms(entries: [SceneGraph.MeshEntry], viewProjection: simd_float4x4, viewRotation: simd_float4x4, cameraPosition: SIMD3<Float>) -> [GBufferDrawUniforms] {
        let previousViewProjection = self.previousViewProjection ?? viewProjection
        var transforms: [Key: simd_float4x4] = [:]
        let uniforms = entries.map { entry in
            let key = Key(node: entry.nodeID, instance: entry.instanceIndex ?? -1)
            let world = entry.worldTransform
            transforms[key] = world
            let previousWorld = previousTransforms[key] ?? world
            let model = world.cameraRelative(to: cameraPosition)
            let previousModel = previousWorld.cameraRelative(to: self.previousViewProjection == nil ? cameraPosition : previousCameraPosition)
            let modelView = viewRotation * model
            let linear = simd_float3x3(modelView.columns.0.xyz, modelView.columns.1.xyz, modelView.columns.2.xyz)
            let hasNormals = entry.mesh.vertexDescriptor.attributes.contains { $0.semantic == .normal }
            return GBufferDrawUniforms(modelViewProjection: viewProjection * model, previousModelViewProjection: previousViewProjection * previousModel, viewNormalMatrix: linear.inverse.transpose, hasNormals: hasNormals ? 1 : 0)
        }
        self.previousViewProjection = viewProjection
        previousCameraPosition = cameraPosition
        previousTransforms = transforms
        return uniforms
    }
}

// Draws the opaque meshes into the G-buffer's normal and velocity targets.
struct GBufferPass: Element {
    var entries: [SceneGraph.MeshEntry]
    var uniforms: [GBufferDrawUniforms]
    var targets: (normals: MTLTexture, velocity: MTLTexture, depth: MTLTexture)

    var body: some Element {
        get throws {
            let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("GBufferPass")
            let vertexShader: VertexShader = try library.vertex_main
            let fragmentShader: FragmentShader = try library.fragment_main
            let targets = targets
            return try RenderPass(label: "G-Buffer") {
                // The previous frame's passes may still be reading the targets.
                QueueBarrier(after: [.fragment, .dispatch], before: [.vertex, .fragment])
                ForEach(Array(zip(entries, uniforms).enumerated()), id: \.offset) { _, item in
                    let (entry, uniforms) = item
                    let mesh = entry.mesh
                    let submesh = mesh.submeshes[entry.submeshIndex]
                    let layout = SceneGraphDebugRenderer.vertexLayout(mesh.vertexDescriptor)
                    try RenderPipeline(label: "G-Buffer", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                        Draw { encoder in
                            encoder.drawIndexedPrimitives(primitiveType: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.gpuAddress + UInt64(submesh.indexBufferOffset), indexBufferLength: submesh.indexBuffer.length - submesh.indexBufferOffset, instanceCount: 1)
                        }
                        .frontFacing(simd_determinant(entry.worldTransform) < 0 ? .clockwise : .counterClockwise)
                        .useResource(submesh.indexBuffer, usage: .read, stages: .vertex)
                        .vertexBuffers(mesh.vertexBuffers)
                        .parameter("uniforms", value: uniforms)
                    }
                    .vertexDescriptor(layout.descriptor)
                    .depthCompare(function: .greater, writes: true)
                    .renderPipelineDescriptorTransformer { descriptor in
                        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
                        descriptor.colorAttachments[1].pixelFormat = .rg16Float
                    }
                }
            }
            .renderPassDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].texture = targets.normals
                descriptor.colorAttachments[0].resolveTexture = nil
                descriptor.colorAttachments[0].loadAction = .clear
                descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                descriptor.colorAttachments[0].storeAction = .store
                descriptor.colorAttachments[1].texture = targets.velocity
                descriptor.colorAttachments[1].loadAction = .clear
                descriptor.colorAttachments[1].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                descriptor.colorAttachments[1].storeAction = .store
                descriptor.depthAttachment.texture = targets.depth
                descriptor.depthAttachment.resolveTexture = nil
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.clearDepth = 0
                descriptor.depthAttachment.storeAction = .store
                descriptor.stencilAttachment.texture = nil
            }
            // Later passes read the targets.
            .barrierAfterPass(after: .fragment, beforeQueueStages: [.vertex, .fragment, .dispatch])
        }
    }
}

public extension SceneGraphElement {
    /// Draws view-space normals and screen-space velocity into `gBuffer` each frame, before the scene pass (#510).
    /// ``RenderContext/gBuffer`` holds it for renderers and render stages.
    func gBuffer(_ gBuffer: GBuffer?) -> Self {
        var copy = self
        copy.gBufferStorage = gBuffer
        return copy
    }
}
