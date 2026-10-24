import CoreGraphics
import Foundation
import GeometryLite3D
import ImageIO
import Metal
import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import Testing
import UniformTypeIdentifiers
@testable import SceneSprockets
@testable import SceneSprocketsPBR

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

// #54: KHR_animation_pointer channels for visibility, lights and cameras become property channels.
@Test
func gltfPointerAnimationsAreMapped() throws {
    var data = Data()
    // Times, then visibility, light intensity and camera yfov keyframes.
    [Float](arrayLiteral: 0, 1, 1, 0, 1, 5, 0.5, 1).withUnsafeBytes { data.append(contentsOf: $0) }
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_animation_pointer", "KHR_node_visibility", "KHR_lights_punctual"],
      "extensions": {"KHR_lights_punctual": {"lights": [{"type": "point", "intensity": 1}]}},
      "scenes": [{"nodes": [0, 1, 2]}],
      "nodes": [
        {"name": "Blinker"},
        {"name": "Lamp", "extensions": {"KHR_lights_punctual": {"light": 0}}},
        {"name": "Eye", "camera": 0}
      ],
      "cameras": [{"type": "perspective", "perspective": {"yfov": 0.5, "znear": 0.1, "zfar": 100}}],
      "animations": [{
        "samplers": [
          {"input": 0, "output": 1, "interpolation": "STEP"},
          {"input": 0, "output": 2},
          {"input": 0, "output": 3}
        ],
        "channels": [
          {"sampler": 0, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/nodes/0/extensions/KHR_node_visibility/visible"}}}},
          {"sampler": 1, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/extensions/KHR_lights_punctual/lights/0/intensity"}}}},
          {"sampler": 2, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/cameras/0/perspective/yfov"}}}}
        ]
      }],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR"},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "SCALAR"},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "SCALAR"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 8},
        {"buffer": 0, "byteOffset": 8, "byteLength": 8},
        {"buffer": 0, "byteOffset": 16, "byteLength": 8},
        {"buffer": 0, "byteOffset": 24, "byteLength": 8}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
    let clip = try #require(result.animations.first)
    #expect(clip.channels.count == 3)
    #expect(!result.warnings.contains { $0.contains("animation channels skipped") })

    clip.apply(at: 1)
    let blinker = try #require(result.nodes[0])
    #expect(!blinker.isVisible)
    let lamp = try #require(result.nodes[1])
    guard case let .light(light) = lamp.content else {
        Issue.record("Lamp has no light")
        return
    }
    #expect(light.intensity == 5)
    let eye = try #require(result.nodes[2])
    guard case let .camera(camera) = eye.content, let projection = camera.projection as? PerspectiveProjection else {
        Issue.record("Eye has no perspective camera")
        return
    }
    #expect(abs(projection.verticalAngleOfView.radians - 1) < 1e-5)
}

// A triangle whose material's baseColorFactor goes from white to red and roughnessFactor from 1 to 0.2 over 1 s,
// through KHR_animation_pointer.
private func materialPointerAnimationSceneGraph() throws -> GLTFSceneGraph {
    var data = Data()
    // Triangle positions, times, then baseColorFactor and roughnessFactor keyframes.
    [Float](arrayLiteral: 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 1, 1, 1, 1, 1, 1, 0, 0, 1, 1, 0.2).withUnsafeBytes { data.append(contentsOf: $0) }
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_animation_pointer"],
      "scenes": [{"nodes": [0]}],
      "nodes": [{"mesh": 0}],
      "materials": [{"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1], "roughnessFactor": 1}}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
      "animations": [{
        "samplers": [{"input": 1, "output": 2}, {"input": 1, "output": 3}],
        "channels": [
          {"sampler": 0, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/materials/0/pbrMetallicRoughness/baseColorFactor"}}}},
          {"sampler": 1, "target": {"path": "pointer", "extensions": {"KHR_animation_pointer": {"pointer": "/materials/0/pbrMetallicRoughness/roughnessFactor"}}}}
        ]
      }],
      "accessors": [
        {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [0, 0, 0], "max": [1, 1, 0]},
        {"bufferView": 1, "componentType": 5126, "count": 2, "type": "SCALAR", "min": [0], "max": [1]},
        {"bufferView": 2, "componentType": 5126, "count": 2, "type": "VEC4"},
        {"bufferView": 3, "componentType": 5126, "count": 2, "type": "SCALAR"}
      ],
      "bufferViews": [
        {"buffer": 0, "byteOffset": 0, "byteLength": 36},
        {"buffer": 0, "byteOffset": 36, "byteLength": 8},
        {"buffer": 0, "byteOffset": 44, "byteLength": 32},
        {"buffer": 0, "byteOffset": 76, "byteLength": 8}
      ],
      "buffers": [{"byteLength": \(data.count), "uri": "data:application/octet-stream;base64,\(data.base64EncodedString())"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    return try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
}

private func pbrMaterial(of node: SceneGraph.Node?) throws -> PBRSceneMaterial {
    guard case let .mesh(_, materials, _, _) = try #require(node).content, let material = materials.first as? PBRSceneMaterial else {
        throw MaterialMissing()
    }
    return material
}

private struct MaterialMissing: Error {}

// #54: KHR_animation_pointer material channels change the mesh's PBR material.
@Test
func gltfMaterialPointerAnimationsAreMapped() throws {
    let result = try materialPointerAnimationSceneGraph()
    let clip = try #require(result.animations.first)
    #expect(clip.channels.count == 2)
    #expect(!result.warnings.contains { $0.contains("animation channels skipped") })

    clip.apply(at: 1)
    let material = try pbrMaterial(of: result.nodes[0])
    #expect(material.pbrMaterial.uniforms.baseColorFactor == [1, 0, 0, 1])
    #expect(abs(material.pbrMaterial.uniforms.roughnessFactor - 0.2) < 1e-5)
}

// #122: the mixer blends material channels against the material's rest value.
@Test
func gltfMaterialChannelsBlendInMixer() throws {
    let result = try materialPointerAnimationSceneGraph()
    let clip = try #require(result.animations.first)
    let mixer = SceneGraph.AnimationMixer(clips: [clip])
    // An additive layer adds half the offset from rest; it needs the rest value.
    mixer.apply([.init(clip: 0, time: 1, weight: 0.5, mode: .additive)])
    let material = try pbrMaterial(of: result.nodes[0])
    // Halfway from rest (roughness 1, white) to the sample (0.2, red).
    #expect(abs(material.pbrMaterial.uniforms.roughnessFactor - 0.6) < 1e-4)
    #expect(simd_distance(material.pbrMaterial.uniforms.baseColorFactor, [1, 0.5, 0.5, 1]) < 1e-4)
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

// A 4 x 4 PNG of one opaque gray.
private func grayPNG() throws -> Data {
    let pixels = [UInt8](repeating: 128, count: 64)
    let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
    let image = try #require(CGImage(width: 4, height: 4, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
}

// #121: the scene's EXT_lights_image_based light becomes the scene environment; variant names are kept.
@Test
func gltfImageBasedLightAndVariantNamesAreMapped() throws {
    let face = try grayPNG().base64EncodedString()
    let images = Array(repeating: #"{"uri": "data:image/png;base64,\#(face)"}"#, count: 6).joined(separator: ", ")
    let coefficients = Array(repeating: "[0, 0, 0]", count: 9).joined(separator: ", ")
    let buffer = [Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 0, 1, 0).withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["EXT_lights_image_based", "KHR_materials_variants"],
      "extensions": {
        "EXT_lights_image_based": {"lights": [{"intensity": 1, "irradianceCoefficients": [\(coefficients)], "specularImageSize": 4, "specularImages": [[0, 1, 2, 3, 4, 5]]}]},
        "KHR_materials_variants": {"variants": [{"name": "Red"}, {"name": "Blue"}]}
      },
      "scene": 0, "scenes": [{"nodes": [0], "extensions": {"EXT_lights_image_based": {"light": 0}}}], "nodes": [{"mesh": 0}],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}}]}],
      "images": [\(images)],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
    #expect(result.sceneGraph.environment.map is PBREnvironment)
    #expect(result.variantNames == ["Red", "Blue"])
}

// #124: switching KHR_materials_variants on a loaded scene graph swaps the mesh's materials in place.
@Test
func gltfMaterialVariantsSwitchInPlace() throws {
    let buffer = [Float](arrayLiteral: -1, -1, 0, 1, -1, 0, 0, 1, 0).withUnsafeBytes { Data($0) }.base64EncodedString()
    let json = """
    {
      "asset": {"version": "2.0"},
      "extensionsUsed": ["KHR_materials_variants"],
      "extensions": {"KHR_materials_variants": {"variants": [{"name": "Red"}, {"name": "Blue"}]}},
      "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0}],
      "materials": [
        {"pbrMetallicRoughness": {"baseColorFactor": [1, 1, 1, 1]}},
        {"pbrMetallicRoughness": {"baseColorFactor": [1, 0, 0, 1]}},
        {"pbrMetallicRoughness": {"baseColorFactor": [0, 0, 1, 1]}}
      ],
      "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0, "extensions": {"KHR_materials_variants": {"mappings": [
        {"material": 1, "variants": [0]}, {"material": 2, "variants": [1]}
      ]}}}]}],
      "accessors": [{"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3", "min": [-1, -1, 0], "max": [1, 1, 0]}],
      "bufferViews": [{"buffer": 0, "byteLength": 36}],
      "buffers": [{"byteLength": 36, "uri": "data:application/octet-stream;base64,\(buffer)"}]
    }
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).gltf")
    try Data(json.utf8).write(to: url)
    let device = try #require(MTLCreateSystemDefaultDevice())
    let result = try GLTFAsset(url: url, device: device).makeSceneGraph(device: device)
    let node = try #require(result.nodes[0])
    #expect(try pbrMaterial(of: node).pbrMaterial.uniforms.baseColorFactor == [1, 1, 1, 1])
    try result.selectVariant(1)
    #expect(try pbrMaterial(of: node).pbrMaterial.uniforms.baseColorFactor == [0, 0, 1, 1])
    try result.selectVariant(0)
    #expect(try pbrMaterial(of: node).pbrMaterial.uniforms.baseColorFactor == [1, 0, 0, 1])
    try result.selectVariant(nil)
    #expect(try pbrMaterial(of: node).pbrMaterial.uniforms.baseColorFactor == [1, 1, 1, 1])
    #expect(throws: (any Error).self) { try result.selectVariant(5) }
}

// #197: ModelFile picks the loader by extension and returns one subtree named after the file.
@Test
func modelFileLoadsGLTFAndOBJ() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let gltfURL = directory.appendingPathComponent("Rig.gltf")
    try FileManager.default.copyItem(at: try makeSceneFile(), to: gltfURL)
    let gltf = try ModelFile.load(gltfURL, device: device)
    #expect(gltf.node.label == "Rig")
    #expect(gltf.node.parent == nil)
    #expect(gltf.node.children.map(\.label).contains("Mesh"))

    let objURL = directory.appendingPathComponent("Triangle.obj")
    try "v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n".write(to: objURL, atomically: true, encoding: .utf8)
    let obj = try ModelFile.load(objURL, device: device)
    #expect(obj.node.label == "Triangle")
    #expect(!SceneGraph(root: obj.node).meshEntries().isEmpty)

    #expect(throws: ModelFile.Failure.self) { try ModelFile.load(directory.appendingPathComponent("notes.txt"), device: device) }

    // #206: a .gltf with a sibling .bin needs its folder; data URIs and other formats do not.
    let external = directory.appendingPathComponent("External.gltf")
    try #"{"asset":{"version":"2.0"},"buffers":[{"uri":"data.bin","byteLength":4}]}"#.write(to: external, atomically: true, encoding: .utf8)
    let embedded = directory.appendingPathComponent("Embedded.gltf")
    try #"{"asset":{"version":"2.0"},"buffers":[{"uri":"data:application/octet-stream;base64,AAAAAA==","byteLength":4}]}"#.write(to: embedded, atomically: true, encoding: .utf8)
    #expect(try ModelFile.needsFolderAccess(external))
    // #213: the alert says how many files, counting each distinct one once.
    let twoFiles = directory.appendingPathComponent("TwoFiles.gltf")
    try #"{"asset":{"version":"2.0"},"buffers":[{"uri":"a.bin","byteLength":4}],"images":[{"uri":"color.png"},{"uri":"color.png"},{"uri":"data:image/png;base64,AA=="}]}"#.write(to: twoFiles, atomically: true, encoding: .utf8)
    #expect(try ModelFile.externalFiles(twoFiles) == ["a.bin", "color.png"])
    #expect(try ModelFile.externalFiles(embedded).isEmpty)
    #expect(try !ModelFile.needsFolderAccess(embedded))
    #expect(try !ModelFile.needsFolderAccess(objURL))
    #expect(ModelFile.isFile(external, inside: directory))
    #expect(!ModelFile.isFile(external, inside: directory.appendingPathComponent("Other")))
}
