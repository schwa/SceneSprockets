import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBRShaders
import simd

extension PBRRenderer {
    /// Instances `start ..< start + count` of the frame's instance table, drawn with one winding.
    struct InstanceRange: Equatable {
        var start: Int
        var count: Int
        /// Front faces are clockwise: the instances' transform, combined with the model matrix, mirrors.
        var mirrored: Bool
    }

    /// One batch drawn this frame. A class: it is large, and groups and segments share it.
    final class BatchDraw: Identifiable {
        let batch: PBRModel.Batch
        var id: Int { batch.element }
        /// The batch's material, or its override.
        let material: PBRMaterial
        /// The pose animates the material's uniforms, so they can differ every frame.
        let isAnimated: Bool
        private let pose: PBRPose?
        let cullMode: MTLCullMode
        let fillMode: MTLTriangleFillMode
        /// Never empty.
        let ranges: [InstanceRange]
        /// One weight per morph target (at least one), for batches with morph targets.
        let morphWeights: [Float]? // swiftlint:disable:this discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        let variant: VertexVariant
        /// Drawn as a ``DrawList`` row rather than an element of its own: morph targets need per-draw inputs, and every
        /// draw resets the fill mode.
        let isListed: Bool

        /// Animated and resolved for the primitive; points and lines are unlit. Computed on each use: the material table
        /// asks only when the material changed or is animated.
        var uniforms: PBRMaterialUniforms {
            var uniforms = PBRMaterialUniforms.resolved(material, primitive: batch.primitive, pose: pose)
            if batch.primitive.primitiveType != .triangle {
                // Points and lines are drawn unlit in their base color, as three.js does.
                uniforms.unlit = 1
                uniforms.isPointOrLine = 1
            }
            return uniforms
        }

        // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        init(batch: PBRModel.Batch, material: PBRMaterial, pose: PBRPose?, cullMode: MTLCullMode, fillMode: MTLTriangleFillMode, ranges: [InstanceRange], morphWeights: [Float]?) {
            self.batch = batch
            self.material = material
            self.pose = pose
            isAnimated = pose?.materialUniforms[ObjectIdentifier(material)] != nil
            self.cullMode = cullMode
            self.fillMode = fillMode
            self.ranges = ranges
            self.morphWeights = morphWeights
            variant = VertexVariant(batch)
            isListed = batch.primitive.morphTargetCount == 0 && fillMode == .fill
        }
    }

    /// Draws sharing one pipeline: opaque batches with one vertex variant and render state, or a run of blended
    /// batches in back-to-front order.
    struct DrawGroup: Identifiable {
        var id: Int
        var label: String
        /// A run of blended batches (or transmissive ones drawn as coverage) in back-to-front order.
        var isBlended: Bool
        var variant: VertexVariant
        var state: PBRPipelineState
        var draws: [BatchDraw]
        var batches: [PBRModel.Batch] { draws.map(\.batch) }
    }

    /// What one frame of this renderer draws, and the tables its draws read.
    struct FrameDraws {
        /// Opaque groups in ``VertexVariant/all`` order then by first use of each render state, then blended runs.
        var groups: [DrawGroup]
        /// Posed instances; nil reads the model's rest-pose ``PBRModel/instanceBuffer``.
        var instances: [PBRInstance]? // swiftlint:disable:this discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        /// The material table element of each posed instance; nil with `instances`.
        var records: [UInt32]? // swiftlint:disable:this discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        /// Every skin's joint matrices; empty when nothing skinned is drawn.
        var palette: [simd_float4x4]

        var opaqueGroups: [DrawGroup] { groups.filter { !$0.isBlended } }
        var blendedRuns: [DrawGroup] { groups.filter(\.isBlended) }
    }

    /// What this renderer draws this frame, seen from `cameraPosition` (for the back-to-front order of blended batches).
    func frameDraws(cameraPosition: SIMD3<Float>) -> FrameDraws {
        var builder = FrameDrawBuilder(renderer: self)
        return builder.build(cameraPosition: cameraPosition)
    }
}

// Decides which batches the renderer's phase and pre-pass stage draw, culls them, groups them by pipeline, sorts blended
// ones, and lays out the posed instance table.
private struct FrameDrawBuilder {
    let renderer: PBRRenderer
    var model: PBRModel { renderer.model }
    let frustums: [Frustum]
    let modelIsMirrored: Bool
    // With a pose: the table every draw reads, filled as batches are drawn.
    var instances: [PBRInstance] = []
    var records: [UInt32] = []

    init(renderer: PBRRenderer) {
        self.renderer = renderer
        frustums = renderer.viewProjections.map { Frustum(viewProjection: $0) }
        modelIsMirrored = renderer.modelMatrix.isMirroring
    }

    func material(_ batch: PBRModel.Batch) -> PBRMaterial {
        batch.material(overrides: renderer.materialOverrides)
    }

