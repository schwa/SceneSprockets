import GeometryLite3D
@testable import SceneSprockets
import simd
import Testing

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
}

private func makeScene() -> (SceneGraph, SceneGraph.Node, SceneGraph.Node) {
    let root = SceneGraph.Node(transform: translation(0, 1, 0))
    let first = SceneGraph.Node(parent: root, transform: translation(0, 0, 5), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    let second = SceneGraph.Node(parent: root, transform: translation(3, 0, 0), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(90)))))
    return (SceneGraph(root: root), first, second)
}

@Test
func cameraNodeWorldTransformDrivesView() throws {
    let (sceneGraph, _, _) = makeScene()
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
    #expect(context.cameraMatrix.columns.3 == SIMD4<Float>(0, 1, 5, 1))
    #expect(context.viewMatrix.columns.3 == SIMD4<Float>(0, -1, -5, 1))
}

@Test
func chosenCameraNodeIsUsed() throws {
    let (sceneGraph, _, second) = makeScene()
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: second, cameraMatrix: nil, aspectRatio: 1))
    #expect(context.cameraMatrix.columns.3 == SIMD4<Float>(3, 1, 0, 1))
    let expected = PerspectiveProjection(verticalAngleOfView: .degrees(90)).projectionMatrix(aspectRatio: 1)
    #expect(context.projectionMatrix == .reverseZ * expected)
}

// #176: an editor camera must win over the scene's camera nodes.
@Test
func cameraOverrideReplacesCameraNodeProjection() throws {
    let (sceneGraph, _, _) = makeScene()
    let editorCamera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(20)))
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: translation(7, 0, 0), aspectRatio: 1, cameraOverride: editorCamera))
    let expected = PerspectiveProjection(verticalAngleOfView: .degrees(20)).projectionMatrix(aspectRatio: 1)
    #expect(context.projectionMatrix == .reverseZ * expected)
    #expect(context.cameraMatrix.columns.3 == SIMD4<Float>(7, 0, 0, 1))
}

@Test
func explicitCameraMatrixOverridesNode() throws {
    let (sceneGraph, _, _) = makeScene()
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: translation(7, 0, 0), aspectRatio: 1))
    #expect(context.cameraMatrix.columns.3 == SIMD4<Float>(7, 0, 0, 1))
}
