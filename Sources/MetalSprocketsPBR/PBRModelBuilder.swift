import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBRShaders
import simd

/// Builds a ``PBRModel``: primitives (from ``PBRGeometryBuilder``) placed by nodes with materials, plus skins and
/// lights. ``build()`` sorts instances into opaque and blended, groups them into instanced batches, lays out
/// one table of every batch's instances, and collects what must stay resident.
public struct PBRModelBuilder {
    public let device: MTLDevice
    /// Node transforms and morph weights at rest; instances without an explicit world matrix are placed by it.
    public var restPose: PBRPose
    public var skins: [PBRModel.Skin] = []
    public var lights: [LightingLight] = []
    /// Materials to keep resident even if no instance uses them (e.g. ones a pose may switch to).
    public var residentMaterials: [PBRMaterial] = []
    /// Primitives to keep resident even if no instance uses them.
    public var residentPrimitives: [PBRModel.Primitive] = []
    private var instances: [PBRModel.Instance] = []

    public init(device: MTLDevice, restPose: PBRPose) {
        self.device = device
        self.restPose = restPose
    }

    /// Places `primitive` with `material` by node `node` (an index into the pose's world matrices). `worldMatrix`
    /// defaults to the node's rest world matrix times `instanceMatrix`. Skinned primitives are placed by the joints of
    /// `skins[skin]` instead.
    public mutating func addInstance(_ primitive: PBRModel.Primitive, material: PBRMaterial, node: Int, instanceMatrix: simd_float4x4 = matrix_identity_float4x4, worldMatrix: simd_float4x4? = nil, skin: Int? = nil) {
        let world = worldMatrix ?? restPose.placement(node: node, instanceMatrix: instanceMatrix)
        var instance = PBRModel.Instance(id: instances.count, nodeIndex: node, skinIndex: primitive.isSkinned ? skin : nil, primitive: primitive, material: material, worldMatrix: world, normalMatrix: world.inverse.transpose, isMirrored: world.isMirroring, worldBounds: primitive.bounds.transformedKeepingEmpty(by: world))
        instance.instanceMatrix = instanceMatrix
        instances.append(instance)
    }

    public func build() throws -> PBRModel {
        // Skinned primitives are placed by their joints, not their node, so their bounds come from the rest pose.
        let placed = instances.map { instance in
            var instance = instance
            if let skinIndex = instance.skinIndex, skins.indices.contains(skinIndex) {
                instance.worldBounds = PBRModel.skinnedBounds(instance.primitive, skin: skins[skinIndex], pose: restPose)
            }
            return instance
        }
        let blended = placed.filter(\.material.isBlended)
        // Group by material so consecutive draws share bindings. Materials keep their first-use order and instances
        // their order within a material, so the same input always builds the same batches.
        var materialRanks: [ObjectIdentifier: Int] = [:]
        for instance in placed where materialRanks[ObjectIdentifier(instance.material)] == nil {
            materialRanks[ObjectIdentifier(instance.material)] = materialRanks.count
        }
        let opaque = placed.filter { !$0.material.isBlended }.sorted {
            // swiftlint:disable:next force_unwrapping - every batch's material was ranked above
            (materialRanks[ObjectIdentifier($0.material)]!, $0.id) < (materialRanks[ObjectIdentifier($1.material)]!, $1.id)
        }
        let opaqueGroups = Self.groupInstances(opaque, instancing: true)
        let blendedGroups = Self.groupInstances(blended, instancing: false)

        // One table of every batch's rest instances, and each instance's batch element, shared by every draw.
        var instanceValues: [PBRInstance] = []
        var instanceRecords: [UInt32] = []
        var batches: [PBRModel.Batch] = []
        for (element, group) in (opaqueGroups + blendedGroups).enumerated() {
            let first = group[0]
            batches.append(PBRModel.Batch(
                id: element < opaqueGroups.count ? element : element - opaqueGroups.count,
                element: element,
                primitive: first.primitive,
                material: first.material,
                isMirrored: first.isMirrored,
                skinIndex: first.skinIndex,
                instanceCount: group.count,
                nodeIndices: group.map(\.nodeIndex),
                instanceMatrices: group.map(\.instanceMatrix),
                firstInstance: instanceValues.count,
                worldBounds: group.dropFirst().reduce(first.worldBounds) { $0.union($1.worldBounds) }
            ))
            instanceValues += group.map { PBRInstance(worldMatrix: $0.worldMatrix, normalMatrix: $0.normalMatrix) }
            instanceRecords += repeatElement(UInt32(element), count: group.count)
        }
        var skinOffsets: [UInt32] = []
        var paletteSize = 0
        for skin in skins {
            skinOffsets.append(UInt32(paletteSize))
            paletteSize += skin.joints.count
        }
        let jointOffsets = batches.map { batch in
            batch.skinIndex.flatMap { skinOffsets.indices.contains($0) ? skinOffsets[$0] : nil } ?? 0
        }
        let instanceBuffer = try Self.buffer(instanceValues, label: "PBR Instances", device: device)
        let instanceRecordBuffer = try Self.buffer(instanceRecords, label: "PBR Instance Records", device: device)
        let jointOffsetBuffer = try Self.buffer(jointOffsets, label: "PBR Joint Offsets", device: device)

        let resourceCollection = try ResourceCollection(device: device)
        let allocations = Self.residencyAllocations(
            materials: residentMaterials + placed.map(\.material),
            primitives: residentPrimitives + placed.map(\.primitive),
            buffers: [instanceBuffer, instanceRecordBuffer, jointOffsetBuffer]
        )
        for allocation in allocations {
            try resourceCollection.register(allocation)
        }
        return PBRModel(
            opaqueInstances: opaque,
            blendedInstances: blended,
            opaqueBatches: Array(batches[..<opaqueGroups.count]),
            blendedBatches: Array(batches[opaqueGroups.count...]),
            skins: skins,
            lights: lights,
            restPose: restPose,
            // What is drawn at rest: instances the rest pose hides do not count.
            bounds: placed.filter { restPose.isVisible($0.nodeIndex) }.reduce(BoundingBox3D.empty) { $0.union($1.worldBounds) },
            resourceCollection: resourceCollection,
            instanceBuffer: instanceBuffer,
            instanceRecordBuffer: instanceRecordBuffer,
            jointOffsetBuffer: jointOffsetBuffer
        )
    }

