import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import simd
import SwiftMesh
import Testing

/// Models built in code: a unit quad in the XY plane, placed by one node per instance.
struct TestModels {
    let device: MTLDevice
    let placeholder: PBRMaterial.Binding
    let quad: PBRModel.Primitive

    init() throws {
        device = MTLCreateSystemDefaultDevice()!
        placeholder = try PBRMaterial.placeholderBinding(device: device)
        var geometry = PBRGeometryBuilder(device: device)
        let positions: [SIMD3<Float>] = [[-0.5, -0.5, 0], [0.5, -0.5, 0], [0.5, 0.5, 0], [-0.5, 0.5, 0]]
        let normals = [SIMD3<Float>](repeating: [0, 0, 1], count: 4)
        try geometry.add(attributes: [
            .init(semantic: .position, format: .float3, values: positions),
            .init(semantic: .normal, format: .float3, values: normals)
        ], indices: [0, 1, 2, 0, 2, 3])
        quad = try geometry.build()[0]
    }

    func material(color: SIMD4<Float> = [1, 0, 0, 1], blended: Bool = false, transmission: Float = 0, doubleSided: Bool = false) -> PBRMaterial {
        var uniforms = PBRMaterialUniforms.defaults(baseColor: color, metallic: 0, roughness: 0.5)
        if blended {
            uniforms.alphaMode = .blend
        }
        uniforms.transmissionFactor = transmission
        return PBRMaterial(uniforms: uniforms, doubleSided: doubleSided, placeholder: placeholder)
    }

    /// One quad per entry, each at its own node translated to `position`.
    func model(_ placements: [(position: SIMD3<Float>, material: PBRMaterial)]) throws -> PBRModel {
        let worldMatrices = placements.map { simd_float4x4(translation: $0.position) }
        var builder = PBRModelBuilder(device: device, restPose: PBRPose(worldMatrices: worldMatrices))
        for (node, placement) in placements.enumerated() {
            builder.addInstance(quad, material: placement.material, node: node)
        }
        return try builder.build()
    }
}

