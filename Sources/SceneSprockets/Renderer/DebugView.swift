import Foundation
import Metal
import MetalSprockets
import MetalSupport
import SceneSprocketsShaders
import simd
import SwiftMesh

// Shows every mesh in a scene in one debug view instead of its material (#132). Give it to
// SceneGraphElement(debugMode:) or SceneView(debugMode:). Back faces are tinted red in every mode except wireframe.
public enum SceneGraphDebugMode: Int32, CaseIterable, Sendable, Codable {
    // Grey, lit from the camera: shape only.
    case shaded = 0
    // World-space normals as color.
    case normals = 1
    // Texture coordinates as red and green; magenta without them.
    case textureCoordinates = 2
    // An 8×8 checkerboard in texture space, to see stretching and seams; magenta without texture coordinates.
    case uvChecker = 3
    // The fraction of the world position, repeating every unit.
    case worldPosition = 4
    // Triangle edges only.
    case wireframe = 5

    public var name: String {
        switch self {
        case .shaded: "Shaded"
        case .normals: "Normals"
        case .textureCoordinates: "Texture Coordinates"
        case .uvChecker: "UV Checker"
        case .worldPosition: "World Position"
        case .wireframe: "Wireframe"
        }
    }
}

// Shows one material value instead of the lit result (#195). Unlike SceneGraphDebugMode it keeps each mesh's
// material: every renderer shows its own version of the channel. Blinn-Phong has no metallic (black) and maps
// shininess to roughness.
public enum SceneGraphMaterialChannel: Int32, CaseIterable, Sendable, Codable {
    // Diffuse for Blinn-Phong.
    case baseColor = 1
    case alpha = 2
    case metallic = 3
    case roughness = 4
    // Specular color for Blinn-Phong, reflectance at normal incidence (F0) for PBR.
    case specular = 5
    case emission = 6

    public var name: String {
        switch self {
        case .baseColor: "Base Color"
        case .alpha: "Alpha"
        case .metallic: "Metallic"
        case .roughness: "Roughness"
        case .specular: "Specular"
        case .emission: "Emission"
        }
    }
}

// Stands in for each mesh's material while a debug view is on.
struct SceneGraphDebugMaterial: Material {
    var mode: SceneGraphDebugMode
}

struct SceneGraphDebugRenderer: SceneGraphMaterialRenderer {
    var materialType: any Material.Type {
        SceneGraphDebugMaterial.self
    }

    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let library = try DebugViewLibrary.shared()
        let vertexShader = try library.function(named: "vertex_main", type: VertexShader.self)
        let fragmentShader = try library.function(named: "fragment_main", type: FragmentShader.self)
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        return ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            let mode = (entry.material as? SceneGraphDebugMaterial)?.mode ?? .shaded
            // Skinned and morphed meshes are deformed on the CPU, as for Blinn-Phong.
            let deformed = entry.deformed(revision: context.revision)
            let mesh = deformed?.mesh ?? entry.mesh
            let modelMatrix = deformed?.modelMatrix ?? entry.worldTransform
            let transforms = ShaderMaterialTransforms(modelMatrix: modelMatrix, viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, cameraPosition: cameraPosition, opacity: 1)
            let layout = Self.vertexLayout(mesh.vertexDescriptor)
            let debug = SIMD4<Int32>(mode.rawValue, layout.hasNormals ? 1 : 0, layout.hasTextureCoordinates ? 1 : 0, 0)
            let submesh = mesh.submeshes[entry.submeshIndex]
            try RenderPipeline(label: "DebugView", vertexShader: vertexShader, fragmentShader: fragmentShader) {
                // Sets the winding even with default cull and fill, so [[front_facing]] is right.
                Draw { encoder in
                    encoder.setFrontFacing(simd_determinant(modelMatrix) < 0 ? .clockwise : .counterClockwise)
                    encoder.setTriangleFillMode(mode == .wireframe ? .lines : .fill)
                    encoder.drawIndexedPrimitives(primitiveType: submesh.primitiveType, indexCount: submesh.indexCount, indexType: submesh.indexType, indexBuffer: submesh.indexBuffer.gpuAddress + UInt64(submesh.indexBufferOffset), indexBufferLength: submesh.indexBuffer.length - submesh.indexBufferOffset, instanceCount: 1)
                }
                .useResource(submesh.indexBuffer, usage: .read, stages: .vertex)
                    .vertexBuffers(mesh.vertexBuffers)
                    .parameter("transforms", value: transforms)
                    .parameter("debug", value: debug)
            }
            .vertexDescriptor(layout.descriptor)
            .depthCompare(function: .greater, writes: true)
        }
        .eraseToAnyElement()
    }

    // Position, normal and first texture coordinate at attributes 0, 1 and 2, whatever the mesh's own layout.
    // Missing ones read the position instead.
    static func vertexLayout(_ vertexDescriptor: VertexDescriptor) -> (descriptor: MTLVertexDescriptor, hasNormals: Bool, hasTextureCoordinates: Bool) {
        let descriptor = vertexDescriptor.mtlVertexDescriptor
        for index in 0..<31 {
            descriptor.attributes[index].format = .invalid
        }
        let position = vertexDescriptor.attributes.first { $0.semantic == .position }
        let normal = vertexDescriptor.attributes.first { $0.semantic == .normal }
        let textureCoordinate = vertexDescriptor.attributes.first { $0.semantic == .texcoord(0) }
        for (index, attribute) in [position, normal ?? position, textureCoordinate ?? position].enumerated() {
            guard let attribute else {
                continue
            }
            descriptor.attributes[index].format = attribute.format
            descriptor.attributes[index].offset = attribute.offset
            descriptor.attributes[index].bufferIndex = attribute.bufferIndex
        }
        return (descriptor, normal != nil, textureCoordinate != nil)
    }
}

enum DebugViewLibrary {
    nonisolated(unsafe) private static var cached: ShaderNamespace?
    private static let lock = NSLock()

    static func shared() throws -> ShaderNamespace {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("DebugView")
        cached = library
        return library
    }
}
