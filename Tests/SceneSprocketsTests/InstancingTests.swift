import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

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
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(Float(index), 0, 0)), content: .mesh(box, material: material(0.8))))
    }
    root.addChild(SceneGraph.Node(content: .mesh(box, material: material(0.3))))
    root.addChild(SceneGraph.Node(content: .mesh(sphere, material: material(0.8))))
    let items = SceneGraph(root: root).meshEntries().map { entry in
        (entry: entry, mesh: entry.mesh, modelMatrix: entry.worldTransform, material: entry.material as! BlinnPhongSceneMaterial)
    }

    let batches = instanceBatches(items)
    #expect(batches.map(\.modelMatrices.count).sorted() == [1, 1, 15])
    let crates = try #require(batches.first { $0.modelMatrices.count == 15 })
    #expect(crates.modelMatrices[3].columns.3 == SIMD4<Float>(3, 0, 0, 1))
}

// #134: opaque batching is cached across frames. Moving nodes reuses it with new matrices; changing a material or
// opacity rebuilds it.
@Test
func cachedOpaqueBatchesFollowChanges() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let nodes = (0..<4).map { index in
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(Float(index), 0, 0)), content: .mesh(box, material: material(0.8))))
    }
    let graph = SceneGraph(root: root)
    let renderer = BlinnPhongMaterialRenderer()

    func groups() throws -> (single: [InstanceBatch], instanced: [InstanceBatch]) {
        let entries = graph.meshEntries()
        let context = RenderContext(viewMatrix: .identity, projectionMatrix: .identity, cameraMatrix: .identity, lights: [], revision: graph.revision, environment: .init())
        let groups = try #require(renderer.cachedOpaqueGroups(entries: entries, inFrustum: entries.map { _ in true }, context: context, cameraPosition: .zero))
        return (groups.flatMap(\.single), groups.flatMap(\.instanced))
    }

    #expect(try groups().instanced.map(\.modelMatrices.count) == [4])

    nodes[2].transform = Transform3D(storing: translation(10, 0, 0))
    let moved = try groups()
    #expect(moved.instanced.map(\.modelMatrices.count) == [4])
    #expect(moved.instanced[0].modelMatrices.contains { $0.columns.3 == SIMD4<Float>(10, 0, 0, 1) })

    nodes[3].content = .mesh(box, material: material(0.3))
    let recolored = try groups()
    #expect(recolored.instanced.map(\.modelMatrices.count) == [3])
    #expect(recolored.single.count == 1)

    nodes[0].opacity = 0.5
    let faded = try groups()
    #expect(faded.instanced.map(\.modelMatrices.count) == [2])
    #expect(faded.single.count == 2)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func instancedBoxesAllRender() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(0, 0, 8)), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(0, 0, 4)), content: .light(Light(type: .point, intensity: 5))))
    for x: Float in [-2, 0, 2] {
        root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(x, 0, 0)), content: .mesh(box, material: material(0.9))))
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

// MARK: - Explicit instancing (#135)

@Test
func instancedMeshGivesAnEntryPerCopy() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    let crates = root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(0, 1, 0)), content: .instancedMesh(box, material: material(0.8), transforms: [translation(-2, 0, 0), translation(0, 0, 0), translation(2, 0, 0)])))
    let graph = SceneGraph(root: root)
    let entries = graph.meshEntries()
    #expect(entries.map(\.instanceIndex) == [0, 1, 2])
    #expect(entries.map(\.worldTransform.columns.3) == [[-2, 1, 0, 1], [0, 1, 0, 1], [2, 1, 0, 1]])
    #expect(entries.allSatisfy { $0.node === crates })
    // The node's bounds hold every copy; each entry's are the box's own.
    let nodeBounds = try #require(crates.meshBounds)
    #expect(nodeBounds.min.x == -2.5 && nodeBounds.max.x == 2.5)
    #expect(entries.allSatisfy { $0.meshBounds?.max.x == 0.5 })
    // A transform-only change keeps each copy's offset.
    crates.transform = Transform3D(storing: translation(0, 3, 0))
    #expect(graph.meshEntries().map(\.worldTransform.columns.3) == [[-2, 3, 0, 1], [0, 3, 0, 1], [2, 3, 0, 1]])
    // Copies batch into one instanced draw like nodes do.
    let items = graph.meshEntries().map { entry in
        (entry: entry, mesh: entry.mesh, modelMatrix: entry.worldTransform, material: entry.material as! BlinnPhongSceneMaterial)
    }
    #expect(instanceBatches(items).map(\.modelMatrices.count) == [3])
}

@Test
func hitTestReportsTheInstanceIndex() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(content: .instancedMesh(box, material: material(0.8), transforms: [translation(-2, 0, 0), translation(2, 0, 0)])))
    let hits = SceneGraph(root: root).hitTest(segmentFrom: [2, 0, 5], to: [2, 0, -5])
    #expect(hits.first?.instanceIndex == 1)
    #expect(abs((hits.first?.position.z ?? 0) - 0.5) < 1e-4)
    #expect(SceneGraph(root: root).hitTest(segmentFrom: [0, 0, 5], to: [0, 0, -5]).isEmpty)
}

@Test
func instancedMeshRendersEveryCopy() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(0, 0, 8)), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation(0, 0, 4)), content: .light(Light(type: .point, intensity: 5))))
    root.addChild(SceneGraph.Node(content: .instancedMesh(box, material: material(0.9), transforms: [-2, 0, 2].map { translation($0, 0, 0) })))
    let texture = try OffscreenRenderer(size: CGSize(width: 64, height: 64)).render(BlinnPhongSceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1)).texture

    func pixel(_ x: Int) -> SIMD4<UInt8> {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, 32, 1, 1), mipmapLevel: 0)
        return value
    }
    for x in [13, 32, 51] {
        #expect(pixel(x).z > 20)
    }
    #expect(pixel(22).z < 3)
}

@Test
func instancedShapeRoundTripsThroughAnArchive() throws {
    let root = SceneGraph.Node()
    let crates = root.addChild(SceneGraph.Node(label: "Crates", shape: .box(), material: material(0.8)))
    guard case let .mesh(mesh, materials, _, _) = crates.content else {
        Issue.record("not a mesh")
        return
    }
    let transforms = [translation(-2, 0, 0), translation(2, 1, 0)]
    crates.content = .instancedMesh(mesh, materials: materials, transforms: transforms)
    #expect(crates.shape == .box())
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = Archive(materialTypes: [BlinnPhongSceneMaterial.self])
    #expect(try archive.write(SceneGraph(root: root), to: url).isEmpty)
    let loaded = try #require(try archive.read(from: url).sceneGraph.root.childNode(withLabel: "Crates"))
    guard case let .instancedMesh(_, _, loadedTransforms, _, _) = loaded.content else {
        Issue.record("not instanced: \(loaded.content)")
        return
    }
    #expect(loadedTransforms == transforms)
    #expect(loaded.shape == .box())
}
