import Metal
import MetalSprocketsAddOns
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

private func material() -> BlinnPhongMaterial {
    BlinnPhongMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
}

@Test
func hitTestFindsNearestBoxFirst() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let near = SceneGraph.Node(parent: root, label: "near", content: .mesh(box, material: material()))
    near.trs.translation = [0, 0, -5]
    let far = SceneGraph.Node(parent: root, label: "far", content: .mesh(box, material: material()))
    far.trs.translation = [0, 0, -10]
    let sideways = SceneGraph.Node(parent: root, label: "sideways", content: .mesh(box, material: material()))
    sideways.trs.translation = [10, 0, -5]
    let sceneGraph = SceneGraph(root: root)

    let hits = sceneGraph.hitTest(SceneGraph.Ray(origin: .zero, direction: [0, 0, -1]))
    let bounds = try #require(near.meshBounds)
    #expect(hits.first?.node === near)
    #expect(hits.contains { $0.node === far })
    #expect(!hits.contains { $0.node === sideways })
    let first = try #require(hits.first)
    #expect(abs(first.distance - (5 - bounds.max.z)) < 1e-4)
    #expect(simd_distance(first.normal, [0, 0, 1]) < 1e-4)
    #expect(abs(first.position.z - (-5 + bounds.max.z)) < 1e-4)
}

@Test
func hitTestIgnoresHiddenNodesAndHitsBehindOrigin() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let hidden = SceneGraph.Node(parent: root, content: .mesh(box, material: material()))
    hidden.trs.translation = [0, 0, -5]
    hidden.isVisible = false
    let behind = SceneGraph.Node(parent: root, content: .mesh(box, material: material()))
    behind.trs.translation = [0, 0, 5]
    let hits = SceneGraph(root: root).hitTest(SceneGraph.Ray(origin: .zero, direction: [0, 0, -1]))
    #expect(hits.isEmpty)
}

@Test
func hitTestFollowsScaledTransforms() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let node = SceneGraph.Node(content: .mesh(box, material: material()))
    node.trs = SceneGraph.TRS(translation: [3, 0, 0], scale: [10, 1, 1])
    let bounds = try #require(node.meshBounds)
    // Misses the unscaled box at x = 3 + 2 * maxX, hits the scaled one.
    let hits = SceneGraph(root: node).hitTest(SceneGraph.Ray(origin: [3 + 2 * bounds.max.x, 0, 10], direction: [0, 0, -1]))
    #expect(hits.count == 2)
    #expect(abs(hits[0].distance - (10 - bounds.max.z)) < 1e-4)
}

@Test
func viewPointRayGoesThroughCenter() {
    let camera = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [1, 2, 3, 1]))
    let fov: Float = .pi / 3
    let near: Float = 0.1
    let far: Float = 100
    let y = 1 / tan(fov / 2)
    // Right-handed perspective, depth 0...1.
    let projection = simd_float4x4(columns: (
        [y, 0, 0, 0],
        [0, y, 0, 0],
        [0, 0, far / (near - far), -1],
        [0, 0, near * far / (near - far), 0]
    ))
    let center = SceneGraph.Ray(viewPoint: [50, 50], viewSize: [100, 100], cameraMatrix: camera, projectionMatrix: projection)
    #expect(simd_distance(center.direction, [0, 0, -1]) < 1e-4)
    #expect(simd_distance(center.origin, [1, 2, 3 - near]) < 1e-3)
    let top = SceneGraph.Ray(viewPoint: [50, 0], viewSize: [100, 100], cameraMatrix: camera, projectionMatrix: projection)
    #expect(abs(acos(simd_dot(top.direction, [0, 0, -1])) - fov / 2) < 1e-3)
    #expect(top.direction.y > 0)
}
