import GeometryLite3D
import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSceneGraphShaders
import MetalSupport
import simd

// Draws particle systems inside the scene pass, after the meshes.
struct ParticlesElement: Element {
    var systems: [SceneGraph.ParticleSystem]
    var context: SceneGraphRenderContext

    var body: some Element {
        get throws {
            let shaders = try ParticleShaders.shared()
            let camera = context.cameraMatrix
            let uniforms = ParticleUniforms(
                viewProjection: context.projectionMatrix * context.viewMatrix,
                right: SIMD4(simd_normalize(SIMD3(camera.columns.0.x, camera.columns.0.y, camera.columns.0.z)), 0),
                up: SIMD4(simd_normalize(SIMD3(camera.columns.1.x, camera.columns.1.y, camera.columns.1.z)), 0)
            )
            let cameraPosition = camera.columns.3.xyz
            let draws: [(buffer: MTLBuffer, count: Int, blendMode: SceneGraph.ParticleSystem.BlendMode)] = systems.compactMap { system in
                // Farthest first, so alpha-blended sprites composite correctly.
                let instances = system.instances()
                    .sorted { simd_distance_squared($0.position, cameraPosition) > simd_distance_squared($1.position, cameraPosition) }
                    .map { ParticleInstance(positionSize: SIMD4($0.position, $0.size), color: $0.color) }
                guard !instances.isEmpty, let buffer = _MTLCreateSystemDefaultDevice().makeBuffer(bytes: instances, length: instances.count * MemoryLayout<ParticleInstance>.stride, options: .storageModeShared) else {
                    return nil
                }
                buffer.label = "Particles"
                return (buffer, instances.count, system.blendMode)
            }
            return try ForEach(Array(draws.enumerated()), id: \.offset) { _, draw in
                try RenderPipeline(label: "Particles", vertexShader: shaders.vertex, fragmentShader: shaders.fragment) {
                    Draw { encoder in
                        encoder.drawPrimitives(primitiveType: .triangleStrip, vertexStart: 0, vertexCount: 4, instanceCount: draw.count)
                    }
                    .parameter("particles", functionType: .vertex, buffer: draw.buffer)
                    .parameter("uniforms", functionType: .vertex, value: uniforms)
                }
                .vertexDescriptor(shaders.vertex.inferredVertexDescriptor())
                // Reversed depth: test, do not write.
                .depthCompare(function: .greater, enabled: false)
                .renderPipelineDescriptorTransformer { descriptor in
                    let attachment = descriptor.colorAttachments[0]!
                    attachment.blendingState = .enabled
                    attachment.sourceRGBBlendFactor = .one
                    attachment.sourceAlphaBlendFactor = .one
                    attachment.destinationRGBBlendFactor = draw.blendMode == .additive ? .one : .oneMinusSourceAlpha
                    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                }
            }
        }
    }
}

struct ParticleShaders {
    var vertex: VertexShader
    var fragment: FragmentShader

    nonisolated(unsafe) private static var cached: ParticleShaders?
    private static let lock = NSLock()

    static func shared() throws -> ParticleShaders {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .metalSprocketsSceneGraphShaders()).namespaced("Particles")
        let shaders = ParticleShaders(vertex: try library.vertex_main, fragment: try library.fragment_main)
        cached = shaders
        return shaders
    }
}
