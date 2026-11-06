import Foundation
import Metal
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import SwiftGLTF
import Testing

// #157: a loaded glTF is saved as the file itself (with its buffers), and read back by loading it again. The model
// root's own changes, such as a move, are kept.
@MainActor
struct ModelReferenceArchiveTests {
    let device = MTLCreateSystemDefaultDevice()!
    let archive = SceneArchive(materialTypes: [BlinnPhongSceneMaterial.self, PBRSceneMaterial.self], meshCodec: GLTFMeshCodec(), modelLoader: ModelFileLoader())

    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(SceneArchive.pathExtension)
    }

    // A red triangle as Triangle.gltf with its buffer in Triangle.bin.
    func writeTriangle(in folder: URL) throws -> URL {
        let positions: [Float] = [0, 0, 0, 1, 0, 0, 0, 1, 0]
        let indices: [UInt16] = [0, 1, 2]
        var binary = positions.withUnsafeBytes { Data($0) }
        binary += indices.withUnsafeBytes { Data($0) }
        let document = Document(
            scene: Index(0),
            scenes: [Scene(nodes: [Index(0)])],
            nodes: [Node(name: "Triangle", mesh: Index(0))],
            meshes: [Mesh(primitives: [.init(attributes: [.POSITION: Index(0)], indices: Index(1), material: Index(0))])],
            accessors: [
                Accessor(bufferView: Index(0), componentType: .FLOAT, count: 3, type: .VEC3, max: [1, 1, 0], min: [0, 0, 0]),
                Accessor(bufferView: Index(1), componentType: .UNSIGNED_SHORT, count: 3, type: .SCALAR)
            ],
            bufferViews: [
                BufferView(buffer: Index(0), byteLength: 36, target: .ARRAY_BUFFER),
                BufferView(buffer: Index(0), byteOffset: 36, byteLength: 6, target: .ELEMENT_ARRAY_BUFFER)
            ],
            buffers: [Buffer(byteLength: binary.count, uri: URI("Triangle.bin"))],
            materials: [Material(pbrMetallicRoughness: .init(baseColorFactor: [1, 0, 0, 1]))]
        )
        let url = folder.appendingPathComponent("Triangle.gltf")
        try document.jsonData().write(to: url)
        try binary.write(to: folder.appendingPathComponent("Triangle.bin"))
        return url
    }

    @Test
    func loadedGLTFIsKeptByReference() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, _) = try ModelFile.load(writeTriangle(in: folder), device: device)
        model.trs.translation = [5, 0, 0]
        let root = SceneGraph.Node()
        root.addChild(model)
        let meshCount = SceneGraph(root: root).meshEntries().count
        #expect(meshCount == 1)

        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.write(SceneGraph(root: root), to: url)
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("models/0/Triangle.gltf").path))
        #expect(FileManager.default.fileExists(atPath: url.appendingPathComponent("models/0/Triangle.bin").path))
        // The subtree is not written as generated meshes.
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("meshes").path))

        let (loaded, warnings) = try archive.read(from: url, device: device)
        #expect(warnings.isEmpty)
        let loadedModel = try #require(loaded.root.children.first)
        #expect(loadedModel.label == "Triangle")
        #expect(loadedModel.trs.translation == [5, 0, 0])
        #expect(loaded.meshEntries().count == meshCount)
        #expect(loadedModel.modelSource == model.modelSource)

        // Saving the loaded scene again keeps the reference.
        let again = temporaryURL()
        defer { try? FileManager.default.removeItem(at: again) }
        try archive.write(loaded, to: again)
        let json = { (url: URL) in try String(contentsOf: url.appendingPathComponent("scene.json"), encoding: .utf8) }
        #expect(try json(again) == json(url))
    }

    // Without a model loader, the subtree is saved like any other (meshes through the mesh codec).
    @Test
    func withoutALoaderTheSubtreeIsSaved() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (model, _) = try ModelFile.load(writeTriangle(in: folder), device: device)
        let root = SceneGraph.Node()
        root.addChild(model)
        var archive = archive
        archive.modelLoader = nil
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.write(SceneGraph(root: root), to: url)
        #expect(!FileManager.default.fileExists(atPath: url.appendingPathComponent("models").path))
        #expect(try archive.read(from: url, device: device).sceneGraph.meshEntries().count == 1)
    }
}
