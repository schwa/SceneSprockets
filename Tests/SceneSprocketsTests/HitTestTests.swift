import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

private func material() -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
}

// #402: hit tests read a mesh's positions and indices once and keep them while the buffers live.
@Test
func hitTestGeometryIsReadOnce() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let cache = HitTestGeometryCache()
    // The pool releases Metal's autoreleased references, so the buffers go when the mesh does.
    try autoreleasepool {
        let box = MetalMesh(mesh: .box(), device: device)
        let first = cache.positions(of: box)
        let second = cache.positions(of: box)
        #expect(first.count == box.vertexCount)
        #expect(first.withUnsafeBufferPointer { $0.baseAddress } == second.withUnsafeBufferPointer { $0.baseAddress })
        let submesh = try #require(box.submeshes.first)
        let indices = cache.indices(of: submesh)
        #expect(indices == submesh.indices)
        #expect(indices.withUnsafeBufferPointer { $0.baseAddress } == cache.indices(of: submesh).withUnsafeBufferPointer { $0.baseAddress })
        #expect(cache.count == 2)
    }
    // Entries go with their buffers.
    #expect(cache.isEmpty)
}

@Test
func hitTestFindsNearestBoxFirst() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let near = root.addChild(SceneGraph.Node(label: "near", content: .mesh(box, material: material())))
    near.transform.translation = [0, 0, -5]
    let far = root.addChild(SceneGraph.Node(label: "far", content: .mesh(box, material: material())))
    far.transform.translation = [0, 0, -10]
    let sideways = root.addChild(SceneGraph.Node(label: "sideways", content: .mesh(box, material: material())))
    sideways.transform.translation = [10, 0, -5]
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
    let hidden = root.addChild(SceneGraph.Node(content: .mesh(box, material: material())))
    hidden.transform.translation = [0, 0, -5]
    hidden.isVisible = false
    let behind = root.addChild(SceneGraph.Node(content: .mesh(box, material: material())))
    behind.transform.translation = [0, 0, 5]
    let hits = SceneGraph(root: root).hitTest(Ray3D(origin: .zero, direction: [0, 0, -1]))
    #expect(hits.isEmpty)
}

@Test
func hitTestFollowsScaledTransforms() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let node = SceneGraph.Node(content: .mesh(box, material: material()))
    node.transform = Transform3D(translation: [3, 0, 0], scale: [10, 1, 1])
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
    let viewProjection = ViewProjection(viewMatrix: camera.inverse, projectionMatrix: projection, isReverseZ: false, viewSize: [100, 100])
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
    let near = root.addChild(SceneGraph.Node(label: "near", transform: .init(translation: [0, 0, -5]), content: .mesh(box, material: material())))
    let far = root.addChild(SceneGraph.Node(label: "far", transform: .init(translation: [0, 0, -10]), content: .mesh(box, material: material())))
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
    // A 2x2 quad in XY: texture coordinates follow x and y.
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh()
    let node = SceneGraph.Node(content: .mesh(quad, material: material()))
    let hit = try #require(SceneGraph(root: node).hitTest(Ray3D(origin: [0.5, 0.5, 5], direction: [0, 0, -1])).first)
    #expect(abs(hit.barycentric.sum() - 1) < 1e-5)
    #expect(simd_distance(hit.localPosition, [0.5, 0.5, 0]) < 1e-4)
    let uv = try #require(hit.textureCoordinates())
    // Center is (0.5, 0.5); a quarter of the way right and up.
    #expect(abs(uv.x - 0.75) < 1e-3)
    #expect(abs(uv.y - 0.25) < 1e-3 || abs(uv.y - 0.75) < 1e-3)
}

