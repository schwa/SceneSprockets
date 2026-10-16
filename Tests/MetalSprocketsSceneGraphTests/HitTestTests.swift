import GeometryLite3D
import Metal
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphBlinnPhong

private func material() -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
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

    let hits = sceneGraph.hitTest(Ray3D(origin: .zero, direction: [0, 0, -1]))
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
    let hits = SceneGraph(root: root).hitTest(Ray3D(origin: .zero, direction: [0, 0, -1]))
    #expect(hits.isEmpty)
}

@Test
func hitTestFollowsScaledTransforms() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let node = SceneGraph.Node(content: .mesh(box, material: material()))
    node.trs = Transform3D(translation: [3, 0, 0], scale: [10, 1, 1])
    let bounds = try #require(node.meshBounds)
    // Misses the unscaled box at x = 3 + 2 * maxX, hits the scaled one.
    let hits = SceneGraph(root: node).hitTest(Ray3D(origin: [3 + 2 * bounds.max.x, 0, 10], direction: [0, 0, -1]))
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
    let viewProjection = ViewProjection(viewMatrix: camera.inverse, projectionMatrix: projection, isReversedDepth: false, viewSize: [100, 100])
    let center = viewProjection.ray(through: [50, 50])
    #expect(simd_distance(center.direction, [0, 0, -1]) < 1e-4)
    #expect(simd_distance(center.origin, [1, 2, 3 - near]) < 1e-3)
    let top = viewProjection.ray(through: [50, 0])
    #expect(abs(acos(simd_dot(top.direction, [0, 0, -1])) - fov / 2) < 1e-3)
    #expect(top.direction.y > 0)
}

// #93
private func twoBoxes() throws -> (SceneGraph, near: SceneGraph.Node, far: SceneGraph.Node) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let near = SceneGraph.Node(parent: root, label: "near", trs: .init(translation: [0, 0, -5]), content: .mesh(box, material: material()))
    let far = SceneGraph.Node(parent: root, label: "far", trs: .init(translation: [0, 0, -10]), content: .mesh(box, material: material()))
    return (SceneGraph(root: root), near, far)
}

@Test
func hitTestOptionsCullBackFacesAndStopEarly() throws {
    let (sceneGraph, near, _) = try twoBoxes()
    // Off center, so the ray does not run along the faces' diagonals.
    let ray = Ray3D(origin: [0.1, 0.2, 0], direction: [0, 0, -1])
    // Each box has a front and a back face on the ray.
    #expect(sceneGraph.hitTest(ray).count == 4)
    #expect(sceneGraph.hitTest(ray, options: .init(backFaceCulling: true)).count == 2)
    #expect(sceneGraph.hitTest(ray, options: .init(firstFoundOnly: true)).count == 1)
    let subtree = sceneGraph.hitTest(ray, options: .init(rootNode: near))
    #expect(subtree.count == 2 && subtree.allSatisfy { $0.node === near })
}

@Test
func segmentHitTestStopsAtItsEnd() throws {
    let (sceneGraph, near, _) = try twoBoxes()
    let hits = sceneGraph.hitTest(segmentFrom: [0.1, 0.2, 0], to: [0.1, 0.2, -7])
    #expect(hits.count == 2 && hits.allSatisfy { $0.node === near })
}

@Test
func boundingBoxHitsReportEntryFace() throws {
    let (sceneGraph, near, _) = try twoBoxes()
    let hits = sceneGraph.hitTest(Ray3D(origin: .zero, direction: [0, 0, -1]), options: .init(boundingBoxOnly: true))
    #expect(hits.count == 2)
    let first = try #require(hits.first)
    #expect(first.node === near)
    #expect(first.triangleIndex == -1)
    #expect(simd_distance(first.normal, [0, 0, 1]) < 1e-4)
    #expect(abs(first.position.z - (-5 + near.meshBounds!.max.z)) < 1e-4)
}

@Test
func hitsReportBarycentricsAndTextureCoordinates() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // A 2x2 quad in XY: texture coordinates follow x and y.
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let node = SceneGraph.Node(content: .mesh(quad, material: material()))
    let hit = try #require(SceneGraph(root: node).hitTest(Ray3D(origin: [0.5, 0.5, 5], direction: [0, 0, -1])).first)
    #expect(abs(hit.barycentric.sum() - 1) < 1e-5)
    #expect(simd_distance(hit.localPosition, [0.5, 0.5, 0]) < 1e-4)
    let uv = try #require(hit.textureCoordinates())
    // Center is (0.5, 0.5); a quarter of the way right and up.
    #expect(abs(uv.x - 0.75) < 1e-3)
    #expect(abs(uv.y - 0.25) < 1e-3 || abs(uv.y - 0.75) < 1e-3)
}
