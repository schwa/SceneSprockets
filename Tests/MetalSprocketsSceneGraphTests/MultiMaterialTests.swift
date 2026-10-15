import Metal
import MetalSprockets
import MetalSprocketsAddOns
import SwiftMesh
import Testing
@testable import MetalSprocketsSceneGraph

private struct UnlitMaterial: MetalSprocketsSceneGraph.Material {
    var color: SIMD3<Float>
}

private struct UnlitRenderer: SceneGraphMaterialRenderer {
    var materialType: any MetalSprocketsSceneGraph.Material.Type { UnlitMaterial.self }

    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        EmptyElement().eraseToAnyElement()
    }
}

@Test
func mixedMaterialsArePartitionedPerRenderer() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let blinnPhong = BlinnPhongMaterial(ambient: .color([1, 0, 0]), diffuse: .color([1, 0, 0]), specular: .color([1, 1, 1]), shininess: 1)

    let root = SceneGraph.Node(children: [
        SceneGraph.Node(content: .mesh(box, material: blinnPhong)),
        SceneGraph.Node(content: .mesh(box, material: UnlitMaterial(color: [0, 1, 0]))),
        SceneGraph.Node(content: .mesh(box, material: UnlitMaterial(color: [0, 0, 1]))),
    ])

    let renderers: [any SceneGraphMaterialRenderer] = [BlinnPhongMaterialRenderer(), UnlitRenderer()]
    let partitions = partitionMeshEntries(SceneGraph(root: root).meshEntries(), renderers: renderers)

    #expect(partitions.count == 2)
    #expect(partitions[0].count == 1)
    #expect(partitions[1].count == 2)
}
