import GeometryLite3D
import Metal
import Observation
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #212: SwiftUI reads statistics during a view update; a query that writes an observed property crashes it
// ('setting value during update').
@Test
func queriesDoNotChangeObservedState() {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    sceneGraph.root.addChild(SceneGraph.Node(content: .light(Light(type: .point))))
    nonisolated(unsafe) var changed = false
    withObservationTracking {
        _ = sceneGraph.statistics
        _ = sceneGraph.bounds
    } onChange: {
        changed = true
    }
    // A fresh traversal, as after any edit.
    _ = sceneGraph.flattened(worldTransform: float4x4(diagonal: [2, 2, 2, 1]))
    _ = sceneGraph.statistics
    #expect(!changed)
}

@Test
func queriesShareOneCachedTraversalUntilSomethingChanges() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
    let root = SceneGraph.Node()
    let mesh = root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    root.addChild(SceneGraph.Node(content: .light(Light(type: .point))))
    root.addChild(SceneGraph.Node(content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
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
