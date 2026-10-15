import GeometryLite3D
import Foundation
import Metal
import MetalSprockets
import MetalSprocketsSceneGraphShaders
import simd
import SwiftMesh

// A material drawn with your own vertex and fragment functions, like SceneKit's SCNProgram. One
// ShaderMaterialRenderer draws every ShaderMaterial, so a new look needs shaders, not a new renderer.
//
// The vertex function must declare `constant ShaderMaterialTransforms &transforms` (MetalSprocketsSceneGraphShaders,
// ShaderMaterial.h); the fragment function may declare it too. Each entry of `parameters` is bound by name and must
// exist in at least one of the two functions. The mesh's vertex descriptor is used as is.
public struct ShaderMaterial: MetalSprocketsSceneGraph.Material {
    public enum Value {
        case float(Float)
        case float2(SIMD2<Float>)
        case float3(SIMD3<Float>)
        case float4(SIMD4<Float>)
        case float4x4(simd_float4x4)
        case texture(MTLTexture)
        case sampler(MTLSamplerState)
        case buffer(MTLBuffer)
    }

    public var vertexShader: VertexShader
    public var fragmentShader: FragmentShader
    public var parameters: [String: Value]
    // Alpha-blends over what is already drawn and does not write depth. Drawn after opaque meshes of the same
    // Node.renderingOrder, farthest first.
    public var isTransparent: Bool

    public init(vertexShader: VertexShader, fragmentShader: FragmentShader, parameters: [String: Value] = [:], isTransparent: Bool = false) {
        self.vertexShader = vertexShader
        self.fragmentShader = fragmentShader
        self.parameters = parameters
        self.isTransparent = isTransparent
    }

    // World-space normals as color.
    public static func normals() throws -> Self {
        let library = try ShaderMaterialSampleLibrary.shared()
        return Self(vertexShader: try library.vertex_main, fragmentShader: try library.fragment_normals)
    }

    // A flat color that darkens where the surface turns away from the camera. Needs no lights.
    // Transparent when color.w < 1.
    public static func rim(color: SIMD4<Float>) throws -> Self {
        let library = try ShaderMaterialSampleLibrary.shared()
        return Self(vertexShader: try library.vertex_main, fragmentShader: try library.fragment_rim, parameters: ["color": .float4(color)], isTransparent: color.w < 1)
    }
}

public struct ShaderMaterialRenderer: SceneGraphMaterialRenderer {
    public init() {
    }

    public var materialType: any MetalSprocketsSceneGraph.Material.Type {
        ShaderMaterial.self
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        // Skinned and morphed meshes are deformed on the CPU, as for Blinn-Phong.
        let items: [(mesh: MetalMesh, submeshIndex: Int, modelMatrix: simd_float4x4, material: ShaderMaterial)] = entries.compactMap { entry in
            guard let material = entry.material as? ShaderMaterial else {
                return nil
            }
            let deformed = entry.deformed(revision: context.revision)
            return (deformed?.mesh ?? entry.mesh, entry.submeshIndex, deformed?.modelMatrix ?? entry.worldTransform, material)
        }
        return ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            let transforms = ShaderMaterialTransforms(
                modelMatrix: item.modelMatrix,
                viewMatrix: context.viewMatrix,
                projectionMatrix: context.projectionMatrix,
                modelViewProjectionMatrix: context.projectionMatrix * context.viewMatrix * item.modelMatrix,
                normalMatrix: item.modelMatrix.inverse.transpose,
                cameraPosition: cameraPosition
            )
            let submesh = item.mesh.submeshes[item.submeshIndex]
            try RenderPipeline(label: "ShaderMaterial", vertexShader: item.material.vertexShader, fragmentShader: item.material.fragmentShader) {
                Draw(
                    primitiveType: submesh.primitiveType,
                    indexBuffer: submesh.indexBuffer,
                    indexType: submesh.indexType,
                    indexCount: submesh.indexCount,
                    indexBufferOffset: submesh.indexBufferOffset
                )
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
            // Reversed depth, as in SceneGraphElement; transparent materials test depth but do not write it.
            .depthCompare(function: .greater, enabled: !item.material.isTransparent)
            .renderPipelineDescriptorTransformer { descriptor in
                guard item.material.isTransparent else {
                    return
                }
                let attachment = descriptor.colorAttachments[0]!
                attachment.blendingState = .enabled
                attachment.sourceRGBBlendFactor = .sourceAlpha
                attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
        }
        .eraseToAnyElement()
    }
}

enum ShaderMaterialSampleLibrary {
    nonisolated(unsafe) private static var cached: ShaderNamespace?
    private static let lock = NSLock()

    static func shared() throws -> ShaderNamespace {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .metalSprocketsSceneGraphShaders()).namespaced("ShaderMaterialSamples")
        cached = library
        return library
    }
}
