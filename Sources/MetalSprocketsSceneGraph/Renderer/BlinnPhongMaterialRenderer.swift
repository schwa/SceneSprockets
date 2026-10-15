import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import SwiftMesh
import simd

extension BlinnPhongMaterial: MetalSprocketsSceneGraph.Material {
}

public struct BlinnPhongMaterialRenderer: SceneGraphMaterialRenderer {
    public var ambientLightColor: SIMD3<Float>

    public init(ambientLightColor: SIMD3<Float> = [0.15, 0.15, 0.2]) {
        self.ambientLightColor = ambientLightColor
    }

    public var materialType: any MetalSprocketsSceneGraph.Material.Type {
        BlinnPhongMaterial.self
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        // Lighting needs at least one light; a black one leaves only the ambient term.
        let lights = context.lights.isEmpty ? [(worldTransform: matrix_identity_float4x4, light: Light(type: .directional, color: .zero, intensity: 0))] : context.lights
        let lighting = try Lighting(ambientLightColor: ambientLightColor, orientedLights: blinnPhongLights(lights))
        let viewProjection = context.projectionMatrix * context.viewMatrix
        let cameraPosition = SIMD3(context.cameraMatrix.columns.3.x, context.cameraMatrix.columns.3.y, context.cameraMatrix.columns.3.z)
        // The shader has no morph or skin inputs, so those meshes are deformed on the CPU. They skip culling because
        // their node bounds do not cover the deformation.
        var plain: [SceneGraph.MeshEntry] = []
        var deformed: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4)] = []
        for entry in entries {
            if let result = entry.deformed(revision: context.revision) {
                deformed.append((entry, result.mesh, result.modelMatrix))
            } else {
                plain.append(entry)
            }
        }
        let visible = sortedFrontToBack(culledMeshEntries(plain, viewProjection: viewProjection), cameraPosition: cameraPosition)
            .map { (entry: $0, mesh: $0.mesh, modelMatrix: $0.worldTransform) } + deformed
        let items = visible.compactMap { item in
            (item.entry.material as? BlinnPhongMaterial).map { (entry: item.entry, mesh: item.mesh, modelMatrix: item.modelMatrix, material: $0) }
        }
        // Each vertex layout needs its own pipelines; repeated mesh+material pairs draw as one instanced call.
        let groups = groupedByVertexDescriptor(items) { $0.mesh.vertexDescriptor }.map { group in
            let batches = instanceBatches(group.entries)
            return (vertexDescriptor: group.vertexDescriptor, single: batches.filter { $0.modelMatrices.count == 1 }, instanced: batches.filter { $0.modelMatrices.count > 1 })
        }
        let viewTransforms = ViewTransforms(projectionMatrix: context.projectionMatrix, cameraMatrix: context.cameraMatrix)

        return ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
            try BlinnPhongShader {
                ForEach(Array(group.single.enumerated()), id: \.offset) { _, batch in
                    try draw(batch, instanceCount: 1)
                        .blinnPhongMatrices(
                            projectionMatrix: context.projectionMatrix,
                            viewMatrix: context.viewMatrix,
                            modelMatrix: batch.modelMatrices[0],
                            cameraMatrix: context.cameraMatrix
                        )
                        .blinnPhongMaterial(batch.material)
                        .lighting(lighting)
                }
            }
            .vertexDescriptor(group.vertexDescriptor.mtlVertexDescriptor)
            try BlinnPhongShader(instanced: true) {
                ForEach(Array(group.instanced.enumerated()), id: \.offset) { _, batch in
                    try draw(batch, instanceCount: batch.modelMatrices.count)
                        .blinnPhongInstancedMatrices(viewTransforms, modelMatrices: batch.modelMatrices)
                        .blinnPhongMaterial(batch.material)
                        .lighting(lighting)
                }
            }
            .vertexDescriptor(group.vertexDescriptor.mtlVertexDescriptor)
        }
        .eraseToAnyElement()
    }

    private func draw(_ batch: InstanceBatch, instanceCount: Int) throws -> some Element {
        let submesh = batch.mesh.submeshes[batch.submeshIndex]
        return Draw(
            primitiveType: submesh.primitiveType,
            indexBuffer: submesh.indexBuffer,
            indexType: submesh.indexType,
            indexCount: submesh.indexCount,
            indexBufferOffset: submesh.indexBufferOffset,
            instanceCount: instanceCount
        )
        .vertexBuffers(batch.mesh.vertexBuffers)
    }
}

struct InstanceBatch {
    var mesh: MetalMesh
    var submeshIndex: Int
    var material: BlinnPhongMaterial
    var modelMatrices: [simd_float4x4]
}

