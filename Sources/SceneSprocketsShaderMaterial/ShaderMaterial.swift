import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSupport
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
///
/// With ``samplesShadows``, the renderer also binds the scene's lights and shadow map by name (`lighting`, `lights`,
/// `shadowMap`, `shadowSampler`; see `ShaderMaterialLighting` in `ShaderMaterial.h`), and the fragment function shades
/// each light with its own shadow, as Blinn-Phong and PBR do. Without it, shadows darken the mesh in screen space after
/// the scene pass, every light's shadow at once.
public struct ShaderMaterial: SceneMaterial, SamplesShadowsInShader, DrawsDeformedVertices {
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
    /// Whether the fragment function reads the lights and shadow map and applies each light's shadow itself.
    public var samplesShadows: Bool
    /// Whether the fragment function's alpha blends the mesh over what is already drawn.
    public var usesAlphaBlending: Bool

    public var samplesShadowsInShader: Bool {
        samplesShadows
    }

    /// Whether the material blends over what is already drawn: ``usesAlphaBlending``, or a ``renderState`` blend mode
    /// that mixes with the background, such as add or multiply.
    ///
    /// A transparent material does not write depth. It draws after opaque meshes with the same `renderingOrder`,
    /// farthest first.
    public var isTransparent: Bool {
        usesAlphaBlending || renderState.blendsWithBackground
    }

    /// Creates a shader material.
    ///
    /// - Parameters:
    ///   - vertexShader: The vertex function. It must declare `ShaderMaterialTransforms`.
    ///   - fragmentShader: The fragment function.
    ///   - parameters: The values to bind to shader arguments, by argument name.
    ///   - usesAlphaBlending: Whether the fragment function's alpha blends the mesh over what is already drawn.
    ///   - renderState: The depth, color mask, blend and fill settings for the draw.
    ///   - samplesShadows: Whether the fragment function reads the lights and shadow map.
    public init(vertexShader: VertexShader, fragmentShader: FragmentShader, parameters: [String: Value] = [:], usesAlphaBlending: Bool = false, renderState: MaterialRenderState = .init(), samplesShadows: Bool = false) {
        self.samplesShadows = samplesShadows
        self.vertexShader = vertexShader
        self.fragmentShader = fragmentShader
        self.parameters = parameters
        self.usesAlphaBlending = usesAlphaBlending
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
    public static func normals() -> Self {
        let shaders = ShaderMaterialSampleLibrary.functions(fragment: "fragment_normals")
        return Self(vertexShader: shaders.vertex, fragmentShader: shaders.fragment)
    }

    /// A sample material with a flat color that darkens where the surface turns away from the camera.
    ///
    /// The material needs no lights. It blends when `opacity` is less than 1.
    ///
    /// - Parameters:
    ///   - color: The color, in linear RGB.
    ///   - opacity: The opacity, from 0 to 1.
    public static func rim(color: SIMD3<Float>, opacity: Float = 1) -> Self {
        let shaders = ShaderMaterialSampleLibrary.functions(fragment: "fragment_rim")
        return Self(vertexShader: shaders.vertex, fragmentShader: shaders.fragment, parameters: ["color": .float4(SIMD4(color, opacity))], usesAlphaBlending: opacity < 1)
    }

    /// A sample material with Lambert diffuse lighting from the scene's lights, each dimmed only by its own shadow.
    ///
    /// A starting point for custom shaders that use ``samplesShadows``.
    ///
    /// - Parameters:
    ///   - color: The diffuse color, in linear RGB.
    ///   - opacity: The opacity, from 0 to 1.
    public static func lit(color: SIMD3<Float>, opacity: Float = 1) -> Self {
        let shaders = ShaderMaterialSampleLibrary.functions(fragment: "fragment_lit")
        return Self(vertexShader: shaders.vertex, fragmentShader: shaders.fragment, parameters: ["color": .float4(SIMD4(color, opacity))], usesAlphaBlending: opacity < 1, samplesShadows: true)
    }
}

/// The renderer that draws every mesh with a ``ShaderMaterial``.
///
/// Add one instance to the renderers of a `SceneView` or `SceneGraphElement`.
public struct ShaderMaterialRenderer: SceneGraphMaterialRenderer, Equatable {
    /// Creates a shader material renderer.
    public init() {
    }

