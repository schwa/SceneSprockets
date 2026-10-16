import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphBlinnPhong

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [x, y, z, 1]))
}

private func material(_ red: Float) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color([0.2, 0.05, 0.05]), diffuse: .color([red, 0.1, 0.1]), specular: .color([0.2, 0.2, 0.2]), shininess: 8)
}

@Test
func identicalMeshAndMaterialShareABatch() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let sphere = MetalMesh(mesh: .sphere(), device: device)
    let root = SceneGraph.Node()
    for index in 0..<15 {
        _ = SceneGraph.Node(parent: root, transform: translation(Float(index), 0, 0), content: .mesh(box, material: material(0.8)))
    }
    _ = SceneGraph.Node(parent: root, content: .mesh(box, material: material(0.3)))
    _ = SceneGraph.Node(parent: root, content: .mesh(sphere, material: material(0.8)))
    let items = SceneGraph(root: root).meshEntries().map { entry in
        (entry: entry, mesh: entry.mesh, modelMatrix: entry.worldTransform, material: entry.material as! BlinnPhongSceneMaterial)
    }

    let batches = instanceBatches(items)
    #expect(batches.map(\.modelMatrices.count).sorted() == [1, 1, 15])
    let crates = try #require(batches.first { $0.modelMatrices.count == 15 })
    #expect(crates.modelMatrices[3].columns.3 == SIMD4<Float>(3, 0, 0, 1))
}

@Test
@MainActor
func instancedBoxesAllRender() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, transform: translation(0, 0, 8), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    _ = SceneGraph.Node(parent: root, transform: translation(0, 0, 4), content: .light(Light(type: .point, intensity: 5)))
    for x: Float in [-2, 0, 2] {
        _ = SceneGraph.Node(parent: root, transform: translation(x, 0, 0), content: .mesh(box, material: material(0.9)))
    }
    let texture = try OffscreenRenderer(size: CGSize(width: 64, height: 64)).render(BlinnPhongSceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1)).texture

    func pixel(_ x: Int) -> SIMD4<UInt8> {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, 32, 1, 1), mipmapLevel: 0)
        return value
    }
    // Boxes at x = -2, 0, 2 project to about 13, 32 and 51 px; gaps between them stay black.
    for x in [13, 32, 51] {
        #expect(pixel(x).z > 20)
    }
    #expect(pixel(22).z < 3)
}
