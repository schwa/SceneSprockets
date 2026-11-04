import Foundation
import MetalSprockets
import SceneSprocketsShaders
import simd

// Draws SceneGraph.Environment.Background.gradient first in the scene pass, without depth (#247).
struct SkyGradientBackground: Element {
    var gradient: SceneGraph.Environment.SkyGradient
    var viewMatrix: simd_float4x4
    var projectionMatrix: simd_float4x4

    var body: some Element {
        get throws {
            var rotationOnly = viewMatrix
            rotationOnly.columns.3 = [0, 0, 0, 1]
            let uniforms = SkyGradientUniforms(
                inverseViewProjection: (projectionMatrix * rotationOnly).inverse,
                zenith: gradient.zenith,
                horizon: gradient.horizon,
                ground: gradient.ground,
                exponent: gradient.exponent
            )
            let shaders = try SkyGradientShaders.shared()
            return try RenderPipeline(label: "Sky Gradient", vertexShader: shaders.vertex, fragmentShader: shaders.fragment) {
                Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
                }
                .parameter("uniforms", value: uniforms)
            }
            .depthCompare(function: .always, enabled: false)
        }
    }
}

enum SkyGradientShaders {
    nonisolated(unsafe) private static var cached: (vertex: VertexShader, fragment: FragmentShader)?
    private static let lock = NSLock()

    static func shared() throws -> (vertex: VertexShader, fragment: FragmentShader) {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("SkyGradient")
        let shaders: (vertex: VertexShader, fragment: FragmentShader) = (try library.vertex_main, try library.fragment_main)
        cached = shaders
        return shaders
    }
}
