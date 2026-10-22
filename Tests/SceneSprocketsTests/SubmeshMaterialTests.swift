import Metal
import SwiftMesh
import Testing
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong

@Test
func eachSubmeshGetsItsOwnMaterial() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var metalMesh = MetalMesh(mesh: .box(), device: device)
    metalMesh.submeshes.append(metalMesh.submeshes[0])
    #expect(metalMesh.submeshes.count == 2)

    let red = BlinnPhongSceneMaterial(ambient: .color([1, 0, 0]), diffuse: .color([1, 0, 0]), specular: .color([1, 1, 1]), shininess: 1)
    let blue = BlinnPhongSceneMaterial(ambient: .color([0, 0, 1]), diffuse: .color([0, 0, 1]), specular: .color([1, 1, 1]), shininess: 2)
    let root = SceneGraph.Node(content: .mesh(metalMesh, materials: [red, blue]))
    let entries = SceneGraph(root: root).meshNodes(withMaterial: BlinnPhongSceneMaterial.self)

    #expect(entries.count == 2)
    #expect(entries.map(\.submeshIndex) == [0, 1])
    #expect(entries.map(\.material.shininess) == [1, 2])
}

@Test
func singleMaterialAppliesToAllSubmeshes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var metalMesh = MetalMesh(mesh: .box(), device: device)
    metalMesh.submeshes.append(metalMesh.submeshes[0])

    let material = BlinnPhongSceneMaterial(ambient: .color([1, 0, 0]), diffuse: .color([1, 0, 0]), specular: .color([1, 1, 1]), shininess: 7)
    let root = SceneGraph.Node(content: .mesh(metalMesh, material: material))
    let entries = SceneGraph(root: root).meshNodes(withMaterial: BlinnPhongSceneMaterial.self)

    #expect(entries.map(\.submeshIndex) == [0, 1])
    #expect(entries.map(\.material.shininess) == [7, 7])
}
