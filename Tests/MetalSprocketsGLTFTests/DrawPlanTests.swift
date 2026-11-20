import Foundation
import GeometryLite3D
@testable import MetalSprocketsGLTF
@testable import MetalSprocketsPBR
import simd
import Testing

@Suite(.requiresMetal4)
struct DrawPlanTests {
    let projection = PerspectiveProjection(verticalAngleOfView: .radians(.pi / 4), depthMode: .reversed(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1)

    func plan(_ asset: GLTFAsset, pose: PBRPose? = nil, stage: PBRRenderer.TransmissionPrePassStage = .none, eye: SIMD3<Float> = [0, 0, 10], target: SIMD3<Float> = .zero) -> PBRRenderer.FrameDraws {
        let view = LookAt(position: eye, target: target, up: [0, 1, 0]).viewMatrix
        var renderer = PBRRenderer(model: asset.model, viewMatrix: view, projectionMatrix: projection, pose: pose)
        renderer.prePassStage = stage
        return renderer.frameDraws(cameraPosition: eye)
    }

    func perBatchCount(_ plan: PBRRenderer.FrameDraws) -> Int {
        plan.groups.map(\.draws.count).reduce(0, +)
    }

    // Static opaque batches with different materials share one pipeline.
    @Test func staticOpaqueBatchesShareAPipeline() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let rest = plan(asset)
        #expect(rest.groups.count == 1 && perBatchCount(rest) == 2)
        #expect(rest.instances == nil)
    }

    // A pose fills the instance table, including one that mirrors an instance.
    @Test func posesFillTheInstanceTable() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        let moved = plan(asset, pose: asset.pose(animation: 0, time: 1))
        #expect(moved.instances?.count == 2)
        let mirrored = plan(asset, pose: asset.pose(animation: 1, time: 1))
        #expect(perBatchCount(mirrored) == 2 && mirrored.instances?.count == 2)
    }

    @Test func cullsOutsideTheView() throws {
        let asset = try GLTFAsset(url: makeTwoMaterialAnimatedFile())
        #expect(perBatchCount(plan(asset, eye: [0, 0, 10], target: [0, 0, 20])) == 0)
    }

    // The transmission pre-pass stages draw only what they need: the opaque stage leaves out glass, the back-face
    // stage only draws double-sided glass, and the main pass draws everything.
    @Test func transmissionStagesSelectBatches() throws {
        let asset = try GLTFAsset(url: makeGlassInFrontOfRedFile())
        func transmissiveCount(_ plan: PBRRenderer.FrameDraws) -> Int {
            plan.opaqueGroups.flatMap(\.batches).filter(\.material.isTransmissive).count
        }
        #expect(perBatchCount(plan(asset)) == 2 && transmissiveCount(plan(asset)) == 1)
        #expect(perBatchCount(plan(asset, stage: .opaque)) == 1 && transmissiveCount(plan(asset, stage: .opaque)) == 0)
        #expect(perBatchCount(plan(asset, stage: .transmissiveBackFaces)) == 0, "Single-sided glass has no back faces to draw")
    }

    // Blended batches are ordered back to front and split into runs by vertex variant.
    @Test func ordersBlendedRunsBackToFront() throws {
        let asset = try GLTFAsset(url: makeBlendedSkinnedAndStaticFile())
        let runs = plan(asset, eye: [0, 0, 4]).blendedRuns
        #expect(runs.map(\.variant.skinned) == [true, false], "The far skinned triangle comes first")
        #expect(runs.map(\.id) == [0, 1])
    }
}
