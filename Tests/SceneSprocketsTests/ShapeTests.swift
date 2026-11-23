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

// #515: building shape meshes, text especially, is slow, so equal shapes share one mesh.
@Test
func equalShapesShareOneMesh() {
    let first = SceneGraph.Node(shape: .text("Shared", fontSize: 0.5), material: material)
    let second = SceneGraph.Node(shape: .text("Shared", fontSize: 0.5), material: material)
    let other = SceneGraph.Node(shape: .text("Other", fontSize: 0.5), material: material)
    guard case let .mesh(firstMesh, _, _, _) = first.content, case let .mesh(secondMesh, _, _, _) = second.content, case let .mesh(otherMesh, _, _, _) = other.content else {
        Issue.record("Shape nodes have no mesh")
        return
    }
    #expect(firstMesh.hasSameBuffers(as: secondMesh))
    #expect(!firstMesh.hasSameBuffers(as: otherMesh))
    #expect(second.shape == .text("Shared", fontSize: 0.5))
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

// #373: `shape` describes what the node shows. Replacing the mesh in `content` ends the shape; changing only the
// materials or shadow flags, or subdividing, keeps it.
@Test
func shapeFollowsContent() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = SceneGraph.Node(shape: .sphere(radius: 1), material: material)
    guard case let .mesh(mesh, _, _, _) = node.content else {
        Issue.record("Expected mesh content")
        return
    }
    node.content = .mesh(mesh, material: material, castsShadow: false)
    #expect(node.shape == .sphere(radius: 1))
    node.subdivisionLevel = 1
    #expect(node.shape == .sphere(radius: 1))

    node.content = .mesh(MetalMesh(mesh: .box(), device: device), material: material)
    #expect(node.shape == nil)

    let light = SceneGraph.Node(shape: .box(), material: material)
    light.content = .light(.point())
    #expect(light.shape == nil)
    // A shape set again rebuilds nothing on a non-mesh node.
    light.shape = .box()
    #expect(light.shape == nil)
}

// #80: chamfered boxes, geodesic spheres and rounded planes keep their extents and face outward.
@Test(arguments: [
    (SceneGraph.Shape.box(width: 2, height: 3, length: 4, chamferRadius: 0.5), SIMD3<Float>(2, 3, 4)),
    (.box(width: 1, height: 1, length: 1, chamferRadius: 5), SIMD3<Float>(1, 1, 1)),
    (.sphere(radius: 1.5, isGeodesic: true), SIMD3<Float>(3, 3, 3)),
    (.plane(width: 2, height: 1, cornerRadius: 0.25), SIMD3<Float>(2, 1, 0))
])
func shapeOptionsKeepExtents(shape: SceneGraph.Shape, size: SIMD3<Float>) throws {
    try shapeSizes(shape: shape, size: size)
}

@Test
func chamferedBoxVolume() {
    // A unit cube with r = 0.5 is a sphere of radius 0.5.
    newShapesFaceOutward(shape: .box(width: 1, height: 1, length: 1, chamferRadius: 0.5), volume: 4 / 3 * .pi * 0.125)
    let (width, height, length, radius): (Float, Float, Float, Float) = (2, 3, 4, 0.5)
    let volume = width * height * length - (8 - 4 / 3 * .pi) * radius * radius * radius - (4 - .pi) * radius * radius * ((width - 2 * radius) + (height - 2 * radius) + (length - 2 * radius))
    newShapesFaceOutward(shape: .box(width: width, height: height, length: length, chamferRadius: radius), volume: volume)
}

@Test
func roundedPlaneArea() {
    let mesh = SceneGraph.Shape.plane(width: 2, height: 1, cornerRadius: 0.25).mesh().triangulated()
    var area: Float = 0
    for face in mesh.topology.faces {
        let corners = mesh.topology.halfEdgeLoop(for: face.id).map { mesh.positions[mesh.topology.halfEdges[$0.raw].origin.raw] }
        // Positive z: faces +z like the unrounded plane.
        area += simd_cross(corners[1] - corners[0], corners[2] - corners[0]).z / 2
    }
    #expect(abs(area - (2 - (4 - .pi) * 0.0625)) < 0.01)
}

@Test
func segmentCountsChangeTheMesh() {
    #expect(SceneGraph.Shape.sphere(radius: 1, segmentCount: 8).mesh().positions.count < SceneGraph.Shape.sphere(radius: 1).mesh().positions.count)
    #expect(SceneGraph.Shape.cylinder(segmentCount: 8).mesh().positions.count < SceneGraph.Shape.cylinder().mesh().positions.count)
    #expect(SceneGraph.Shape.torus(ringSegmentCount: 8, pipeSegmentCount: 4).mesh().positions.count < SceneGraph.Shape.torus().mesh().positions.count)
    #expect(SceneGraph.Shape.tube(segmentCount: 8).mesh().positions.count < SceneGraph.Shape.tube().mesh().positions.count)
    #expect(SceneGraph.Shape.capsule(segmentCount: 8).mesh().positions.count < SceneGraph.Shape.capsule().mesh().positions.count)
    #expect(SceneGraph.Shape.cone(segmentCount: 8).mesh().positions.count < SceneGraph.Shape.cone().mesh().positions.count)
    // The defaults draw the same meshes as before the options existed.
    #expect(SceneGraph.Shape.sphere(radius: 1).mesh() == Mesh.sphere(extents: [2, 2, 2], latitudeSegments: 32, longitudeSegments: 64, attributes: [.smoothNormals, .textureCoordinates]))
}

// Archives written before #80 have no option keys; they load with the defaults, and new archives round-trip.
@Test
func shapeDecodesArchivesWithoutOptions() throws {
    let old = #"[{"box":{"width":2,"height":3,"length":4}},{"sphere":{"radius":1}},{"plane":{"width":1,"height":2}},{"torus":{"ringRadius":1,"pipeRadius":0.5}},{"text":{"_0":"Hi","fontName":"Helvetica","fontSize":1,"extrusionDepth":0.1}}]"#
    let shapes = try JSONDecoder().decode([SceneGraph.Shape].self, from: Data(old.utf8))
    #expect(shapes == [.box(width: 2, height: 3, length: 4), .sphere(radius: 1), .plane(width: 1, height: 2), .torus(ringRadius: 1, pipeRadius: 0.5), .text("Hi")])
    let new: [SceneGraph.Shape] = [.box(chamferRadius: 0.1), .sphere(segmentCount: 12, isGeodesic: true), .plane(cornerRadius: 0.2), .cylinder(segmentCount: 7), .cone(segmentCount: 5), .capsule(segmentCount: 9), .torus(ringSegmentCount: 10, pipeSegmentCount: 6), .tube(segmentCount: 11), .pyramid(), .floor(), .extrudedPath("0 0 m 1 0 l 0 1 l h"), .teapot()]
    #expect(try JSONDecoder().decode([SceneGraph.Shape].self, from: JSONEncoder().encode(new)) == new)
}
