import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsShaders
import simd
import SwiftMesh

/// A material that draws with your own vertex and fragment functions, like SceneKit's `SCNProgram`.
///
/// One ``ShaderMaterialRenderer`` draws every shader material, so a new look needs new shaders, not a new renderer.
///
/// The vertex function must declare `constant ShaderMaterialTransforms &transforms`, from `ShaderMaterial.h` in
/// SceneSprocketsShaders. The fragment function can declare it too. The renderer binds each entry of ``parameters`` by
/// name, and the name must exist in at least one of the two functions. The renderer uses the mesh's vertex descriptor
/// as it is.
public struct ShaderMaterial: SceneSprockets.Material {
    /// A value to bind to a shader argument.
    public enum Value {
        /// A `float`.
        case float(Float)
        /// A `float2`.
        case float2(SIMD2<Float>)
        /// A `float3`.
        case float3(SIMD3<Float>)
        /// A `float4`.
        case float4(SIMD4<Float>)
        /// A `float4x4`.
        case float4x4(simd_float4x4)
        /// A texture.
        case texture(MTLTexture)
        /// A sampler state.
        case sampler(MTLSamplerState)
        /// A buffer.
        case buffer(MTLBuffer)
    }

    /// The vertex function.
    public var vertexShader: VertexShader
    /// The fragment function.
    public var fragmentShader: FragmentShader
    /// The values to bind to shader arguments, by argument name.
    public var parameters: [String: Value]
    /// The depth, color mask, blend and fill settings for the draw.
    public var renderState: MaterialRenderState
    var alphaBlends: Bool

    /// Whether the material blends over what is already drawn.
    ///
    /// A transparent material does not write depth. It draws after opaque meshes with the same `renderingOrder`,
    /// farthest first. The value is also true when ``renderState`` has a blend mode that mixes with the background,
    /// such as add or multiply.
    public var isTransparent: Bool {
        get { alphaBlends || renderState.blendsWithBackground }
        set { alphaBlends = newValue }
    }

    /// Creates a shader material.
    ///
    /// - Parameters:
    ///   - vertexShader: The vertex function. It must declare `ShaderMaterialTransforms`.
    ///   - fragmentShader: The fragment function.
    ///   - parameters: The values to bind to shader arguments, by argument name.
    ///   - isTransparent: Whether the material blends over what is already drawn.
    ///   - renderState: The depth, color mask, blend and fill settings for the draw.
    public init(vertexShader: VertexShader, fragmentShader: FragmentShader, parameters: [String: Value] = [:], isTransparent: Bool = false, renderState: MaterialRenderState = .init()) {
        self.vertexShader = vertexShader
        self.fragmentShader = fragmentShader
        self.parameters = parameters
        self.alphaBlends = isTransparent
        self.renderState = renderState
    }

    /// Always true. When the node opacity is less than 1, the renderer blends and passes the opacity as
    /// `transforms.opacity`.
    ///
    /// The fragment shader must multiply its alpha by `transforms.opacity`. The sample shaders do this.
    public var appliesNodeOpacity: Bool {
        true
    }

    /// A sample material that shows world-space normals as colors.
    ///
    /// - Throws: An error if the sample shader library cannot load.
    public static func normals() throws -> Self {
        let library = try ShaderMaterialSampleLibrary.shared()
        return Self(vertexShader: try library.vertex_main, fragmentShader: try library.fragment_normals)
    }

    /// A sample material with a flat color that darkens where the surface turns away from the camera.
    ///
    /// The material needs no lights. It is transparent when `color.w` is less than 1.
    ///
    /// - Parameter color: The color, with alpha in `w`.
    /// - Throws: An error if the sample shader library cannot load.
    public static func rim(color: SIMD4<Float>) throws -> Self {
        let library = try ShaderMaterialSampleLibrary.shared()
        return Self(vertexShader: try library.vertex_main, fragmentShader: try library.fragment_rim, parameters: ["color": .float4(color)], isTransparent: color.w < 1)
    }
}

/// The renderer that draws every mesh with a ``ShaderMaterial``.
///
/// Add one instance to the renderers of a `SceneView` or `SceneGraphElement`.
public struct ShaderMaterialRenderer: SceneGraphMaterialRenderer, Equatable {
    /// Creates a shader material renderer.
    public init() {
    }

    public var materialType: any SceneSprockets.Material.Type {
        ShaderMaterial.self
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        // Skinned and morphed meshes are deformed on the CPU, as for Blinn-Phong.
        let items: [(mesh: MetalMesh, submeshIndex: Int, modelMatrix: simd_float4x4, material: ShaderMaterial, opacity: Float, isTransparent: Bool)] = entries.compactMap { entry in
            guard let material = entry.material as? ShaderMaterial else {
                return nil
            }
            let deformed = entry.deformed(revision: context.revision)
            return (deformed?.mesh ?? entry.mesh, entry.submeshIndex, deformed?.modelMatrix ?? entry.worldTransform, material, entry.opacity, entry.isTransparent)
        }
        return ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            let transforms = ShaderMaterialTransforms(modelMatrix: item.modelMatrix, viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, cameraPosition: cameraPosition, opacity: item.opacity)
            let submesh = item.mesh.submeshes[item.submeshIndex]
            try RenderPipeline(label: "ShaderMaterial", vertexShader: item.material.vertexShader, fragmentShader: item.material.fragmentShader) {
                materialDraw(submesh, fillMode: item.material.renderState.fillMode)
                .vertexBuffers(item.mesh.vertexBuffers)
                .parameters { parameters in
                    parameters.set("transforms", value: transforms)
                    for (name, value) in item.material.parameters {
                        switch value {
                        case .float(let value): parameters.set(name, value: value)
                        case .float2(let value): parameters.set(name, value: value)
                        case .float3(let value): parameters.set(name, value: value)
                        case .float4(let value): parameters.set(name, value: value)
                        case .float4x4(let value): parameters.set(name, value: value)
                        case .texture(let texture): parameters.set(name, texture: texture)
                        case .sampler(let sampler): parameters.set(name, samplerState: sampler)
                        case .buffer(let buffer): parameters.set(name, buffer: buffer)
                        }
                    }
                }
            }
            .vertexDescriptor(item.mesh.vertexDescriptor.mtlVertexDescriptor)
            .materialRenderState(item.material.renderState, isTransparent: item.isTransparent)
        }
        .eraseToAnyElement()
    }
}

enum ShaderMaterialSampleLibrary {
    // The name saved archives use for the sample shaders; registered with every SceneArchive.
    static let archiveName = "SceneSprocketsShaderMaterialSamples"

    nonisolated(unsafe) private static var cached: ShaderNamespace?
    private static let lock = NSLock()

    static func shared() throws -> ShaderNamespace {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("ShaderMaterialSamples")
        cached = library
        return library
    }
}