    // A shared buffer holding `values`, at least one byte long.
    static func buffer<T>(_ values: [T], label: String, device: MTLDevice) throws -> MTLBuffer {
        let buffer = values.withUnsafeBytes { bytes in
            if let address = bytes.baseAddress, !bytes.isEmpty {
                return device.makeBuffer(bytes: address, length: bytes.count, options: .storageModeShared)
            }
            return device.makeBuffer(length: 1, options: .storageModeShared)
        }
        guard let buffer else {
            throw PBRGeometryError.bufferAllocationFailed
        }
        buffer.label = label
        return buffer
    }

    /// Groups instances into batches. With `instancing`, instances sharing primitive, material and winding share one
    /// batch; skinned and morphed instances have their own joints or weights, so they always get their own.
    static func groupInstances(_ instances: [PBRModel.Instance], instancing: Bool) -> [[PBRModel.Instance]] {
        struct Key: Hashable {
            var geometry: ObjectIdentifier
            var primitive: Int
            var material: ObjectIdentifier
            var isMirrored: Bool
        }
        var groups: [[PBRModel.Instance]] = []
        if instancing {
            var indices: [Key: Int] = [:]
            func isUnique(_ instance: PBRModel.Instance) -> Bool {
                instance.skinIndex != nil || instance.primitive.morphTargetCount > 0
            }
            for instance in instances where isUnique(instance) {
                groups.append([instance])
            }
            for instance in instances where !isUnique(instance) {
                let key = Key(geometry: ObjectIdentifier(instance.primitive.geometry), primitive: instance.primitive.id, material: ObjectIdentifier(instance.material), isMirrored: instance.isMirrored)
                if let index = indices[key] {
                    groups[index].append(instance)
                } else {
                    indices[key] = groups.count
                    groups.append([instance])
                }
            }
        } else {
            groups = instances.map { [$0] }
        }
        return groups
    }

    /// Every long-lived allocation, each once: material textures, geometry, skin and morph buffers, and `buffers`
    /// (the model's instance tables).
    static func residencyAllocations(materials: [PBRMaterial], primitives: [PBRModel.Primitive], buffers: [MTLBuffer]) -> [any MTLAllocation] {
        var allocations: [any MTLAllocation] = []
        for material in materials {
            allocations += material.textureBindings.map(\.texture)
        }
        for primitive in primitives {
            allocations += primitive.geometry.allocations
            allocations += [primitive.morphBuffer].compactMap(\.self)
        }
        allocations += buffers as [any MTLAllocation]
        var seen = Set<ObjectIdentifier>()
        return allocations.filter { seen.insert(ObjectIdentifier($0)).inserted }
    }
}
