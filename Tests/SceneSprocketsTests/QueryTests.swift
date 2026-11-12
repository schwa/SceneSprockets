import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

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

// #95
@Test
func statisticsCountVisibleContent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: .box(), device: device), material: ShaderMaterial.normals())))
    let hidden = root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: .box(), device: device), material: ShaderMaterial.normals())))
    hidden.isVisible = false
    root.addChild(SceneGraph.Node(content: .light(Light(type: .point))))
    let statistics = SceneGraph(root: root).statistics
    #expect(statistics.nodeCount == 3)
    #expect(statistics.meshCount == 1)
    #expect(statistics.triangleCount == 12)
    #expect(statistics.lightCount == 1)
    #expect(statistics.cameraCount == 0)
}

@Test
func frustumQueriesFindVisibleNodes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let mesh = MetalMesh(mesh: .box(), device: device)
    let material = ShaderMaterial.normals()
    let root = SceneGraph.Node()
    let inside = root.addChild(SceneGraph.Node(content: .mesh(mesh, material: material)))
    let behind = root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 20]), content: .mesh(mesh, material: material)))
    let group = root.addChild(SceneGraph.Node(transform: .init(translation: [100, 0, 0])))
    group.addChild(SceneGraph.Node(content: .mesh(mesh, material: material)))
    let sceneGraph = SceneGraph(root: root)
    let nodes = sceneGraph.nodesInsideFrustum(cameraMatrix: camera, projectionMatrix: projection)
    #expect(nodes.count == 1 && nodes.first === inside)
    #expect(sceneGraph.isNode(inside, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
    #expect(!sceneGraph.isNode(behind, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
    #expect(!sceneGraph.isNode(group, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
    inside.isVisible = false
    #expect(!sceneGraph.isNode(inside, insideFrustumWithCameraMatrix: camera, projectionMatrix: projection))
}
