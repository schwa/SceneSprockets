import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import SwiftMesh
import Testing

private struct UnlitMaterial: SceneMaterial {
    var color: SIMD3<Float>
}

private struct UnlitRenderer: MaterialRenderer {
    var materialType: any SceneMaterial.Type { UnlitMaterial.self }

    func makeElement(entries _: [SceneGraph.MeshEntry], context _: RenderContext) -> AnyElement {
        EmptyElement().eraseToAnyElement()
    }
}

@Test
func mixedMaterialsArePartitionedPerRenderer() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let blinnPhong = BlinnPhongSceneMaterial(ambient: .color([1, 0, 0]), diffuse: .color([1, 0, 0]), specular: .color([1, 1, 1]), shininess: 1)

    let root = SceneGraph.Node(children: [
        SceneGraph.Node(content: .mesh(box, material: blinnPhong)),
        SceneGraph.Node(content: .mesh(box, material: UnlitMaterial(color: [0, 1, 0]))),
        SceneGraph.Node(content: .mesh(box, material: UnlitMaterial(color: [0, 0, 1])))
    ])

    let renderers: [any MaterialRenderer] = [BlinnPhongMaterialRenderer(), UnlitRenderer()]
    let partitions = partitionMeshEntries(SceneGraph(root: root).meshEntries(), renderers: renderers)

    #expect(partitions.count == 2)
    #expect(partitions[0].count == 1)
    #expect(partitions[1].count == 2)
}
