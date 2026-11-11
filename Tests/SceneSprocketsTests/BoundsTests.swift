import GeometryLite3D
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

private func approximatelyEqual(_ lhs: BoundingBox3D?, _ rhs: BoundingBox3D) -> Bool {
    guard let lhs else {
        return false
    }
    return simd_distance(lhs.min, rhs.min) < 0.0001 && simd_distance(lhs.max, rhs.max) < 0.0001
}

private func makeBox(device: MTLDevice, layout: MetalMesh.BufferLayout = .interleaved) -> MetalMesh {
    MetalMesh(mesh: .box(), device: device, bufferLayout: layout)
}

private var material: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
}

@Test
func meshBoundsComeFromPositions() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for layout in [MetalMesh.BufferLayout.interleaved, .separateBuffers] {
        let box = makeBox(device: device, layout: layout)
        let node = SceneGraph.Node(content: .mesh(box, material: material))
        #expect(approximatelyEqual(node.meshBounds, BoundingBox3D(min: [-0.5, -0.5, -0.5], max: [0.5, 0.5, 0.5])))
    }
}

@Test
func nonMeshNodesHaveNoBounds() {
    let node = SceneGraph.Node(content: .light(Light(type: .point)))
    #expect(node.meshBounds == nil)
    #expect(SceneGraph(root: node).bounds == nil)
}

@Test
func worldBoundsIncludeTransformsAndChildren() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = makeBox(device: device)
    let root = SceneGraph.Node()
    root.transform.translation = [0, 10, 0]
    let group = root.addChild(SceneGraph.Node())
    group.transform.scale = [2, 2, 2]
    let left = group.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    left.transform.translation = [-1, 0, 0]
    let right = group.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    right.transform.translation = [1, 0, 0]
    let sceneGraph = SceneGraph(root: root)

    // Group spans x -1.5...1.5 locally, scaled by 2, then moved up 10.
    #expect(approximatelyEqual(sceneGraph.bounds, BoundingBox3D(min: [-3, 9, -1], max: [3, 11, 1])))
    #expect(approximatelyEqual(sceneGraph.worldBounds(of: right), BoundingBox3D(min: [1, 9, -1], max: [3, 11, 1])))

    right.transform.translation = [5, 0, 0]
    #expect(approximatelyEqual(sceneGraph.bounds, BoundingBox3D(min: [-3, 9, -1], max: [11, 11, 1])))

    right.removeFromParent()
    #expect(approximatelyEqual(sceneGraph.bounds, BoundingBox3D(min: [-3, 9, -1], max: [-1, 11, 1])))
}
