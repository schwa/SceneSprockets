import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsGLTF
import simd
import Testing
@testable import MetalSprocketsSceneGraph

// Mesh node 0 (x = 10) has two triangle primitives with different materials, skinned to joint node 1 (x = 3), which
// is animated from x = 3 to x = -3. Node 2 holds a camera and node 3 (a child of node 2) a point light.
private func makeSceneFile() throws -> URL {
    var data = Data()
    func append<T>(_ values: [T]) {
        values.withUnsafeBytes { data.append(contentsOf: $0) }
    }
    append([Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 0, 1, 0)) // positions, 36 bytes at 0
    append([UInt16](repeating: 0, count: 12)) // JOINTS_0, 24 bytes at 36
    append([Float](arrayLiteral: 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)) // WEIGHTS_0, 48 bytes at 60
    append([Float](arrayLiteral: 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1)) // inverse bind, 64 bytes at 108
    append([Float](arrayLiteral: 0, 1)) // times, 8 bytes at 172
    append([Float](arrayLiteral: 3, 0, 0, -3, 0, 0)) // joint translations, 24 bytes at 180
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_lights_punctual"],
      "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "color": [1, 0.5, 0.25], "intensity": 7, "range": 20}]}},
      "scene": 0,
      "scenes": [{"name": "Scene", "nodes": [0, 1, 2]}],
      "nodes": [
        {"name": "Mesh", "mesh": 0, "skin": 0, "translation": [10, 0, 0]},
        {"name": "Joint", "translation": [3, 0, 0]},
        {"name": "Camera", "camera": 0, "translation": [0, 0, 5], "children": [3]},
        {"name": "Light", "rotation": [0, 0.7071068, 0, 0.7071068], "extensions": {"KHR_lights_punctual": {"light": 0}}}
      ],
      "cameras": [{"type": "perspective", "perspective": {"yfov": 0.8, "znear": 0.1, "zfar": 50}}],
      "skins": [{"joints": [1], "inverseBindMatrices": 3}],
      "meshes": [{"name": "Triangles", "primitives": [
        {"attributes": {"POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2}, "material": 0},
        {"attributes": {"POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2}, "material": 1}
      ]}],
      "materials": [
        {"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}},
        {"pbrMetallicRoughness": {"baseColorFactor": [0, 0, 1, 1]}}
      ],
      "animations": [{"name": "Slide", "channels": [{"sampler": 0, "target": {"node": 1, "path": "translation"}}], "samplers": [{"input": 4, "output": 5}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5123, "count": 3, "type": "VEC4"},
        {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5126, "count": 1, "type": "MAT4"},
        {"bufferView": 4, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 5, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 24},
        {"buffer": 0, "byteOffset": 60, "byteLength": 48},
        {"buffer": 0, "byteOffset": 108, "byteLength": 64},
        {"buffer": 0, "byteOffset": 172, "byteLength": 8},
        {"buffer": 0, "byteOffset": 180, "byteLength": 24}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    return url
}

@Test
func gltfSceneLoadsIntoSceneGraph() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let asset = try GLTFAsset(url: try makeSceneFile(), device: device)
    let result = try asset.makeSceneGraph(device: device)

    #expect(result.sceneGraph.root.label == "Scene")
    #expect(result.sceneGraph.root.children.map(\.label) == ["Mesh", "Joint", "Camera"])

    let meshNode = try #require(result.nodes[0])
    #expect(meshNode.trs.translation == [10, 0, 0])
    guard case let .mesh(mesh, materials, _, _) = meshNode.content else {
        Issue.record("Expected mesh content")
        return
    }
    #expect(mesh.submeshes.count == 2)
    #expect(mesh.vertexCount == 6)
    #expect(mesh.submeshes[1].indices == [3, 4, 5])
    let colors = materials.compactMap { ($0 as? PBRSceneMaterial)?.pbrMaterial.uniforms.baseColorFactor }
    #expect(colors == [[1, 0, 0, 1], [0, 0, 1, 1]])

    let joint = try #require(result.nodes[1])
    let skin = try #require(meshNode.skin)
    #expect(skin.joints.count == 1 && skin.joints[0] === joint)
    #expect(meshNode.skinVertices.count == 6)
    #expect(meshNode.skinVertices.allSatisfy { $0.joints == .zero && $0.weights == [1, 0, 0, 0] })

    let cameraNode = try #require(result.nodes[2])
    guard case let .camera(camera) = cameraNode.content else {
        Issue.record("Expected camera content")
        return
    }
    #expect(camera.projection is PerspectiveProjection)

    let lightNode = try #require(result.nodes[3])
    #expect(lightNode.parent === cameraNode)
    guard case let .light(light) = lightNode.content else {
        Issue.record("Expected light content")
        return
    }
    #expect(light.type == .point)
    #expect(light.color == [1, 0.5, 0.25])
    #expect(light.intensity == 7)
    #expect(light.range == 20)

    let clip = try #require(result.animations.first)
    #expect(clip.name == "Slide")
    clip.apply(at: 1)
    #expect(joint.trs.translation == [-3, 0, 0])
}

@Test
func gltfSceneGraphBuildsPBRModel() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let asset = try GLTFAsset(url: try makeSceneFile(), device: device)
    let sceneGraph = try asset.makeSceneGraph(device: device).sceneGraph
    let model = try PBRSceneGraphModelBuilder(device: device).makeModel(entries: sceneGraph.meshEntries())
    #expect(model.opaqueInstances.count == 2)
    #expect(model.skins.count == 1)
}

// #54: EXT_mesh_gpu_instancing copies become child nodes, KHR_node_visibility hides nodes.
@Test
func gltfInstancingAndVisibilityAreMapped() throws {
    var data = Data()
    [Float](arrayLiteral: 0, 0, 0, 1, 0, 0, 0, 1, 0, 5, 0, 0, -5, 0, 0).withUnsafeBytes { data.append(contentsOf: $0) }
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["EXT_mesh_gpu_instancing", "KHR_node_visibility"],
      "scenes": [{"nodes": [0, 1]}],
      "nodes": [
        {"name": "Copies", "mesh": 0, "extensions": {"EXT_mesh_gpu_instancing": {"attributes": {"TRANSLATION": 1}}}},
        {"name": "Hidden", "mesh": 0, "extensions": {"KHR_node_visibility": {"visible": false}}}
      ],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "VEC3"}
      ],
      "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 24}],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
    let copies = try #require(result.nodes[0])
    #expect(copies.children.count == 2)
    #expect(copies.children.map { $0.transform.columns.3.x } == [5, -5])
    let hidden = try #require(result.nodes[1])
    #expect(!hidden.isVisible)
    // Only the two copies are drawn.
    #expect(result.sceneGraph.meshEntries().count == 2)
}

// #92: morph target names come from the mesh's extras.targetNames.
@Test
func gltfMorphTargetNamesAreRead() throws {
    var data = Data()
    [Float](arrayLiteral: 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 0, 0, 1).withUnsafeBytes { data.append(contentsOf: $0) }
    let json = """
    {
      "asset": {"version": "2.0"},
      "scenes": [{"nodes": [0]}],
      "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "targets": [{"POSITION": 1}]}], "weights": [0.25], "extras": {"targetNames": ["Smile"]}}],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 1], "max": [0, 0, 1]}
      ],
      "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 36}, {"buffer": 0, "byteOffset": 36, "byteLength": 36}],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
    let node = try #require(result.nodes[0])
    #expect(node.morphTargets.map(\.name) == ["Smile"])
    #expect(node.morphWeight(forTargetNamed: "Smile") == 0.25)
    node.setMorphWeight(1, forTargetNamed: "Smile")
    #expect(node.morphWeights == [1])
    #expect(node.morphWeight(forTargetNamed: "Frown") == nil)
}