// #240: a viewport built from a camera casts the same rays as the projection itself, for every depth mode.
@Test(arguments: [
    PerspectiveProjection.DepthMode.standard(zClip: 0.1 ... 100),
    .reversed(zClip: 0.1 ... 100),
    .reversedInfinite(zNear: 0.1)
])
func viewportFromCameraCastsTheProjectionsRays(_ depthMode: PerspectiveProjection.DepthMode) {
    let projection = PerspectiveProjection(verticalAngleOfView: .degrees(50), depthMode: depthMode)
    let cameraMatrix = LookAt(position: [3, 2, 5], target: .zero, up: [0, 1, 0]).cameraMatrix
    let viewSize: SIMD2<Float> = [640, 480]
    let viewport = Viewport(cameraMatrix: cameraMatrix, camera: Camera(projection: projection), viewSize: viewSize, drawableSize: viewSize * 2)
    let reference = ViewProjection(viewMatrix: cameraMatrix.inverse, projection: projection, viewSize: viewSize)
    for point: SIMD2<Float> in [[0, 0], [320, 240], [600, 50]] {
        let ray = viewport.ray(through: point)
        let expected = reference.ray(through: point)
        #expect(simd_distance(ray.origin, expected.origin) < 1e-3)
        #expect(simd_distance(simd_normalize(ray.direction), simd_normalize(expected.direction)) < 1e-4)
    }
}

// #404: a primitive restart starts a new strip, whose winding counts from its own first triangle.
@Test(arguments: [MTLIndexType.uint32, .uint16])
func stripsRestartAtPrimitiveRestartIndices(indexType: MTLIndexType) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // Two unit quads facing +z, at x 0...1 and x 2...3; the second strip starts at index 5, an odd position.
    let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0], [2, 0, 0], [3, 0, 0], [2, 1, 0], [3, 1, 0]]
    let restart: UInt32 = indexType == .uint16 ? 0xFFFF : 0xFFFF_FFFF
    let indices: [UInt32] = [0, 1, 2, 3, restart, 4, 5, 6, 7]
    // Index buffer made here: MetalMesh's array initializer reads every index as a vertex.
    var mesh = MetalMesh(device: device, attributes: [.positions(positions)], submeshes: [.init(indices: Array(0..<8), primitiveType: .triangleStrip)])
    let buffer = try #require(indexType == .uint16
        ? device.makeBuffer(bytes: indices.map { UInt16(truncatingIfNeeded: $0) }, length: indices.count * 2)
        : device.makeBuffer(bytes: indices, length: indices.count * 4))
    mesh.submeshes[0] = MetalMesh.Submesh(indexBuffer: buffer, indexCount: indices.count, indexType: indexType, primitiveType: .triangleStrip)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(content: .mesh(mesh, material: material())))
    let sceneGraph = SceneGraph(root: root)
    let options = SceneGraph.HitTestOptions(backFaceCulling: true)
    for point: SIMD2<Float> in [[0.2, 0.2], [0.8, 0.8], [2.2, 0.2], [2.8, 0.8]] {
        let front = sceneGraph.hitTest(Ray3D(origin: [point.x, point.y, 1], direction: [0, 0, -1]), options: options)
        let back = sceneGraph.hitTest(Ray3D(origin: [point.x, point.y, -1], direction: [0, 0, 1]), options: options)
        #expect(front.count == 1, "front at \(point)")
        #expect(back.isEmpty, "back at \(point)")
    }
    // Nothing between the quads, where a triangle across the restart would be.
    #expect(sceneGraph.hitTest(Ray3D(origin: [1.5, 0.5, 1], direction: [0, 0, -1])).isEmpty)
}

// #403: odd triangles of a strip have reversed index order, so their front face follows the even triangles'.
@Test
func backFaceCullingKeepsFrontFacesOfEveryStripTriangle() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    // A unit quad facing +z as one strip: triangle 0 is (0, 1, 2), triangle 1 is (2, 1, 3) in winding order.
    let positions: [SIMD3<Float>] = [[0, 0, 0], [1, 0, 0], [0, 1, 0], [1, 1, 0]]
    let mesh = MetalMesh(device: device, attributes: [.positions(positions)], submeshes: [.init(indices: [0, 1, 2, 3], primitiveType: .triangleStrip)])
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(content: .mesh(mesh, material: material())))
    let sceneGraph = SceneGraph(root: root)
    let options = SceneGraph.HitTestOptions(backFaceCulling: true)
    for point: SIMD2<Float> in [[0.2, 0.2], [0.8, 0.8]] {
        let front = sceneGraph.hitTest(Ray3D(origin: [point.x, point.y, 1], direction: [0, 0, -1]), options: options)
        let back = sceneGraph.hitTest(Ray3D(origin: [point.x, point.y, -1], direction: [0, 0, 1]), options: options)
        #expect(front.count == 1, "front at \(point)")
        #expect(back.isEmpty, "back at \(point)")
    }
}