@Suite(.requiresMetal4)
struct DrawPlanTests {
    let models: TestModels
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)

    init() throws {
        models = try TestModels()
    }

    func plan(_ model: PBRModel, pose: PBRPose? = nil, stage: PBRRenderer.TransmissionPrePassStage = .none, eye: SIMD3<Float> = [0, 0, 10], target: SIMD3<Float> = .zero, overrides: PBRModel.MaterialOverrides = [:], modelMatrix: simd_float4x4 = matrix_identity_float4x4, trianglesOnly: Bool = false) -> PBRRenderer.FrameDraws {
        let view = LookAt(position: eye, target: target, up: [0, 1, 0]).viewMatrix
        var renderer = PBRRenderer(model: model, viewMatrix: view, projectionMatrix: projection, modelMatrix: modelMatrix, pose: pose)
        renderer.prePassStage = stage
        renderer.materialOverrides = overrides
        renderer.drawsTrianglesOnly = trianglesOnly
        return renderer.frameDraws(cameraPosition: eye)
    }

    func batchDraws(_ plan: PBRRenderer.FrameDraws) -> [PBRRenderer.BatchDraw] {
        plan.groups.flatMap(\.draws)
    }

    func perBatchCount(_ plan: PBRRenderer.FrameDraws) -> Int {
        batchDraws(plan).count
    }

    func twoOpaqueQuads() throws -> PBRModel {
        try models.model([([-1, 0, 0], models.material(color: [1, 0, 0, 1])), ([1, 0, 0], models.material(color: [0, 1, 0, 1]))])
    }

    // Opaque batches with one vertex variant and render state share one pipeline, and at rest read the model's tables.
    @Test func opaqueBatchesShareAPipeline() throws {
        let model = try twoOpaqueQuads()
        let rest = plan(model)
        #expect(rest.groups.count == 1 && rest.groups[0].draws.count == 2)
        #expect(rest.instances == nil && rest.records == nil)
        #expect(rest.groups[0].draws.allSatisfy { $0.isListed }) // swiftlint:disable:this prefer_key_path
        let ranges = rest.groups[0].draws.map(\.ranges)
        #expect(ranges == model.opaqueBatches.map { [.init(start: $0.firstInstance, count: $0.instanceCount, mirrored: false)] })
    }

    // The model's instance table holds each batch's instances at its first instance, each recording its batch element.
    @Test func instanceTablesLayOutEveryBatch() throws {
        let blended = models.material(color: [1, 1, 1, 0.5], blended: true)
        let red = models.material()
        let model = try models.model([([-1, 0, 0], red), ([1, 0, 0], red), ([0, 0, 1], blended)])
        #expect(model.batches.map(\.element) == [0, 1])
        #expect(model.batches.map(\.firstInstance) == [0, 2])
        let records = model.instanceRecordBuffer.contents().bindMemory(to: UInt32.self, capacity: 3)
        #expect((0 ..< 3).map { records[$0] } == [0, 0, 1])
        #expect(model.blendedBatches.map(\.id) == [0], "Blended batch IDs count from 0")
    }

    @Test func customRenderStatesSplitPipelines() throws {
        let plain = models.material(color: [1, 0, 0, 1])
        let wire = models.material(color: [0, 1, 0, 1]).with(renderState: PBRRenderState(fillMode: .lines))
        let additive = models.material(color: [0, 0, 1, 1]).with(renderState: PBRRenderState(blendMode: .additive))
        let model = try models.model([([-1, 0, 0], plain), ([-1, 1, 0], models.material(color: [1, 1, 0, 1])), ([1, 0, 0], wire), (.zero, additive)])
        #expect(model.blendedBatches.count == 1, "A blend mode makes an opaque alpha mode blended")
        let plan = plan(model)
        #expect(plan.opaqueGroups.map(\.state) == [.opaque])
        // The fill mode is per draw, and every draw resets it, so lines get their own element.
        #expect(plan.opaqueGroups.flatMap(\.draws).filter { !$0.isListed }.map(\.fillMode) == [.lines])
        let blended = try #require(plan.blendedRuns.first)
        #expect(blended.state.blendMode == .additive && !blended.state.depthWrite)
        #expect(!plain.canOverride(wire))
    }

    @Test func renderStateResolvesDepthWrites() {
        let material = models.material(color: [1, 0, 0, 1], blended: true)
        #expect(PBRPipelineState(material, writesBlendedDepth: false).depthWrite == false)
        #expect(PBRPipelineState(material, writesBlendedDepth: true).depthWrite == true, "Stereo writes blended depth")
        #expect(PBRPipelineState(material.with(renderState: PBRRenderState(depthWrite: .enabled)), writesBlendedDepth: false).depthWrite == true)
        let noDepth = material.with(renderState: PBRRenderState(depthWrite: .disabled))
        #expect(PBRPipelineState(noDepth, writesBlendedDepth: true).depthWrite == true, "Stereo wins")
        let opaque = material.with(renderState: PBRRenderState(blendMode: .opaque, depthWrite: .disabled))
        #expect(!opaque.isBlended)
        #expect(PBRPipelineState(opaque, writesBlendedDepth: true).depthWrite == false)
    }

    @Test func cullsOutsideTheView() throws {
        let model = try twoOpaqueQuads()
        #expect(perBatchCount(plan(model, target: [0, 0, 20])) == 0)
    }

    // A pose fills the frame's instance table; a mirrored instance draws with the other winding.
    @Test func posesFillTheInstanceTable() throws {
        let model = try twoOpaqueQuads()
        let moved = PBRPose(worldMatrices: [simd_float4x4(translation: [-2, 0, 0]), simd_float4x4(translation: [2, 0, 0])])
        let posed = plan(model, pose: moved)
        #expect(posed.instances?.count == 2)
        #expect(posed.records?.sorted() == model.opaqueBatches.map { UInt32($0.element) }.sorted())
        let mirrored = PBRPose(worldMatrices: [simd_float4x4(scale: [-1, 1, 1]), matrix_identity_float4x4])
        let draws = batchDraws(plan(model, pose: mirrored))
        #expect(draws.count == 2)
        #expect(Set(draws.map { $0.ranges.map(\.mirrored) }) == [[true], [false]])
    }

    @Test func hiddenNodesAreCulled() throws {
        let model = try twoOpaqueQuads()
        let pose = PBRPose(worldMatrices: model.restPose.worldMatrices, visibility: [true, false])
        let hidden = plan(model, pose: pose)
        #expect(batchDraws(hidden).map { $0.batch.nodeIndices } == [[0]])
        #expect(hidden.instances?.count == 1)
    }

    // A node the pose does not cover is drawn at identity, so its bounds are there too (not empty, which culled it).
    @Test func boundsMatchPlacementForUncoveredNodes() throws {
        let model = try twoOpaqueQuads()
        let pose = PBRPose(worldMatrices: [model.restPose.worldMatrices[0]])
        let uncovered = try #require(model.opaqueBatches.first { $0.nodeIndices == [1] })
        let bounds = model.worldBounds(of: uncovered, pose: pose)
        #expect(bounds.center == .zero)
        #expect(perBatchCount(plan(model, pose: pose)) == 2)
    }

    @Test func overridesReplaceMaterials() throws {
        let model = try twoOpaqueQuads()
        let replacement = models.material(color: [0, 0, 1, 1])
        let draws = batchDraws(plan(model, overrides: [models.quad.key: replacement]))
        #expect(draws.count == 2)
        #expect(draws.allSatisfy { $0.material === replacement })
        #expect(draws.map(\.uniforms.baseColorFactor) == [[0, 0, 1, 1], [0, 0, 1, 1]])
    }

    @Test func transmissionStagesSelectBatches() throws {
        let model = try models.model([([0, 0, -1], models.material()), ([0, 0, 1], models.material(transmission: 1))])
        func transmissiveCount(_ plan: PBRRenderer.FrameDraws) -> Int {
            plan.opaqueGroups.flatMap(\.batches).filter(\.material.isTransmissive).count
        }
        let main = plan(model)
        #expect(perBatchCount(main) == 2 && transmissiveCount(main) == 1)
        let opaque = plan(model, stage: .opaque)
        #expect(perBatchCount(opaque) == 1 && transmissiveCount(opaque) == 0)
        #expect(perBatchCount(plan(model, stage: .transmissiveBackFaces)) == 0, "Single-sided glass has no back faces")
    }

    @Test func doubleSidedGlassDrawsBackFaces() throws {
        let model = try models.model([([0, 0, -1], models.material()), ([0, 0, 1], models.material(transmission: 1, doubleSided: true))])
        let backFaces = plan(model, stage: .transmissiveBackFaces)
        #expect(perBatchCount(backFaces) == 1)
        let batches = backFaces.opaqueGroups.flatMap(\.batches)
        // A key path fails to compile inside #expect (rethrows expansion).
        #expect(batches.allSatisfy { $0.material.isTransmissive }) // swiftlint:disable:this prefer_key_path
    }

    @Test func posedBatchesSplitInstancesByWinding() throws {
        let material = models.material()
        let worldMatrices = [simd_float4x4(translation: [-1, 0, 0]), simd_float4x4(translation: [1, 0, 0])]
        var builder = PBRModelBuilder(device: models.device, restPose: PBRPose(worldMatrices: worldMatrices))
        builder.addInstance(models.quad, material: material, node: 0)
        builder.addInstance(models.quad, material: material, node: 1)
        let model = try builder.build()
        let pose = PBRPose(worldMatrices: [simd_float4x4(translation: [-1, 0, 0]) * simd_float4x4(scale: [-1, 1, 1]), worldMatrices[1]])
        let posed = plan(model, pose: pose)
        let draw = try #require(batchDraws(posed).first)
        #expect(draw.ranges == [.init(start: 0, count: 1, mirrored: false), .init(start: 1, count: 1, mirrored: true)])
        let instanceX = posed.instances?.map(\.worldMatrix.columns.3.x)
        #expect(instanceX == [1, -1], "Unmirrored instances come first")
        // A mirroring model matrix flips every range.
        let flipped = try #require(batchDraws(plan(model, pose: pose, modelMatrix: simd_float4x4(scale: [-1, 1, 1]))).first)
        #expect(flipped.ranges.map(\.mirrored) == [true, false])
        let hidden = PBRPose(worldMatrices: worldMatrices, visibility: [false, true])
        #expect(batchDraws(plan(model, pose: hidden)).first?.ranges == [.init(start: 0, count: 1, mirrored: false)])
    }

    @Test func cullModeFollowsStageAndSidedness() throws {
        let model = try models.model([([0, 0, -1], models.material()), ([0, 0, 1], models.material(transmission: 1, doubleSided: true))])
        #expect(Set(batchDraws(plan(model)).map(\.cullMode)) == [.back, .none])
        #expect(batchDraws(plan(model, stage: .transmissiveBackFaces)).map(\.cullMode) == [.front])
    }

    @Test func pointsAreUnlitAndLeftOutWhenOnlyTrianglesDraw() throws {
        var geometry = PBRGeometryBuilder(device: models.device)
        try geometry.add(attributes: [.init(semantic: .position, format: .float3, values: [SIMD3<Float>](repeating: .zero, count: 3))], indices: [0, 1, 2], primitiveType: .point)
        let points = try geometry.build()[0]
        var builder = PBRModelBuilder(device: models.device, restPose: PBRPose(worldMatrices: [matrix_identity_float4x4, matrix_identity_float4x4]))
        builder.addInstance(points, material: models.material(), node: 0)
        builder.addInstance(models.quad, material: models.material(), node: 1)
        let model = try builder.build()
        let pointDraw = batchDraws(plan(model)).first { $0.batch.primitive.primitiveType == .point }
        #expect(pointDraw?.uniforms.unlit == 1 && pointDraw?.uniforms.isPointOrLine == 1 && pointDraw?.cullMode == MTLCullMode.none)
        let trianglesOnly = plan(model, trianglesOnly: true)
        #expect(batchDraws(trianglesOnly).map(\.batch.primitive.primitiveType) == [.triangle])
        var pointsBuilder = PBRModelBuilder(device: models.device, restPose: PBRPose(worldMatrices: [matrix_identity_float4x4]))
        pointsBuilder.addInstance(points, material: models.material(), node: 0)
        #expect(plan(try pointsBuilder.build(), trianglesOnly: true).opaqueGroups.isEmpty, "No pipeline for points alone")
    }

    @Test func ordersBlendedBatchesBackToFront() throws {
        let near = models.material(color: [1, 0, 0, 0.5], blended: true)
        let far = models.material(color: [0, 1, 0, 0.5], blended: true)
        let model = try models.model([([0, 0, 2], near), ([0, 0, -2], far)])
        let runs = plan(model).blendedRuns
        #expect(runs.count == 1, "Same vertex variant shares a run")
        #expect(runs.first?.batches.map { $0.material === far } == [true, false])
        let behind = plan(model, eye: [0, 0, -10]).blendedRuns
        #expect(behind.first?.batches.map { $0.material === near } == [true, false])
    }
}

