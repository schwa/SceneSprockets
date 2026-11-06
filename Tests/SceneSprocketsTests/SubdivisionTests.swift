import Metal
@testable import SceneSprockets
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

// #82
@Test
func subdivisionSplitsTrianglesAndSmooths() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = SceneGraph.Shape.box().metalMesh(device: device)
    let triangles = box.submeshes.reduce(0) { $0 + $1.indexCount / 3 }

    let flat = try #require(box.subdivided(levels: 1, smooth: false))
    #expect(flat.submeshes.reduce(0) { $0 + $1.indexCount / 3 } == triangles * 4)
    // Midpoint split: every vertex stays on the box surface.
    #expect(flat.positions().allSatisfy { abs(max(abs($0.x), abs($0.y), abs($0.z)) - 0.5) < 1e-5 })

    let smooth = try #require(box.subdivided(levels: 2))
    #expect(smooth.submeshes.reduce(0) { $0 + $1.indexCount / 3 } == triangles * 16)
    // Loop smoothing rounds the corners in.
    let farthest = smooth.positions().map(simd_length).max() ?? 0
    #expect(farthest < sqrt(3) / 2 - 0.05)
    // Seams stay closed: copies of a vertex (split for texture coordinates) move together, so no two vertices are
    // almost, but not exactly, at the same place.
    let positions = smooth.positions()
    let cracks = positions.indices.flatMap { i in positions.indices.filter { $0 > i }.map { (i, $0) } }.filter { i, j in
        let distance = simd_distance(positions[i], positions[j])
        return distance > 0 && distance < 1e-3
    }
    #expect(cracks.isEmpty)
}

@Test
func nodeSubdivisionLevelRestoresOriginal() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let node = SceneGraph.Node(shape: .box(), material: try ShaderMaterial.normals(), device: device)
    guard case let .mesh(original, _, _, _) = node.content else {
        Issue.record("Expected a mesh")
        return
    }
    node.subdivisionLevel = 1
    guard case let .mesh(subdivided, _, _, _) = node.content else {
        Issue.record("Expected a mesh")
        return
    }
    #expect(subdivided.vertexCount > original.vertexCount)
    node.subdivisionLevel = 0
    guard case let .mesh(restored, _, _, _) = node.content else {
        Issue.record("Expected a mesh")
        return
    }
    #expect(restored.vertexBuffer === original.vertexBuffer)
    // Changing the shape keeps the level.
    node.subdivisionLevel = 1
    node.shape = .box(width: 2)
    guard case let .mesh(reshaped, _, _, _) = node.content else {
        Issue.record("Expected a mesh")
        return
    }
    #expect(reshaped.vertexCount > original.vertexCount)
    #expect((reshaped.positions().map(\.x).max() ?? 0) > 0.6)
}