    func worldBounds(_ batch: PBRModel.Batch) -> BoundingBox3D {
        model.worldBounds(of: batch, pose: renderer.pose, modelMatrix: renderer.modelMatrix)
    }

    func pipelineState(_ batch: PBRModel.Batch, coverage: Bool) -> PBRPipelineState {
        let material = material(batch)
        var state = PBRPipelineState(material, writesBlendedDepth: renderer.writesBlendedDepth)
        if renderer.drawsWeightedTransparency, state.blendMode == .alpha {
            state.isWeighted = true
        }
        if coverage {
            state.blendMode = .premultiplied
            state.alphaToCoverage = false
            state.depthWrite = renderer.writesBlendedDepth || material.renderState.depthWrite.resolved(blended: true)
        }
        return state
    }

    // In the pre-pass stage, and seen by a view.
    func isIncluded(_ batch: PBRModel.Batch) -> Bool {
        let material = material(batch)
        let inStage = switch renderer.prePassStage {
        case .none: true
        case .opaque: !material.isTransmissive
        case .transmissiveBackFaces: material.hasTransmissiveBackFaces
        }
        guard inStage else {
            return false
        }
        let bounds = worldBounds(batch)
        return frustums.contains { $0.intersectsNonEmpty(bounds) }
    }

    mutating func build(cameraPosition: SIMD3<Float>) -> PBRRenderer.FrameDraws {
        // swiftlint:disable:next discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        var blendedOrder: [PBRRenderer.SortedBatch]?
        if case let .blended(order) = renderer.phase {
            blendedOrder = order
        }
        let drawsOpaque = blendedOrder == nil
        let drawsBlended = renderer.phase != .opaque
        let coverageDraws = renderer.transmissionAsCoverage

        var groups: [PBRRenderer.DrawGroup] = []
        if drawsOpaque {
            // One pass: groups per vertex variant, each in order of first use of its render state.
            var variantGroups = Array(repeating: [PBRRenderer.DrawGroup](), count: VertexVariant.all.count)
            for batch in model.opaqueBatches where isIncluded(batch) && !(coverageDraws && material(batch).isTransmissive) {
                guard let draw = batchDraw(batch) else {
                    continue
                }
                let state = pipelineState(batch, coverage: false)
                let variantIndex = draw.variant.index
                if let index = variantGroups[variantIndex].firstIndex(where: { $0.state == state }) {
                    variantGroups[variantIndex][index].draws.append(draw)
                } else {
                    variantGroups[variantIndex].append(.init(id: 0, label: "PBR Opaque\(draw.variant.labelSuffix)\(state.labelSuffix)", isBlended: false, variant: draw.variant, state: state, draws: [draw]))
                }
            }
            for var group in variantGroups.joined() {
                group.id = groups.count
                groups.append(group)
            }
        }

        // Blended primitives keep one back-to-front order. Each vertex variant needs its own pipeline, so the order is
        // split into consecutive runs, each drawn with its own pipeline. With transmission as coverage, transmissive
        // opaque batches join the order. With several models they write depth, so they join the shared order of the
        // blended phase (see ``PBRScene/blendedRuns(_:cameraPosition:coverage:)``), after every model's opaque phase.
        var candidates: [(batch: PBRModel.Batch, coverage: Bool)]
        if !drawsBlended {
            candidates = []
        } else if let blendedOrder {
            let blendedByID = Dictionary(uniqueKeysWithValues: model.blendedBatches.map { ($0.id, $0) })
            let opaqueByID = Dictionary(uniqueKeysWithValues: model.opaqueBatches.map { ($0.id, $0) })
            candidates = blendedOrder.compactMap { entry in
                (entry.coverage ? opaqueByID[entry.id] : blendedByID[entry.id]).map { ($0, entry.coverage) }
            }
        } else {
            let glass = coverageDraws && renderer.phase == .all ? model.opaqueBatches.filter { material($0).isTransmissive } : []
            candidates = model.blendedBatches.map { ($0, false) } + glass.map { ($0, true) }
            let centers = candidates.map { worldBounds($0.batch).center }
            let backToFront = candidates.indices.sorted {
                simd_distance_squared(centers[$0], cameraPosition) > simd_distance_squared(centers[$1], cameraPosition)
            }
            candidates = backToFront.map { candidates[$0] }
        }
        for (batch, coverage) in candidates where isIncluded(batch) {
            guard let draw = batchDraw(batch) else {
                continue
            }
            let state = pipelineState(batch, coverage: coverage)
            if let last = groups.last, last.isBlended, last.variant == draw.variant, last.state == state {
                groups[groups.count - 1].draws.append(draw)
            } else {
                groups.append(.init(id: groups.count, label: "PBR Blended\(draw.variant.labelSuffix)\(state.labelSuffix)", isBlended: true, variant: draw.variant, state: state, draws: [draw]))
            }
        }

        let drawsSkinned = groups.contains(where: \.variant.skinned)
        return .init(
            groups: groups,
            instances: renderer.pose == nil ? nil : instances,
            records: renderer.pose == nil ? nil : records,
            palette: drawsSkinned ? model.jointPalette(pose: renderer.pose ?? model.restPose) : []
        )
    }

