import GeometryLite3D
import Metal
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

private let projection = PerspectiveProjection(verticalAngleOfView: .degrees(60)).projectionMatrix(aspectRatio: 1)
private let camera = simd_float4x4(translation: [0, 0, 5])
private let viewSize = SIMD2<Float>(200, 200)

@Test
func projectPointMapsCenterAndRoundTrips() {
    let center = SceneGraph.projectPoint([0, 0, 0], viewSize: viewSize, cameraMatrix: camera, projectionMatrix: projection)
    #expect(abs(center.x - 100) < 0.01 && abs(center.y - 100) < 0.01)
    // +Y is up in the world and down in view coordinates.
    #expect(SceneGraph.projectPoint([0, 1, 0], viewSize: viewSize, cameraMatrix: camera, projectionMatrix: projection).y < 100)
    let point = SIMD3<Float>(0.7, -0.4, -1.2)
    let projected = SceneGraph.projectPoint(point, viewSize: viewSize, cameraMatrix: camera, projectionMatrix: projection)
    let back = SceneGraph.unprojectPoint(projected, viewSize: viewSize, cameraMatrix: camera, projectionMatrix: projection)
    #expect(simd_distance(back, point) < 1e-3)
}

@Test
func frustumQueriesFindVisibleNodes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let mesh = MetalMesh(mesh: .box(), device: device)
    let material = try ShaderMaterial.normals()
    let root = SceneGraph.Node()
    let inside = SceneGraph.Node(parent: root, content: .mesh(mesh, material: material))
    let behind = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 20]), content: .mesh(mesh, material: material))
    let group = SceneGraph.Node(parent: root, trs: .init(translation: [100, 0, 0]))
    _ = SceneGraph.Node(parent: group, content: .mesh(mesh, material: material))
    let sceneGraph = SceneGraph(root: root)
    let nodes = sceneGraph.nodesInsideFrustum(cameraMatrix: camera, projectionMatrix: projection)
    #expect(nodes.count == 1 && nodes.first === inside)
    #expect(sceneGraph.isNode(inside, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
    #expect(!sceneGraph.isNode(behind, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
    #expect(!sceneGraph.isNode(group, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
    inside.isVisible = false
    #expect(!sceneGraph.isNode(inside, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
}
