import Metal
import MetalSprockets
import MetalSprocketsAddOnsShaders
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import MetalSupport
import SwiftMesh
import simd

public struct PBRSceneMaterial: MetalSprocketsSceneGraph.Material {
    public var pbrMaterial: PBRMaterial

    public init(_ pbrMaterial: PBRMaterial) {
        self.pbrMaterial = pbrMaterial
    }

    public var isTransparent: Bool {
        pbrMaterial.isBlended
    }

    public init(device: MTLDevice, baseColor: SIMD4<Float> = [1, 1, 1, 1], metallic: Float = 0, roughness: Float = 0.5) throws {
        let uniforms = PBRMaterialUniforms.defaults(baseColor: baseColor, metallic: metallic, roughness: roughness)
        pbrMaterial = try PBRMaterial(uniforms: uniforms, placeholder: PBRMaterial.placeholderBinding(device: device), device: device)
    }
}

// Maps scene graph nodes to PBR node indices: entries first (index N is entries[N]), then skin joints.
public struct PBRNodeLayout {
    public var entries: [SceneGraph.MeshEntry]
    public private(set) var jointNodes: [SceneGraph.Node] = []
    public private(set) var skins: [SceneGraph.Skin] = []
    private var jointIndices: [ObjectIdentifier: Int] = [:]
    private var skinIndices: [ObjectIdentifier: Int] = [:]

    public init(entries: [SceneGraph.MeshEntry]) {
        self.entries = entries
        for entry in entries {
            guard let skin = validSkin(of: entry), skinIndices[ObjectIdentifier(skin)] == nil else {
                continue
            }
            skinIndices[ObjectIdentifier(skin)] = skins.count
            skins.append(skin)
            for joint in skin.joints where jointIndices[ObjectIdentifier(joint)] == nil {
                jointIndices[ObjectIdentifier(joint)] = entries.count + jointNodes.count
                jointNodes.append(joint)
            }
        }
    }

    func skinIndex(of entry: SceneGraph.MeshEntry) -> Int? {
        validSkin(of: entry).flatMap { skinIndices[ObjectIdentifier($0)] }
    }

    var pbrSkins: [PBRModel.Skin] {
        skins.map { skin in
            PBRModel.Skin(joints: skin.joints.map { jointIndices[ObjectIdentifier($0)]! }, inverseBindMatrices: skin.inverseBindMatrices)
        }
    }

    public func pose() -> PBRPose {
        PBRPose(
            worldMatrices: entries.map(\.worldTransform) + jointNodes.map(\.worldTransform),
            morphWeights: entries.map(\.node.morphWeights) + jointNodes.map { _ in [] }
        )
    }
}

// A skin is used only if its arrays line up with the mesh and each other.
func validSkin(of entry: SceneGraph.MeshEntry) -> SceneGraph.Skin? {
    guard let skin = entry.node.skin,
          skin.joints.count == skin.inverseBindMatrices.count,
          entry.node.skinVertices.count == entry.mesh.vertexCount
    else {
        return nil
    }
    return skin
}

public struct PBRSceneGraphModelBuilder {
    public var device: MTLDevice

    public init(device: MTLDevice) {
        self.device = device
    }

    public func makeModel(entries: [SceneGraph.MeshEntry]) throws -> PBRModel {
        try makeModel(entries: entries, layout: PBRNodeLayout(entries: entries))
    }

    public func makeModel(entries: [SceneGraph.MeshEntry], layout: PBRNodeLayout) throws -> PBRModel {
        var geometry = PBRGeometryBuilder(device: device)
        var attributeCache: [ObjectIdentifier: [MetalMesh.VertexAttributeData]] = [:]
        var primitiveIDs: [Int] = []
        for entry in entries {
            let key = ObjectIdentifier(entry.mesh.vertexBuffer)
            let attributes = attributeCache[key] ?? entry.mesh.vertexAttributeData()
            attributeCache[key] = attributes
            let input = pbrPrimitiveInput(entry: entry, attributes: attributes, skinned: layout.skinIndex(of: entry) != nil)
            primitiveIDs.append(try geometry.add(attributes: input.attributes, indices: input.indices, primitiveType: input.primitiveType, morphTargets: input.morphTargets, label: entry.mesh.label))
        }
        let primitives = try geometry.build()
        var builder = PBRModelBuilder(device: device, restPose: layout.pose())
        builder.skins = layout.pbrSkins
        for (index, entry) in entries.enumerated() {
            guard let material = entry.material as? PBRSceneMaterial else {
                continue
            }
            builder.addInstance(primitives[primitiveIDs[index]], material: material.pbrMaterial, node: index, skin: layout.skinIndex(of: entry))
        }
        return try builder.build()
    }
}

public final class PBRMaterialRenderer: SceneGraphMaterialRenderer {
    public var device: MTLDevice
    public var environment: PBREnvironment
    public var environmentIntensity: Float
    public var exposure: Float
    // One model per entry set (SceneGraphElement may split entries into batches), for the current structure.
    private var cachedModels: [EntrySetKey: PBRModel] = [:]
    private var cachedRevision: Int?

    public init(device: MTLDevice, environment: PBREnvironment = .studio, environmentIntensity: Float = 1, exposure: Float = 1) {
        self.device = device
        self.environment = environment
        self.environmentIntensity = environmentIntensity
        self.exposure = exposure
    }

