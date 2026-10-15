import Metal
import MetalSprocketsAddOns
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

private var material: BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([1, 1, 1]), specular: .color(0), shininess: 1)
}

@Test(arguments: [
    (SceneGraph.Shape.box(width: 2, height: 3, length: 4), SIMD3<Float>(2, 3, 4)),
    (.sphere(radius: 1.5), SIMD3<Float>(3, 3, 3)),
    (.plane(width: 2, height: 1), SIMD3<Float>(2, 1, 0)),
    (.cylinder(radius: 1, height: 2), SIMD3<Float>(2, 2, 2)),
    (.cone(bottomRadius: 1, height: 3), SIMD3<Float>(2, 3, 2)),
    (.cone(topRadius: 0.5, bottomRadius: 1, height: 3), SIMD3<Float>(2, 3, 2)),
    (.capsule(capRadius: 0.5, height: 3), SIMD3<Float>(1, 3, 1)),
    (.torus(ringRadius: 1, pipeRadius: 0.25), SIMD3<Float>(2.5, 0.5, 2.5)),
])
func shapeSizes(shape: SceneGraph.Shape, size: SIMD3<Float>) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = SceneGraph.Node(shape: shape, material: material, device: device)
    let bounds = try #require(node.meshBounds)
    #expect(simd_distance(bounds.max - bounds.min, size) < 0.02)
}

@Test
func textShapeIsExtruded() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = SceneGraph.Node(shape: .text("Hi", fontSize: 2, extrusionDepth: 0.5), material: material, device: device)
    let bounds = try #require(node.meshBounds)
    #expect(abs((bounds.max.z - bounds.min.z) - 0.5) < 1e-4)
    #expect(bounds.max.x > 1)
    #expect(node.label == "Text \"Hi\"")
}

// #101: glyphs with holes (e, a, p) had zero-length normals.
@Test
func textShapeHasUnitNormals() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let mesh = SceneGraph.Shape.text("SceneGraph", fontName: "Helvetica-Bold").metalMesh(device: device)
    let normals = try #require(mesh.float3Values(.normal))
    #expect(!normals.isEmpty)
    #expect(normals.filter { abs(simd_length($0) - 1) > 1e-3 }.isEmpty)
}

@Test
func settingShapeRebuildsMeshAndKeepsMaterial() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = SceneGraph.Node(shape: .box(), material: material, device: device)
    let revision = node.revision.structure
    node.shape = .box(width: 4)
    #expect(node.revision.structure != revision)
    let bounds = try #require(node.meshBounds)
    #expect(abs((bounds.max.x - bounds.min.x) - 4) < 1e-4)
    guard case let .mesh(_, materials, _, _) = node.content else {
        Issue.record("Expected mesh content")
        return
    }
    #expect(materials.first is BlinnPhongSceneMaterial)
}