@Suite(.requiresMetal4)
struct ModelBuilderOrderTests {
    // Batch order must not depend on where materials happen to be allocated.
    @Test func opaqueBatchesFollowFirstUseOfMaterials() throws {
        let models = try TestModels()
        let materials = (0 ..< 8).map { index in models.material(color: [Float(index) / 8, 0, 0, 1]) }
        // Used in the reverse of allocation order, so sorting by address would reverse them.
        let used = Array(materials.reversed())
        let model = try models.model(used.enumerated().map { ([Float($0.offset), 0, 0], $0.element) })
        #expect(model.opaqueBatches.map { ObjectIdentifier($0.material) } == used.map { ObjectIdentifier($0) })
        #expect(model.opaqueBatches.map(\.nodeIndices) == (0 ..< 8).map { [$0] })
    }

    @Test func instancesSharingAMaterialStayGroupedInOrder() throws {
        let models = try TestModels()
        let red = models.material(color: [1, 0, 0, 1])
        let green = models.material(color: [0, 1, 0, 1])
        let model = try models.model([([0, 0, 0], green), ([1, 0, 0], red), ([2, 0, 0], green)])
        #expect(model.opaqueInstances.map(\.nodeIndex) == [0, 2, 1])
    }
}

@Suite(.requiresMetal4)
struct SceneOrderingTests {
    let models: TestModels