    public var materialType: any SceneMaterial.Type {
        ShaderMaterial.self
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        // Skinned and morphed meshes are deformed by SceneGraphElement's GPU pre-pass (#298).
        let items: [ShaderMaterialItem] = entries.compactMap { entry in
            guard let material = entry.material as? ShaderMaterial else {
                return nil
            }
            let deformed = entry.renderDeformed(revision: context.revision)
            return ShaderMaterialItem(mesh: deformed?.mesh ?? entry.mesh, submeshIndex: entry.submeshIndex, modelMatrix: deformed?.modelMatrix ?? entry.worldTransform, material: material, opacity: entry.opacity, isTransparent: entry.isTransparent, receivesShadow: entry.receivesShadow)
        }
        let lights = shaderMaterialLights(context.lights, shadowSlices: context.shadow == nil ? [] : context.lightShadowSlices, cameraPosition: cameraPosition)
        return ShaderMaterialDrawsElement(items: items, context: context, cameraPosition: cameraPosition, lights: lights).eraseToAnyElement()
    }
}

struct ShaderMaterialItem {
    var mesh: MetalMesh
    var submeshIndex: Int
    var modelMatrix: simd_float4x4
    var material: ShaderMaterial
    var opacity: Float
    var isTransparent: Bool
    var receivesShadow: Bool
}

// An element so it can read the submission index: the shadow map has one texture per frame in flight.
struct ShaderMaterialDrawsElement: Element {
    var items: [ShaderMaterialItem]
    var context: SceneGraphRenderContext
    var cameraPosition: SIMD3<Float>
    var lights: [ShaderMaterialLight]

    @MSEnvironment(\.submissionIndex)
    private var submissionIndex

    var body: some Element {
        get throws {
            let context = context
            let cameraPosition = cameraPosition
            // An empty array cannot be bound; the shader reads none of it when lightCount is 0.
            let lightValues = lights.isEmpty ? [ShaderMaterialLight()] : lights
            let lightCount = Int32(lights.count)
            let shadow = context.shadow
            let needsLighting = items.contains(where: \.material.samplesShadows)
            let shadowTexture = needsLighting ? try shadow.map { $0.shadowMap.depthTexture(forSubmission: submissionIndex) } ?? ShaderMaterialSampleLibrary.placeholderShadowMap() : nil
            let shadowSampler = needsLighting ? try shadow?.shadowMap.sampler ?? ShaderMaterialSampleLibrary.placeholderShadowSampler() : nil
            return ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                try draw(item, context: context, cameraPosition: cameraPosition, lightValues: lightValues, lightCount: lightCount, shadowTexture: shadowTexture, shadowSampler: shadowSampler)
            }
        }
    }

    private func lighting(lightCount: Int32, receivesShadow: Bool) -> ShaderMaterialLighting {
        var lighting = ShaderMaterialLighting()
        lighting.lightCount = lightCount
        guard let shadow = context.shadow else {
            return lighting
        }
        lighting.receivesShadow = receivesShadow ? 1 : 0
        lighting.shadowMapSize = Float(shadow.shadowMap.resolution)
        lighting.shadowIntensity = shadow.intensity
        lighting.shadowColor = shadow.color
        lighting.shadowRadius = Int32(max(shadow.softness, 0))
        withUnsafeMutableBytes(of: &lighting.shadowSliceViewProjections) { buffer in
            let slices = buffer.bindMemory(to: simd_float4x4.self)
            // Both the slices and the shading positions are camera-relative.
            for (index, matrix) in shadow.shadowMap.lightViewProjectionMatrices.prefix(slices.count).enumerated() {
                slices[index] = matrix
            }
        }
        return lighting
    }