// Groups items that share vertex buffers, submesh and material, keeping first-seen order.
func instanceBatches(_ items: [(entry: SceneGraph.MeshEntry, mesh: MetalMesh, modelMatrix: simd_float4x4, material: BlinnPhongMaterial)]) -> [InstanceBatch] {
    struct Key: Hashable {
        var vertexBuffers: [ObjectIdentifier]
        var submeshIndex: Int
        var material: MaterialKey
    }
    var batches: [InstanceBatch] = []
    var indexByKey: [Key: Int] = [:]
    for item in items {
        let buffers = item.mesh.vertexBuffers.sorted { $0.key < $1.key }.map { ObjectIdentifier($0.value) }
        let key = Key(vertexBuffers: buffers, submeshIndex: item.entry.submeshIndex, material: MaterialKey(item.material))
        if let index = indexByKey[key] {
            batches[index].modelMatrices.append(item.modelMatrix)
        } else {
            indexByKey[key] = batches.count
            batches.append(InstanceBatch(mesh: item.mesh, submeshIndex: item.entry.submeshIndex, material: item.material, modelMatrices: [item.modelMatrix]))
        }
    }
    return batches
}

// BlinnPhongMaterial is not Hashable (it holds textures); compare colors by value and textures by identity.
private struct MaterialKey: Hashable {
    var sources: [ColorSourceKey]
    var shininess: Float

    init(_ material: BlinnPhongMaterial) {
        sources = [material.ambient, material.diffuse, material.specular].map(ColorSourceKey.init)
        shininess = material.shininess
    }

    enum ColorSourceKey: Hashable {
        case color(SIMD3<Float>)
        case texture(kind: Int, texture: ObjectIdentifier, sampler: ObjectIdentifier?, extra: Int)

        init(_ source: ColorSource) {
            switch source {
            case .color(let color):
                self = .color(color)
            case .texture2D(let texture, let sampler):
                self = .texture(kind: 0, texture: ObjectIdentifier(texture), sampler: sampler.map { ObjectIdentifier($0) }, extra: 0)
            case .textureCube(let texture, let sampler, let extra):
                self = .texture(kind: 1, texture: ObjectIdentifier(texture), sampler: sampler.map { ObjectIdentifier($0) }, extra: extra)
            case .depth2D(let texture, let sampler):
                self = .texture(kind: 2, texture: ObjectIdentifier(texture), sampler: sampler.map { ObjectIdentifier($0) }, extra: 0)
            }
        }
    }
}

// Lights point down their node's -Z axis.
func blinnPhongLights(_ lights: [(worldTransform: simd_float4x4, light: Light)]) -> [(position: SIMD3<Float>, direction: SIMD3<Float>, light: Light)] {
    lights.map { entry in
        let transform = entry.worldTransform
        let forward = -SIMD3(transform.columns.2.x, transform.columns.2.y, transform.columns.2.z)
        return (
            position: SIMD3(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z),
            direction: simd_length(forward) > 0 ? simd_normalize(forward) : Lighting.defaultLightDirection,
            light: entry.light
        )
    }
}

/// Renders a scene graph's Blinn-Phong meshes. Shorthand for `SceneGraphElement` with a `BlinnPhongMaterialRenderer`.
///
/// ```swift
/// RenderView { context, size in
///     BlinnPhongSceneGraphElement(
///         sceneGraph: sceneGraph,
///         cameraMatrix: cameraMatrix,
///         aspectRatio: Float(size.width / size.height)
///     )
/// }
/// ```
public struct BlinnPhongSceneGraphElement: Element {
    var sceneGraph: SceneGraph
    var camera: SceneGraph.Node?
    var cameraMatrix: simd_float4x4?
    var aspectRatio: Float
    var ambientLightColor: SIMD3<Float>

    public init(
        sceneGraph: SceneGraph,
        camera: SceneGraph.Node? = nil,
        cameraMatrix: simd_float4x4? = nil,
        aspectRatio: Float,
        ambientLightColor: SIMD3<Float> = [0.15, 0.15, 0.2]
    ) {
        self.sceneGraph = sceneGraph
        self.camera = camera
        self.cameraMatrix = cameraMatrix
        self.aspectRatio = aspectRatio
        self.ambientLightColor = ambientLightColor
    }

    public var body: some Element {
        SceneGraphElement(
            sceneGraph: sceneGraph,
            camera: camera,
            cameraMatrix: cameraMatrix,
            aspectRatio: aspectRatio,
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: ambientLightColor)]
        )
    }
}