    init() throws {
        models = try TestModels()
    }

    @Test func blendedRunsInterleaveItemsBackToFront() throws {
        let blended = models.material(color: [1, 1, 1, 0.5], blended: true)
        let first = try models.model([([0, 0, -4], blended), ([0, 0, 0], blended)])
        let second = try models.model([([0, 0, -2], blended)])
        let items = [PBRScene.Item(model: first), PBRScene.Item(model: second)]
        let runs = PBRScene.blendedRuns(items, cameraPosition: [0, 0, 10])
        #expect(runs.map(\.item) == [0, 1, 0])
        #expect(runs.map(\.batches.count) == [1, 1, 1])
    }

    @Test func oneItemUsesOneRenderer() throws {
        let model = try models.model([([0, 0, 0], models.material())])
        let renderers = PBRScene.renderers([PBRScene.Item(model: model)], cameraPosition: [0, 0, 10]) { item in
            PBRRenderer(model: item.model, viewMatrix: matrix_identity_float4x4, projectionMatrix: matrix_identity_float4x4)
        }
        #expect(renderers.count == 1 && renderers[0].phase == .all)
    }

    // The pre-pass draws every renderer as configured for the main pass, in its opaque stage.
    @Test func transmissionPassKeepsRendererConfiguration() throws {
        let glass = models.material(transmission: 1)
        let first = try models.model([([0, 0, 0], glass)])
        let second = try models.model([([0, 0, -2], models.material())])
        let target = try PBRTransmissionTarget(device: models.device, width: 4, height: 4)
        let overrides = [models.quad.key: models.material(transmission: 0.5)]
        let renderers = [first, second].map { model in
            var renderer = PBRRenderer(model: model, viewMatrix: matrix_identity_float4x4, projectionMatrix: matrix_identity_float4x4, transmissionTarget: target)
            renderer.materialOverrides = overrides
            renderer.drawsTrianglesOnly = true
            return renderer
        }
        let pass = PBRTransmissionPass(renderers: renderers, target: target, showsBackground: false)
        let all = [pass.renderer] + pass.additionalRenderers
        #expect(all.count == 2)
        #expect(all.allSatisfy { $0.prePassStage == .opaque && $0.drawsTrianglesOnly && $0.materialOverrides.count == 1 })
        #expect(all.map { ObjectIdentifier($0.model) } == [ObjectIdentifier(first), ObjectIdentifier(second)])
    }