    // How `batch` is drawn, or nil when it draws nothing: a point or line batch that `drawsTrianglesOnly` leaves out,
    // or every instance hidden. With a pose, appends its instances to the table.
    mutating func batchDraw(_ batch: PBRModel.Batch) -> PBRRenderer.BatchDraw? {
        let primitive = batch.primitive
        let isTriangles = primitive.primitiveType == .triangle
        guard isTriangles || !renderer.drawsTrianglesOnly else {
            return nil
        }
        let material = material(batch)
        let pose = renderer.pose
        let cullMode: MTLCullMode = !isTriangles ? .none : renderer.prePassStage == .transmissiveBackFaces ? .front : material.doubleSided ? .none : .back
        let fillMode: MTLTriangleFillMode = material.renderState.fillMode == .lines ? .lines : .fill

        // Mirroring by both the node and the model matrix cancels out.
        let ranges: [PBRRenderer.InstanceRange]
        if let pose {
            let start = instances.count
            if batch.skinIndex != nil {
                // Skinned meshes follow their joints; the instance only carries the record. Hidden skinned meshes never
                // get here: their bounds are empty, so they are culled.
                instances.append(PBRInstance(worldMatrix: matrix_identity_float4x4, normalMatrix: matrix_identity_float4x4, irradiance: nil))
                ranges = [.init(start: start, count: 1, mirrored: batch.isMirrored != modelIsMirrored)]
            } else {
                // Hidden nodes' instances are left out. Posed instances are ordered unmirrored first, then mirrored (an
                // animation can mirror some of a batch's nodes), and drawn as up to two ranges with their own winding.
                let placements = zip(batch.nodeIndices, batch.instanceMatrices).filter { pose.isVisible($0.0) }.map { node, instanceMatrix in
                    (matrix: pose.placement(node: node, instanceMatrix: instanceMatrix), irradiance: pose.irradiance.indices.contains(node) ? pose.irradiance[node] : nil)
                }
                guard !placements.isEmpty else {
                    return nil
                }
                let unmirrored = placements.filter { !$0.matrix.isMirroring }
                let mirrored = placements.filter(\.matrix.isMirroring)
                instances += (unmirrored + mirrored).map { PBRInstance(worldMatrix: $0.matrix, normalMatrix: $0.matrix.inverse.transpose, irradiance: $0.irradiance) }
                var posedRanges: [PBRRenderer.InstanceRange] = []
                if !unmirrored.isEmpty {
                    posedRanges.append(.init(start: start, count: unmirrored.count, mirrored: modelIsMirrored))
                }
                if !mirrored.isEmpty {
                    posedRanges.append(.init(start: start + unmirrored.count, count: mirrored.count, mirrored: !modelIsMirrored))
                }
                ranges = posedRanges
            }
            records += repeatElement(UInt32(batch.element), count: instances.count - start)
        } else {
            ranges = [.init(start: batch.firstInstance, count: batch.instanceCount, mirrored: batch.isMirrored != modelIsMirrored)]
        }

        return .init(batch: batch, material: material, pose: pose, cullMode: cullMode, fillMode: fillMode, ranges: ranges, morphWeights: Self.morphWeights(batch, model: model, pose: pose))
    }

    // One weight per morph target from the pose, else the node's rest weights; nil without morph targets.
    static func morphWeights(_ batch: PBRModel.Batch, model: PBRModel, pose: PBRPose?) -> [Float]? { // swiftlint:disable:this discouraged_optional_collection - nil means absent or not overridden, which differs from empty
        let targetCount = batch.primitive.morphTargetCount
        guard targetCount > 0 else {
            return nil
        }
        let node = batch.nodeIndices.first ?? 0
        let poseWeights = pose.flatMap { $0.morphWeights.indices.contains(node) ? $0.morphWeights[node] : nil }
        let weights = poseWeights ?? model.restMorphWeights(node: node)
        return (0 ..< targetCount).map { $0 < weights.count ? weights[$0] : 0 }
    }
}

/// Which vertex shader a batch needs: skinned or instanced, with or without morph targets.
struct VertexVariant: Hashable {
    var skinned: Bool
    var morphed: Bool

    static let all = [false, true].flatMap { skinned in [false, true].map { Self(skinned: skinned, morphed: $0) } }

    /// Position in ``all``.
    var index: Int { (skinned ? 2 : 0) + (morphed ? 1 : 0) }

    init(skinned: Bool, morphed: Bool) {
        self.skinned = skinned
        self.morphed = morphed
    }

    init(_ batch: PBRModel.Batch) {
        self.init(skinned: batch.skinIndex != nil, morphed: batch.primitive.morphTargetCount > 0)
    }

    var labelSuffix: String {
        (skinned ? " Skinned" : "") + (morphed ? " Morphed" : "")
    }
}
