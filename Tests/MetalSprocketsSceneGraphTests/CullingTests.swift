import GeometryLite3D
import Metal
import MetalSprocketsAddOns
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

private extension simd_float4x4 {
    static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
    }
}

private let unitBox = BoundingBox(min: [-0.5, -0.5, -0.5], max: [0.5, 0.5, 0.5])

private func viewProjection() -> simd_float4x4 {
    // Camera at origin looking down -Z.
    PerspectiveProjection(verticalAngleOfView: .degrees(90)).projectionMatrix(aspectRatio: 1)
}

@Test
func boxesInsideAndOutsideFrustum() {
    let matrix = viewProjection()
    #expect(isInFrustum(unitBox.transformed(by: .translation(0, 0, -5)), viewProjection: matrix))
    #expect(!isInFrustum(unitBox.transformed(by: .translation(0, 0, 5)), viewProjection: matrix))
    #expect(!isInFrustum(unitBox.transformed(by: .translation(50, 0, -5)), viewProjection: matrix))
    // Straddles the left plane.
    #expect(isInFrustum(unitBox.transformed(by: .translation(-5, 0, -5)), viewProjection: matrix))
}

@Test
func cullingDropsEntriesOutsideFrustum() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, label: "front", transform: .translation(0, 0, -5), content: .mesh(box, material: material))
    _ = SceneGraph.Node(parent: root, label: "behind", transform: .translation(0, 0, 5), content: .mesh(box, material: material))

    let visible = culledMeshEntries(SceneGraph(root: root).meshEntries(), viewProjection: viewProjection())
    #expect(visible.map(\.node.label) == ["front"])
}

@Test
func entriesAreSortedFrontToBack() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongMaterial(ambient: .color([1, 1, 1]), diffuse: .color([1, 1, 1]), specular: .color([1, 1, 1]), shininess: 1)
    let root = SceneGraph.Node()
    for (label, z) in [("far", -20), ("near", -2), ("middle", -8)] {
        _ = SceneGraph.Node(parent: root, label: label, transform: .translation(0, 0, Float(z)), content: .mesh(box, material: material))
    }
    let sorted = sortedFrontToBack(SceneGraph(root: root).meshEntries(), cameraPosition: .zero)
    #expect(sorted.map(\.node.label) == ["near", "middle", "far"])
}
