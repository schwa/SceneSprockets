import Foundation
import Metal
import MetalSprocketsAddOns
import simd
import Testing
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphModelIO
@testable import MetalSprocketsSceneGraphPBR

private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

// Two triangles in one OBJ object, each with its own MTL material.
private func makeOBJ() throws -> URL {
    let directory = try temporaryDirectory()
    let mtl = """
    newmtl Red
    Kd 1 0 0
    newmtl Blue
    Kd 0 0 1
    """
    let obj = """
    mtllib scene.mtl
    o Triangles
    v 0 0 0
    v 1 0 0
    v 0 1 0
    v 2 0 0
    v 3 0 0
    v 2 1 0
    usemtl Red
    f 1 2 3
    usemtl Blue
    f 4 5 6
    """
    try Data(mtl.utf8).write(to: directory.appendingPathComponent("scene.mtl"))
    let url = directory.appendingPathComponent("scene.obj")
    try Data(obj.utf8).write(to: url)
    return url
}

// A mesh under a translated transform.
private func makeUSDA() throws -> URL {
    let usda = """
    #usda 1.0
    (
        defaultPrim = "Root"
        upAxis = "Y"
    )
    def Xform "Root"
    {
        def Xform "Group"
        {
            double3 xformOp:translate = (5, 0, 0)
            uniform token[] xformOpOrder = ["xformOp:translate"]

            def Mesh "Triangle"
            {
                int[] faceVertexCounts = [3]
                int[] faceVertexIndices = [0, 1, 2]
                point3f[] points = [(0, 0, 0), (1, 0, 0), (0, 1, 0)]
            }
        }
    }
    """
    let url = try temporaryDirectory().appendingPathComponent("scene.usda")
    try Data(usda.utf8).write(to: url)
    return url
}

@Test
func objLoadsWithPerSubmeshMaterials() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try ModelIOSceneGraph(url: try makeOBJ(), device: device)
    let entries = result.sceneGraph.meshEntries()
    #expect(entries.count == 2)
    let colors = entries.compactMap { ($0.material as? PBRSceneMaterial)?.pbrMaterial.uniforms.baseColorFactor }
    #expect(Set(colors.map { [$0.x, $0.y, $0.z] }) == [[1, 0, 0], [0, 0, 1]])
    #expect(result.animation == nil)

    let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: entries)
    #expect(model.opaqueInstances.count == 2)
}

@Test
func objLoadsAsBlinnPhong() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try ModelIOSceneGraph(url: try makeOBJ(), device: device, materials: .blinnPhong)
    #expect(result.sceneGraph.meshEntries().allSatisfy { $0.material is BlinnPhongMaterial })
}

@Test
func usdHierarchyAndTransformsAreKept() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try ModelIOSceneGraph(url: try makeUSDA(), device: device)
    let entries = result.sceneGraph.meshEntries()
    let entry = try #require(entries.first)
    #expect(entries.count == 1)
    #expect(entry.node.label == "Triangle")
    #expect(entry.node.parent?.label == "Group")
    #expect(entry.worldTransform.columns.3 == [5, 0, 0, 1])
}