    // Stereo glass writes depth, so an item's glass must not be drawn before another item's opaque batches behind it.
    @Test func stereoCoverageGlassDrawsAfterEveryItemsOpaqueBatches() throws {
        let glass = models.material(transmission: 1)
        let first = try models.model([([0, 0, 2], glass)])
        let second = try models.model([([0, 0, -2], models.material())])
        let items = [PBRScene.Item(model: first), PBRScene.Item(model: second)]
        let eye: SIMD3<Float> = [0, 0, 10]
        let view = LookAt(position: eye, target: .zero, up: [0, 1, 0]).viewMatrix
        let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)
        let viewport = MTLViewport(originX: 0, originY: 0, width: 4, height: 4, znear: 0, zfar: 1)
        let stereo = StereoViews(viewMatrices: [view, view], projectionMatrices: [projection, projection], viewports: [viewport, viewport])
        let renderers = PBRScene.renderers(items, cameraPosition: eye) { item in
            var renderer = PBRRenderer(model: item.model, viewMatrix: view, projectionMatrix: projection)
            renderer.stereo = stereo
            return renderer
        }
        // Which model each draw comes from, in draw order.
        let order = renderers.flatMap { renderer -> [ObjectIdentifier] in
            let count = renderer.frameDraws(cameraPosition: eye).groups.flatMap(\.draws).count
            return Array(repeating: ObjectIdentifier(renderer.model), count: count)
        }
        #expect(order == [ObjectIdentifier(second), ObjectIdentifier(first)])
    }

    @Test func severalItemsDrawOpaqueThenBlendedRuns() throws {
        let blended = models.material(color: [1, 1, 1, 0.5], blended: true)
        let first = try models.model([([0, 0, -4], blended), ([0, 0, 0], models.material())])
        let second = try models.model([([0, 0, -2], blended)])
        let items = [PBRScene.Item(model: first), PBRScene.Item(model: second)]
        let renderers = PBRScene.renderers(items, cameraPosition: [0, 0, 10]) { item in
            PBRRenderer(model: item.model, viewMatrix: matrix_identity_float4x4, projectionMatrix: matrix_identity_float4x4)
        }
        #expect(renderers.map(\.phase) == [.opaque, .opaque, .blended([.init(id: first.blendedBatches[0].id, coverage: false)]), .blended([.init(id: second.blendedBatches[0].id, coverage: false)])])
    }
}