    // swiftlint:disable:next function_parameter_count
    private func draw(_ item: ShaderMaterialItem, context: SceneGraphRenderContext, cameraPosition: SIMD3<Float>, lightValues: [ShaderMaterialLight], lightCount: Int32, shadowTexture: MTLTexture?, shadowSampler: MTLSamplerState?) throws -> some Element {
        let transforms = ShaderMaterialTransforms(modelMatrix: item.modelMatrix, viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, cameraPosition: cameraPosition, opacity: item.opacity)
        let lighting = lighting(lightCount: lightCount, receivesShadow: item.receivesShadow)
        let submesh = item.mesh.submeshes[item.submeshIndex]
        return try RenderPipeline(label: "ShaderMaterial", vertexShader: item.material.vertexShader, fragmentShader: item.material.fragmentShader) {
            materialDraw(submesh, cullMode: item.material.renderState.cullMode, isMirrored: item.modelMatrix.isMirroring, fillMode: item.material.renderState.fillMode)
            .vertexBuffers(item.mesh.vertexBuffers)
            .parameters { parameters in
                parameters.set("transforms", value: transforms)
                if item.material.samplesShadows, let shadowTexture, let shadowSampler {
                    parameters.set("lighting", value: lighting)
                    parameters.set("lights", values: lightValues)
                    parameters.set("shadowMap", texture: shadowTexture)
                    parameters.set("shadowSampler", samplerState: shadowSampler)
                }
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
}

// Lights point down their node's -Z axis. `shadowSlices` is parallel to `lights` (empty: no shadows). Positions are
// camera-relative.
func shaderMaterialLights(_ lights: [(worldTransform: simd_float4x4, light: Light)], shadowSlices: [Range<Int>], cameraPosition: SIMD3<Float>) -> [ShaderMaterialLight] {
    lights.enumerated().map { index, entry in
        let slices = index < shadowSlices.count ? shadowSlices[index] : 0..<0
        let transform = entry.worldTransform
        let forward = -transform.columns.2.xyz
        let type: Int32 = switch entry.light.type {
        case .directional: Int32(SHADER_MATERIAL_LIGHT_DIRECTIONAL)
        case .spot: Int32(SHADER_MATERIAL_LIGHT_SPOT)
        case .point: Int32(SHADER_MATERIAL_LIGHT_POINT)
        }
        return ShaderMaterialLight(
            position: cameraRelative(transform.columns.3.xyz, to: cameraPosition),
            direction: simd_length(forward) > 0 ? simd_normalize(forward) : [0, 0, -1],
            color: entry.light.color * entry.light.intensity,
            type: type,
            range: entry.light.range,
            innerConeCos: cos(entry.light.innerConeAngle),
            outerConeCos: cos(entry.light.outerConeAngle),
            shadowSliceStart: Int32(slices.lowerBound),
            shadowSliceCount: Int32(slices.count)
        )
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

    // The sample vertex function and a sample fragment function. They ship in this package's bundle, so failing to load
    // them is a packaging bug and traps.
    static func functions(fragment name: String) -> (vertex: VertexShader, fragment: FragmentShader) {
        do {
            let library = try shared()
            return (try library.function(named: "vertex_main", type: VertexShader.self), try library.function(named: name, type: FragmentShader.self))
        } catch {
            fatalError("Could not load the ShaderMaterial sample shaders: \(error)")
        }
    }

    nonisolated(unsafe) private static var cachedShadowMap: MTLTexture?
    nonisolated(unsafe) private static var cachedShadowSampler: MTLSamplerState?

    // Bound as `shadowMap` when the frame has no shadows; `lighting.receivesShadow` is 0, so it is never sampled.
    static func placeholderShadowMap() throws -> MTLTexture {
        lock.lock()
        defer { lock.unlock() }
        if let cachedShadowMap {
            return cachedShadowMap
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .depth32Float, width: 1, height: 1, mipmapped: false)
        descriptor.textureType = .type2DArray
        descriptor.usage = .shaderRead
        descriptor.storageMode = .private
        guard let texture = _MTLCreateSystemDefaultDevice().makeTexture(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create ShaderMaterial placeholder shadow map")
        }
        texture.label = "ShaderMaterial Placeholder Shadow Map"
        cachedShadowMap = texture
        return texture
    }

    static func placeholderShadowSampler() throws -> MTLSamplerState {
        lock.lock()
        defer { lock.unlock() }
        if let cachedShadowSampler {
            return cachedShadowSampler
        }
        let descriptor = MTLSamplerDescriptor()
        descriptor.compareFunction = .greaterEqual
        guard let sampler = _MTLCreateSystemDefaultDevice().makeSamplerState(descriptor: descriptor) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create ShaderMaterial placeholder shadow sampler")
        }
        cachedShadowSampler = sampler
        return sampler
    }
}
