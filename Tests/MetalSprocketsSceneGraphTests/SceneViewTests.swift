import GeometryLite3D
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import Testing
import simd
@testable import MetalSprocketsSceneGraph

@Test
func defaultCameraIsUsedWithoutCameraNodes() throws {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    #expect(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1) == nil)
    let matrix = lookAt(eye: [0, 0, 5], target: .zero)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: matrix, aspectRatio: 1, defaultCamera: Camera(projection: PerspectiveProjection())))
    #expect(context.cameraMatrix == matrix)
}

@Test
func defaultLightIsAddedOnlyWithoutLights() throws {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, content: .camera(Camera(projection: PerspectiveProjection())))
    let sceneGraph = SceneGraph(root: root)
    let light = Light(type: .directional)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1, defaultLight: light))
    #expect(context.lights.count == 1)

    _ = SceneGraph.Node(parent: root, content: .light(Light(type: .point)))
    let lit = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1, defaultLight: light))
    #expect(lit.lights.count == 1)
    #expect(lit.lights[0].light.type == .point)
}

@Test
func lookAtFacesTarget() {
    let matrix = lookAt(eye: [0, 0, 5], target: .zero)
    let forward = -SIMD3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
    #expect(simd_distance(forward, [0, 0, -1]) < 1e-5)
    #expect(matrix.columns.3 == [0, 0, 5, 1])
}
