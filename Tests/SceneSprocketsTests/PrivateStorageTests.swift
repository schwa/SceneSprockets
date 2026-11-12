import GeometryLite3D
import Metal
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import SwiftMesh
import Testing

// #303: meshes whose vertex and index buffers are in private storage still have bounds, hit tests and PBR models.

@MainActor
private func privateCopy(of mesh: MetalMesh, device: MTLDevice) throws -> MetalMesh {
    let queue = try #require(device.makeCommandQueue())
    let commandBuffer = try #require(queue.makeCommandBuffer())
    let blit = try #require(commandBuffer.makeBlitCommandEncoder())
    func moved(_ buffer: MTLBuffer) throws -> MTLBuffer {
        let copy = try #require(device.makeBuffer(length: buffer.length, options: .storageModePrivate))
        blit.copy(from: buffer, sourceOffset: 0, to: copy, destinationOffset: 0, size: buffer.length)
        return copy
    }
    var result = mesh
    result.vertexBuffers = try mesh.vertexBuffers.mapValues(moved)
    result.submeshes = try mesh.submeshes.map { submesh in
        var submesh = submesh
        submesh.indexBuffer = try moved(submesh.indexBuffer)
        return submesh
    }
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    return result
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func privateStorageMeshesCanBeReadOnTheCPU() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let shared = MetalMesh(mesh: .box(), device: device)
    let mesh = try privateCopy(of: shared, device: device)
    try #require(mesh.vertexBuffer.storageMode == .private)

    // Bounds.
    let root = SceneGraph.Node()
    let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.5), specular: .color(0), shininess: 1)
    let node = root.addChild(SceneGraph.Node(content: .mesh(mesh, material: material)))
    let sceneGraph = SceneGraph(root: root)
    let bounds = try #require(node.meshBounds)
    let expected = try #require(shared.positionBounds())
    #expect(bounds.min == expected.min && bounds.max == expected.max)

    // Hit testing reads positions and indices.
    let hits = sceneGraph.hitTest(Ray3D(origin: [0, 0, 5], direction: [0, 0, -1]))
    #expect(hits.first?.node === node)
    #expect(abs((hits.first?.distance ?? 0) - 4.5) < 1e-4)

    // PBR conversion reads every attribute and the indices.
    let pbr = PBRSceneMaterial()
    let entry = SceneGraph.MeshEntry(node: node, worldTransform: .identity, mesh: mesh, submeshIndex: 0, material: pbr, castsShadow: true, receivesShadow: true)
    _ = try PBRSceneGraphModelBuilder().makeModel(entries: [entry])
    let input = pbrPrimitiveInput(entry: entry, attributes: mesh.cpuReadable().vertexAttributeData(), skinned: false)
    #expect(input.indices == shared.submeshes[0].indices)
}
