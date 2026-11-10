import Foundation
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

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
    (.tube(innerRadius: 0.5, outerRadius: 1, height: 2), SIMD3<Float>(2, 2, 2)),
    (.pyramid(width: 2, height: 3, length: 4), SIMD3<Float>(2, 3, 4)),
    (.floor(width: 10, length: 20), SIMD3<Float>(10, 0, 20)),
    (.extrudedPath("0 0 m 2 0 l 2 1 l 0 1 l h", extrusionDepth: 0.5), SIMD3<Float>(2, 1, 0.5))
])
func shapeSizes(shape: SceneGraph.Shape, size: SIMD3<Float>) throws {
    let node = SceneGraph.Node(shape: shape, material: material)
    let bounds = try #require(node.meshBounds)
    #expect(simd_distance(bounds.max - bounds.min, size) < 0.02)
}

// #81: closed shapes enclose positive volume (faces point outward) close to the analytic volume; the floor faces up.
@Test(arguments: [
    (SceneGraph.Shape.tube(innerRadius: 0.5, outerRadius: 1, height: 2), Float.pi * (1 - 0.25) * 2),
    (.pyramid(width: 2, height: 3, length: 4), Float(2 * 3 * 4) / 3),
    (.extrudedPath("0 0 m 2 0 l 2 1 l 0 1 l h", extrusionDepth: 0.5), 1)
])
func newShapesFaceOutward(shape: SceneGraph.Shape, volume: Float) {
    let mesh = shape.mesh().triangulated()
    var signedVolume: Float = 0
    for face in mesh.topology.faces {
        let corners = mesh.topology.halfEdgeLoop(for: face.id).map { mesh.positions[mesh.topology.halfEdges[$0.raw].origin.raw] }
        signedVolume += simd_dot(corners[0], simd_cross(corners[1], corners[2])) / 6
    }
    #expect(abs(signedVolume - volume) / volume < 0.02)
}

// #336: the teapot is a built-in shape whose widest side is its diameter, with smooth normals.
@Test
func teapotShapeFitsItsDiameter() throws {
    let node = SceneGraph.Node(shape: .teapot(diameter: 2), material: material)
    let bounds = try #require(node.meshBounds)
    let size = bounds.max - bounds.min
    #expect(abs(max(size.x, size.y, size.z) - 2) < 0.02)
    #expect(node.label == "Teapot")
    let data = try JSONEncoder().encode(SceneGraph.Shape.teapot(diameter: 2))
    #expect(try JSONDecoder().decode(SceneGraph.Shape.self, from: data) == .teapot(diameter: 2))
}

@Test
func floorFacesUp() throws {
    let normals = try #require(SceneGraph.Shape.floor().metalMesh().float3Values(.normal))
    #expect(normals.allSatisfy { simd_distance($0, [0, 1, 0]) < 1e-4 })
}

@Test
func newShapesRoundTripThroughCodable() throws {
    for shape in [SceneGraph.Shape.tube(), .pyramid(), .floor(), .extrudedPath("0 0 m 1 0 l 0 1 l h")] {
        let data = try JSONEncoder().encode(shape)
        #expect(try JSONDecoder().decode(SceneGraph.Shape.self, from: data) == shape)
    }
}

@Test
func textShapeIsExtruded() throws {
    let node = SceneGraph.Node(shape: .text("Hi", fontSize: 2, extrusionDepth: 0.5), material: material)
    let bounds = try #require(node.meshBounds)
    #expect(abs((bounds.max.z - bounds.min.z) - 0.5) < 1e-4)
    #expect(bounds.max.x > 1)
    #expect(node.label == "Text \"Hi\"")
}

// #101: glyphs with holes (e, a, p) had zero-length normals.
@Test
func textShapeHasUnitNormals() throws {
    let mesh = SceneGraph.Shape.text("SceneGraph", fontName: "Helvetica-Bold").metalMesh()
    let normals = try #require(mesh.float3Values(.normal))
    #expect(!normals.isEmpty)
    #expect(!normals.contains { abs(simd_length($0) - 1) > 1e-3 })
}

@Test
func settingShapeRebuildsMeshAndKeepsMaterial() throws {
    let node = SceneGraph.Node(shape: .box(), material: material)
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
