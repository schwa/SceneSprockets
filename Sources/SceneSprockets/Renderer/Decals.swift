import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSupport
import MetalSupport
import SceneSprocketsShaders
import simd

/// Materials whose renderer reads the scene's depth (#397). Their entries are drawn after the scene pass, with
/// ``RenderContext/sceneDepth`` set, and cast no shadows. They need readable view targets (see
/// ``Shadows/requiredColorUsage``) and no multisampled view target; otherwise they are not drawn.
public protocol ReadsSceneDepth {}

/// A decal projected onto the scene, like a bullet hole, footprint or road marking (#397). Put it on a node with a
/// box shape: the node's transform places a unit box (-0.5...0.5 on each axis), and the decal covers the surfaces
/// inside it, projected along the box's -Z axis with its texture's top along +Y. Draw it with ``DecalRenderer``.
///
/// Decals are unlit: the color is drawn as it is, blended by alpha.
public struct DecalMaterial: SceneMaterial, ReadsSceneDepth {
    /// The image to project. Nil draws ``color`` alone.
    public var texture: MTLTexture?
    /// Linear RGBA, multiplied with the texture.
    public var color: SIMD4<Float>
    /// Surfaces turned further than this from the projection direction, in radians, get no decal; the decal fades out
    /// over the last fifth of the angle, so it does not stretch along steep sides.
    public var maximumAngle: Float

    public var isTransparent: Bool { true }
    public var appliesNodeOpacity: Bool { true }

    public init(texture: MTLTexture? = nil, color: SIMD4<Float> = [1, 1, 1, 1], maximumAngle: Float = .pi / 3) {
        self.texture = texture
        self.color = color
        self.maximumAngle = maximumAngle
    }
}

/// Draws ``DecalMaterial`` entries.
public struct DecalRenderer: MaterialRenderer {
    public init() {}

    public var materialType: any SceneMaterial.Type {
        DecalMaterial.self
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: RenderContext) throws -> AnyElement {
        guard let sceneDepth = context.sceneDepth, context.stereoViews == nil else {
            return EmptyElement().eraseToAnyElement()
        }
        let shaders = try DecalShaders.shared()
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let viewProjection = context.projectionMatrix * context.viewMatrix.rotationOnlyView
        let inverseViewProjection = viewProjection.inverse
        return try RenderPipeline(label: "Decals", vertexShader: shaders.vertex, fragmentShader: shaders.fragment) {
            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                let material = entry.material as? DecalMaterial ?? DecalMaterial()
                let model = entry.worldTransform.cameraRelative(to: cameraPosition)
                var uniforms = DecalUniforms()
                uniforms.modelViewProjection = viewProjection * model
                uniforms.inverseModel = model.inverse
                uniforms.inverseViewProjection = inverseViewProjection
                uniforms.color = material.color * SIMD4(1, 1, 1, entry.opacity)
                uniforms.axis = simd_normalize(model.columns.2.xyz)
                uniforms.viewSize = [Float(sceneDepth.width), Float(sceneDepth.height)]
                uniforms.fadeEndCosine = cos(material.maximumAngle)
                uniforms.fadeStartCosine = cos(material.maximumAngle * 0.8)
                uniforms.hasTexture = material.texture == nil ? 0 : 1
                return Draw { encoder in
                    encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 36)
                }
                // Back faces only, so the camera can be inside the box; mirrored boxes swap which side is the back.
                .frontFacing(simd_determinant(model) < 0 ? .clockwise : .counterClockwise)
                .parameter("uniforms", value: uniforms)
                .parameter("decalTexture", functionType: .fragment, texture: material.texture ?? shaders.whiteTexture)
            }
            .parameter("sceneDepth", functionType: .fragment, texture: sceneDepth)
            .parameter("decalSampler", functionType: .fragment, samplerState: shaders.sampler)
        }
        .cullMode(.front)
        .materialRenderState(MaterialRenderState(writesToDepthBuffer: false, readsFromDepthBuffer: false), isTransparent: true)
        .eraseToAnyElement()
    }
}

struct DecalShaders {
    var vertex: VertexShader
    var fragment: FragmentShader
    var whiteTexture: MTLTexture
    var sampler: MTLSamplerState

    nonisolated(unsafe) private static var cached: Self?
    private static let lock = NSLock()

    static func shared() throws -> Self {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("Decal")
        let device = _MTLCreateSystemDefaultDevice()
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        guard let whiteTexture = device.makeTexture(descriptor: textureDescriptor) else {
            throw MetalSprocketsError.resourceCreationFailure("Decal white texture")
        }
        whiteTexture.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8](repeating: 255, count: 4), bytesPerRow: 4)
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            throw MetalSprocketsError.resourceCreationFailure("Decal sampler")
        }
        let shaders = Self(vertex: try library.vertex_main, fragment: try library.fragment_main, whiteTexture: whiteTexture, sampler: sampler)
        cached = shaders
        return shaders
    }
}