    public var materialType: any MetalSprocketsSceneGraph.Material.Type {
        PBRSceneMaterial.self
    }

    // Rebuilds the model only on structure changes (meshes, materials, skins, morph targets, hierarchy);
    // transform and weight changes go through the pose.
    func model(for entries: [SceneGraph.MeshEntry], layout: PBRNodeLayout, structureRevision: Int) throws -> PBRModel {
        if cachedRevision != structureRevision {
            cachedModels.removeAll()
            cachedRevision = structureRevision
        }
        let key = EntrySetKey(entries)
        if let model = cachedModels[key] {
            return model
        }
        let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: entries, layout: layout)
        cachedModels[key] = model
        return model
    }

    func model(for entries: [SceneGraph.MeshEntry], structureRevision: Int) throws -> PBRModel {
        try model(for: entries, layout: PBRNodeLayout(entries: entries), structureRevision: structureRevision)
    }

    public func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        let layout = PBRNodeLayout(entries: entries)
        let model = try model(for: entries, layout: layout, structureRevision: context.revision.structure)
        let lighting = lighting(context: context)
        return PBRRenderer(
            model: model,
            viewMatrix: context.viewMatrix,
            projectionMatrix: context.projectionMatrix,
            lighting: lighting,
            pose: layout.pose()
        )
        .eraseToAnyElement()
    }
}

private struct EntrySetKey: Hashable {
    var nodes: [ObjectIdentifier]
    var submeshes: [Int]

    init(_ entries: [SceneGraph.MeshEntry]) {
        nodes = entries.map { ObjectIdentifier($0.node) }
        submeshes = entries.map(\.submeshIndex)
    }
}

extension PBREnvironment: EnvironmentMap {}

extension PBRMaterialRenderer: SceneGraphBackgroundRenderer {
    // The scene's environment map when it is a PBREnvironment, otherwise `environment`; intensities multiply.
    func lighting(context: SceneGraphRenderContext) -> PBRLighting {
        var lighting = PBRLighting(
            lights: context.lights.map { pbrLight(worldTransform: $0.worldTransform, light: $0.light) },
            environment: context.environment.map as? PBREnvironment ?? environment,
            environmentIntensity: environmentIntensity * context.environment.intensity,
            exposure: exposure
        )
        lighting.environmentRotation = context.environment.rotation
        return lighting
    }

    public func makeBackgroundElement(context: SceneGraphRenderContext) throws -> AnyElement? {
        guard case let .environment(blur) = context.environment.background else {
            return nil
        }
        return PBREnvironmentBackground(lighting: lighting(context: context), viewMatrix: context.viewMatrix, projectionMatrix: context.projectionMatrix, blur: blur)
            .eraseToAnyElement()
    }
}

func pbrPose(for entries: [SceneGraph.MeshEntry]) -> PBRPose {
    PBRNodeLayout(entries: entries).pose()
}

struct PBRPrimitiveInput {
    var attributes: [MetalMesh.VertexAttributeData]
    var indices: [UInt32]
    var primitiveType: MTLPrimitiveType
    var morphTargets: MetalMesh.MorphTargets?
}

func pbrPrimitiveInput(entry: SceneGraph.MeshEntry, attributes: [MetalMesh.VertexAttributeData], skinned: Bool) -> PBRPrimitiveInput {
    let mesh = entry.mesh
    let submesh = mesh.submeshes[entry.submeshIndex]
    var attributes = attributes
    if skinned {
        let skinVertices = entry.node.skinVertices
        attributes.append(.init(semantic: .jointIndices(0), format: .ushort4, values: skinVertices.map(\.joints)))
        attributes.append(.init(semantic: .jointWeights(0), format: .float4, values: skinVertices.map(\.weights)))
    }
    // Invalid targets are dropped as a whole, so target indices stay aligned with weights only when all are valid.
    let targets = entry.node.morphTargets
    var morphTargets: MetalMesh.MorphTargets?
    if !targets.isEmpty, targets.allSatisfy({ $0.isValid(vertexCount: mesh.vertexCount) }) {
        morphTargets = MetalMesh.MorphTargets(targets: targets.map { target in
            MetalMesh.MorphTargets.Target(
                positionOffsets: target.positionDeltas.isEmpty ? nil : target.positionDeltas,
                normalOffsets: target.normalDeltas.isEmpty ? nil : target.normalDeltas,
                tangentOffsets: target.tangentDeltas.isEmpty ? nil : target.tangentDeltas
            )
        })
    }
    return PBRPrimitiveInput(attributes: attributes, indices: submesh.indices, primitiveType: submesh.primitiveType, morphTargets: morphTargets)
}

// Lights point down the node's -Z axis.
func pbrLight(worldTransform: simd_float4x4, light: Light) -> PBRLight {
    var result = PBRLight()
    result.position = SIMD3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
    let forward = -SIMD3(worldTransform.columns.2.x, worldTransform.columns.2.y, worldTransform.columns.2.z)
    result.direction = simd_length(forward) > 0 ? simd_normalize(forward) : [0, 0, -1]
    result.color = light.color
    result.intensity = light.intensity
    result.range = light.range
    switch light.type {
    case .directional:
        result.type = .directional
    case .spot:
        result.type = .spot
        result.innerConeCos = cos(light.innerConeAngle)
        result.outerConeCos = cos(light.outerConeAngle)
    default:
        result.type = .point
    }
    return result
}

