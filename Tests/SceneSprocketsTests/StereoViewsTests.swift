import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
import simd
import Testing

// #380: the scene renderer carries per-eye views.

private func translation(_ offset: SIMD3<Float>) -> simd_float4x4 {
    var matrix = matrix_identity_float4x4
    matrix.columns.3 = SIMD4(offset, 1)
    return matrix
}

private let viewport = MTLViewport(originX: 0, originY: 0, width: 100, height: 50, znear: 0, zfar: 1)

private func eyes() -> StereoViews {
    let projection = simd_float4x4.reverseZ * PerspectiveProjection(verticalAngleOfView: .degrees(90)).projectionMatrix(aspectRatio: 1)
    // Eyes 6 cm apart at height 1.5, looking down -Z.
    return StereoViews(
        viewMatrices: [translation([-0.03, 1.5, 0]).inverse, translation([0.03, 1.5, 0]).inverse],
        projectionMatrices: [projection, projection],
        viewports: [viewport, viewport]
    )
}

@Test
func centerCameraIsBetweenTheEyes() {
    let center = eyes().centerCameraMatrix.columns.3
    #expect(simd_distance(SIMD3(center.x, center.y, center.z), [0, 1.5, 0]) < 1e-6)
}

@Test
func relativeViewProjectionsMatchAbsoluteOnes() {
    let views = eyes()
    let origin: SIMD3<Float> = [10, 2, -3]
    let point: SIMD3<Float> = [10.5, 1.8, -5]
    for (absolute, relative) in zip(views.viewProjections, views.relativeViewProjections(origin: origin)) {
        let expected = absolute * SIMD4(point, 1)
        let actual = relative * SIMD4(point - origin, 1)
        #expect(simd_distance(expected, actual) < 1e-4)
    }
}

@Test
@MainActor
func renderContextCarriesStereoViews() throws {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    let views = eyes()
    // No camera node: stereo views stand in for it.
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1, defaultCamera: Camera(projection: PerspectiveProjection()), stereoViews: views))
    #expect(context.viewCount == 2)
    #expect(context.viewProjections == views.viewProjections)
    #expect(context.cameraMatrix == views.centerCameraMatrix)
    #expect(context.projectionMatrix == views.projectionMatrices[0])
    let mono = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1, defaultCamera: Camera(projection: PerspectiveProjection())))
    #expect(mono.viewCount == 1)
    #expect(mono.viewProjections == [mono.projectionMatrix * mono.viewMatrix])
}
