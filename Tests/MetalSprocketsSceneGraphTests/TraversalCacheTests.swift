import Metal
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import GeometryLite3D
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

@Test
func queriesShareOneCachedTraversalUntilSomethingChanges() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
    let root = SceneGraph.Node()
    let mesh = SceneGraph.Node(parent: root, content: .mesh(box, material: material))
    _ = SceneGraph.Node(parent: root, content: .light(Light(type: .point)))
    _ = SceneGraph.Node(parent: root, content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    let sceneGraph = SceneGraph(root: root)

    // A frame's worth of queries: one traversal.
    _ = sceneGraph.meshEntries()
    _ = sceneGraph.lightNodes()
    _ = sceneGraph.cameraNodes()
    #expect(sceneGraph.traversalCount == 1)

    // Next frame, nothing changed: no traversal.
    _ = sceneGraph.meshEntries()
    _ = sceneGraph.lightNodes()
    #expect(sceneGraph.traversalCount == 1)

    // A transform change refreshes world transforms.
    mesh.trs.translation = [3, 0, 0]
    #expect(sceneGraph.meshEntries()[0].worldTransform.columns.3 == SIMD4<Float>(3, 0, 0, 1))
    #expect(sceneGraph.traversalCount == 2)

    // A non-identity starting transform bypasses the cache.
    _ = sceneGraph.meshEntries(worldTransform: float4x4(diagonal: [2, 2, 2, 1]))
    #expect(sceneGraph.traversalCount == 3)
}
