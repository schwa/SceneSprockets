import Metal
import SceneSprocketsAddOns
import simd
import Testing

@Test
func primitiveDistances() {
    #expect(SignedDistanceShape.sphere(center: .zero, radius: 1).distance(at: [2, 0, 0]) == 1)
    #expect(SignedDistanceShape.sphere(center: .zero, radius: 1).distance(at: .zero) == -1)
    #expect(SignedDistanceShape.box(center: .zero, halfExtents: [1, 2, 3]).distance(at: [0, 3, 0]) == 1)
    #expect(SignedDistanceShape.capsule(from: [0, -1, 0], to: [0, 1, 0], radius: 0.5).distance(at: [0, 2, 0]) == 0.5)
}

@Test
func smoothUnionBridgesTheGapBetweenNearbySpheres() {
    let spheres: [SignedDistanceShape] = [.sphere(center: [-1.1, 0, 0], radius: 1), .sphere(center: [1.1, 0, 0], radius: 1)]
    // Hard union: the point between them is outside.
    #expect(SignedDistanceShape.union(spheres).distance(at: .zero) > 0)
    // Smooth union: they merge.
    #expect(SignedDistanceShape.union(spheres, smoothness: 0.8).distance(at: .zero) < 0)
}

@Test
func subtractionAndIntersection() {
    let sphere = SignedDistanceShape.sphere(center: .zero, radius: 1)
    let cutter = SignedDistanceShape.box(center: [1, 0, 0], halfExtents: [1, 1, 1])
    #expect(SignedDistanceShape.subtraction(sphere, removing: cutter).distance(at: [0.5, 0, 0]) > 0)
    #expect(SignedDistanceShape.subtraction(sphere, removing: cutter).distance(at: [-0.5, 0, 0]) < 0)
    #expect(SignedDistanceShape.intersection([sphere, cutter]).distance(at: [0.5, 0, 0]) < 0)
    #expect(SignedDistanceShape.intersection([sphere, cutter]).distance(at: [-0.5, 0, 0]) > 0)
}

@Test
func sphereSurfaceLiesOnTheSphereAndFacesOut() {
    let shape = SignedDistanceShape.sphere(center: [1, 2, 3], radius: 1.5)
    let surface = shape.surface(cellSize: 0.1)
    #expect(surface.indices.count > 1_000)
    #expect(surface.positions.allSatisfy { abs(simd_length($0 - [1, 2, 3]) - 1.5) < 0.02 })
    // Every triangle winds counter-clockwise seen from outside.
    let wrongWay = stride(from: 0, to: surface.indices.count, by: 3).filter { triangle in
        let (a, b, c) = (surface.positions[Int(surface.indices[triangle])], surface.positions[Int(surface.indices[triangle + 1])], surface.positions[Int(surface.indices[triangle + 2])])
        return simd_dot(simd_cross(b - a, c - a), (a + b + c) / 3 - [1, 2, 3]) <= 0
    }
    #expect(wrongWay.isEmpty)
    #expect(surface.normals.indices.allSatisfy { simd_dot(surface.normals[$0], simd_normalize(surface.positions[$0] - [1, 2, 3])) > 0.99 })
}

@Test
func emptyShapeMakesNoMesh() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let disjoint = SignedDistanceShape.intersection([.sphere(center: [-5, 0, 0], radius: 1), .sphere(center: [5, 0, 0], radius: 1)])
    #expect(disjoint.makeMesh(device: device, cellSize: 0.2) == nil)
    #expect(SignedDistanceShape.union([]).makeMesh(device: device, cellSize: 0.2) == nil)
    #expect(SignedDistanceShape.sphere(center: .zero, radius: 1).makeMesh(device: device, cellSize: 0.2) != nil)
}
