import GeometryLite3D
import Metal
import MetalSprocketsGLTF
import MetalSprocketsPBR
import simd
import SwiftGLTF
import SwiftMesh

// A glTF scene as a scene graph. EXT_mesh_gpu_instancing copies become child nodes; KHR_node_visibility sets
// isVisible. KHR_animation_pointer channels for visibility, lights and cameras become property channels. Not
// supported: channels that target materials, and camera xmag and aspectRatio.
public struct GLTFSceneGraph {
    public var sceneGraph: SceneGraph
    public var animations: [SceneGraph.AnimationClip]
    // Indexed like the glTF document's nodes; nil for nodes outside the loaded scene.
    public var nodes: [SceneGraph.Node?]
    public var warnings: [String]
}

public extension GLTFAsset {
    func makeSceneGraph(device: MTLDevice) throws -> GLTFSceneGraph {
        try GLTFSceneGraphBuilder(asset: self, device: device).build()
    }
}

private struct ConvertedMesh {
    var mesh: MetalMesh
    var materials: [any MetalSprocketsSceneGraph.Material]
    var skinVertices: [SceneGraph.SkinVertex]
    var morphTargets: [SceneGraph.MorphTarget]
    var defaultWeights: [Float]
}

private struct GLTFSceneGraphBuilder {
    let asset: GLTFAsset
    let device: MTLDevice
    var document: Document { asset.container.document }

    func build() throws -> GLTFSceneGraph {
        var warnings: [String] = []
        let materials = materialsByPrimitive()
        let defaultMaterial = try PBRSceneMaterial(device: device)
        var meshes: [Int: ConvertedMesh?] = [:]
        func mesh(_ index: Int) throws -> ConvertedMesh? {
            if let cached = meshes[index] {
                return cached
            }
            let converted = try convertMesh(index, materials: materials, defaultMaterial: defaultMaterial)
            meshes[index] = converted
            return converted
        }

        let roots: [Int]
        if asset.sceneIndex < document.scenes.count {
            roots = document.scenes[asset.sceneIndex].nodes.map(\.index)
        } else {
            let children = Set(document.nodes.flatMap { $0.children.map(\.index) })
            roots = document.nodes.indices.filter { !children.contains($0) }
        }

        var nodes: [SceneGraph.Node?] = Array(repeating: nil, count: document.nodes.count)
        var skinNodes: [(node: SceneGraph.Node, skin: Int)] = []
        // Scene nodes holding each glTF light and camera, for pointer animations.
        var lightNodes: [Int: [SceneGraph.Node]] = [:]
        var cameraNodes: [Int: [SceneGraph.Node]] = [:]
        var path = Set<Int>()
        func visit(_ index: Int, parent: SceneGraph.Node) throws {
            guard document.nodes.indices.contains(index) else {
                throw GLTFSceneGraphError.invalidNode(index)
            }
            guard path.insert(index).inserted else {
                throw GLTFSceneGraphError.cycle(index)
            }
            defer { path.remove(index) }
            let source = document.nodes[index]
            let node = SceneGraph.Node(parent: parent, label: source.name)
            if let matrix = source.matrix, matrix != matrix_identity_float4x4 {
                node.transform = matrix
            } else {
                node.trs = Transform3D(
                    translation: source.translation ?? .zero,
                    rotation: source.rotation.map { simd_quatf(vector: $0) } ?? .identity,
                    scale: source.scale ?? .one
                )
            }
            nodes[index] = node

            // KHR_node_visibility hides the node's mesh and its descendants, like isVisible.
            node.isVisible = source.isVisible
            if let meshIndex = source.mesh?.index, let converted = try mesh(meshIndex) {
                let skin = converted.skinVertices.isEmpty ? nil : source.skin?.index
                // EXT_mesh_gpu_instancing: one child per copy. Skinned meshes follow their joints, so they get one.
                let instances = skin == nil ? try instanceTransforms(of: source) : nil
                let meshNodes = instances.map { transforms in
                    transforms.enumerated().map { index, transform in
                        SceneGraph.Node(parent: node, label: "\(source.name ?? "Instance") \(index)", transform: transform)
                    }
                } ?? [node]
                for meshNode in meshNodes {
                    meshNode.content = .mesh(converted.mesh, materials: converted.materials)
                    meshNode.morphTargets = converted.morphTargets
                    meshNode.morphWeights = source.weights ?? converted.defaultWeights
                }
                if let skin {
                    node.skinVertices = converted.skinVertices
                    skinNodes.append((node, skin))
                }
            }
            // A glTF node can hold a mesh, a camera and a light; the scene graph has one content per node.
            func addContent(_ content: SceneGraph.Node.Content) -> SceneGraph.Node {
                if case .empty = node.content {
                    node.content = content
                    return node
                }
                return SceneGraph.Node(parent: node, label: source.name, content: content)
            }
            if let cameraIndex = source.camera?.index {
                if let camera = camera(cameraIndex) {
                    cameraNodes[cameraIndex, default: []].append(addContent(.camera(camera)))
                } else {
                    warnings.append("Camera \(cameraIndex) skipped: it has no perspective or orthographic settings")
                }
            }
            if let light = source.punctualLight(in: document), let lightIndex = (try? source.extensionValue(KHRLightsPunctualNodeRef.self))??.light {
                lightNodes[lightIndex, default: []].append(addContent(.light(MetalSprocketsSceneGraph.Light(light))))
            }
            for child in source.children {
                try visit(child.index, parent: node)
            }
        }
        let root = SceneGraph.Node(label: document.scenes.indices.contains(asset.sceneIndex) ? document.scenes[asset.sceneIndex].name : nil)
        for index in roots {
            try visit(index, parent: root)
        }

        var skins: [Int: SceneGraph.Skin] = [:]
        for (node, index) in skinNodes {
            guard asset.skins.indices.contains(index) else {
                continue
            }
            if skins[index] == nil {
                let source = asset.skins[index]
                let joints = source.joints.compactMap { nodes.indices.contains($0) ? nodes[$0] : nil }
                guard joints.count == source.joints.count else {
                    warnings.append("Skin \(index) skipped: joints outside the scene")
                    continue
                }
                skins[index] = SceneGraph.Skin(joints: joints, inverseBindMatrices: source.inverseBindMatrices)
            }
            node.skin = skins[index]
        }

        func node(_ index: Int) -> [SceneGraph.Node] {
            nodes.indices.contains(index) ? nodes[index].map { [$0] } ?? [] : []
        }
        var skippedChannels = 0
        let animations = asset.animations.map { clip in
            SceneGraph.AnimationClip(name: clip.name, channels: clip.channels.flatMap { channel -> [SceneGraph.AnimationClip.Channel] in
                let targets: [(node: SceneGraph.Node, path: SceneGraph.AnimationClip.Path)]
                switch channel.target {
                case let .node(index, property):
                    let path: SceneGraph.AnimationClip.Path = switch property {
                    case .translation: .translation
                    case .rotation: .rotation
                    case .scale: .scale
                    case .weights: .weights
                    }
                    targets = node(index).map { ($0, path) }
                case let .visibility(index):
                    targets = node(index).map { ($0, .property(.visibility)) }
                case let .light(index, name):
                    targets = SceneGraph.AnimationClip.Property.gltfLight(name).map { property in lightNodes[index, default: []].map { ($0, .property(property)) } } ?? []
                case let .camera(index, name):
                    targets = SceneGraph.AnimationClip.Property.gltfCamera(name).map { property in cameraNodes[index, default: []].map { ($0, .property(property)) } } ?? []
                case .material:
                    targets = []
                }
                if targets.isEmpty {
                    skippedChannels += 1
                }
                let interpolation: SceneGraph.AnimationClip.Interpolation = switch channel.interpolation {
                case .step: .step
                case .linear: .linear
                case .cubicSpline: .cubicSpline
                }
                let sampler = SceneGraph.AnimationClip.Sampler(times: channel.times, values: channel.values, interpolation: interpolation)
                return targets.map { SceneGraph.AnimationClip.Channel(target: $0.node, path: $0.path, sampler: sampler) }
            })
        }
        if skippedChannels > 0 {
            warnings.append("\(skippedChannels) animation channels skipped: material channels, camera xmag/aspectRatio and missing targets are not supported")
        }

        return GLTFSceneGraph(sceneGraph: SceneGraph(root: root), animations: animations, nodes: nodes, warnings: asset.warnings + warnings)
    }

    // The asset resolves each primitive's material (including variants); instances carry the result.
    func materialsByPrimitive() -> [PBRModel.Primitive.Key: PBRMaterial] {
        var result: [PBRModel.Primitive.Key: PBRMaterial] = [:]
        for instance in asset.opaqueInstances + asset.blendedInstances {
            result[instance.primitive.key] = instance.material
        }
        return result
    }

    // One MetalMesh per glTF mesh, one submesh per primitive.
    func convertMesh(_ index: Int, materials: [PBRModel.Primitive.Key: PBRMaterial], defaultMaterial: PBRSceneMaterial) throws -> ConvertedMesh? {
        guard asset.meshes.indices.contains(index), !asset.meshes[index].isEmpty else {
            return nil
        }
        let primitives = asset.meshes[index]
        let isSkinned = primitives.contains(where: \.isSkinned)
        let targetCount = primitives.map { $0.mesh.morphTargets?.targets.count ?? 0 }.max() ?? 0
        var attributes: [MetalMesh.VertexAttributeData] = []
        var submeshes: [MetalMesh.SubmeshIndices] = []
        var skinVertices: [SceneGraph.SkinVertex] = []
        var morphTargets = Array(repeating: SceneGraph.MorphTarget(), count: targetCount)
        var defaultWeights: [Float] = []
        var vertexCount = 0
        for primitive in primitives {
            let mesh = primitive.mesh
            let data = mesh.vertexAttributeData()
            let joints = data.first { $0.semantic == .jointIndices(0) }
            let weights = data.first { $0.semantic == .jointWeights(0) }
            let vertexData = data.filter { $0.semantic != .jointIndices(0) && $0.semantic != .jointWeights(0) }
            if attributes.isEmpty {
                attributes = vertexData
            } else {
                guard vertexData.map(\.semantic) == attributes.map(\.semantic), vertexData.map(\.format) == attributes.map(\.format) else {
                    throw GLTFSceneGraphError.mixedVertexLayouts(index)
                }
                for (offset, attribute) in vertexData.enumerated() {
                    attributes[offset].bytes += attribute.bytes
                    attributes[offset].count += attribute.count
                }
            }
            let base = UInt32(vertexCount)
            submeshes.append(.init(label: mesh.label, indices: mesh.submeshes[0].indices.map { $0 + base }, primitiveType: primitive.primitiveType))

            if isSkinned {
                if let joints, let weights {
                    let jointValues: [SIMD4<UInt16>] = joints.format == .ushort4 ? floats(joints, as: SIMD4<UInt16>.self) : floats(joints, as: SIMD4<Float>.self).map { SIMD4<UInt16>($0) }
                    skinVertices += zip(jointValues, floats(weights, as: SIMD4<Float>.self)).map { SceneGraph.SkinVertex(joints: $0, weights: $1) }
                } else {
                    // Unskinned primitive in a skinned mesh: follows joint 0.
                    skinVertices += Array(repeating: SceneGraph.SkinVertex(joints: .zero, weights: [1, 0, 0, 0]), count: mesh.vertexCount)
                }
            }

            let sourceTargets = mesh.morphTargets?.targets ?? []
            for target in 0..<targetCount {
                let source = sourceTargets.indices.contains(target) ? sourceTargets[target] : nil
                morphTargets[target].positionDeltas += source?.positionOffsets ?? Array(repeating: .zero, count: mesh.vertexCount)
                morphTargets[target].normalDeltas += source?.normalOffsets ?? Array(repeating: .zero, count: mesh.vertexCount)
                morphTargets[target].tangentDeltas += source?.tangentOffsets ?? Array(repeating: .zero, count: mesh.vertexCount)
            }
            if defaultWeights.isEmpty, let weights = mesh.morphTargets?.defaultWeights {
                defaultWeights = weights
            }
            vertexCount += mesh.vertexCount
        }
        // Names from the common `extras.targetNames` convention (Blender and three.js write it).
        if case let .object(extras)? = document.meshes[index].extras, case let .array(names)? = extras["targetNames"] {
            for (target, name) in zip(morphTargets.indices, names) {
                if case let .string(name) = name {
                    morphTargets[target].name = name
                }
            }
        }
        let label = document.meshes[index].name
        let mesh = MetalMesh(device: device, attributes: attributes, submeshes: submeshes, label: label)
        let meshMaterials: [any MetalSprocketsSceneGraph.Material] = primitives.map { primitive in
            materials[primitive.key].map { PBRSceneMaterial($0) } ?? defaultMaterial
        }
        return ConvertedMesh(mesh: mesh, materials: meshMaterials, skinVertices: skinVertices, morphTargets: morphTargets, defaultWeights: defaultWeights)
    }

    // EXT_mesh_gpu_instancing copies, relative to the node; nil when the node does not use it.
    func instanceTransforms(of node: SwiftGLTF.Node) throws -> [simd_float4x4]? {
        guard let instancing = try? node.extensionValue(EXTMeshGPUInstancing.self) else {
            return nil
        }
        func values(_ name: String, components: Int) throws -> [Float]? {
            guard let index = instancing.attributes[name] else {
                return nil
            }
            guard document.accessors.indices.contains(index), document.accessors[index].type.componentCount == components else {
                throw GLTFSceneGraphError.invalidInstancing(name)
            }
            return try asset.container.floatComponents(for: document.accessors[index])
        }
        let translations = try values("TRANSLATION", components: 3)
        let rotations = try values("ROTATION", components: 4)
        let scales = try values("SCALE", components: 3)
        let counts = [translations.map { $0.count / 3 }, rotations.map { $0.count / 4 }, scales.map { $0.count / 3 }].compactMap(\.self)
        guard let count = counts.first else {
            return nil
        }
        guard counts.allSatisfy({ $0 == count }) else {
            throw GLTFSceneGraphError.invalidInstancing("attribute counts differ")
        }
        return (0..<count).map { index in
            Transform3D(
                translation: translations.map { SIMD3($0[index * 3], $0[index * 3 + 1], $0[index * 3 + 2]) } ?? .zero,
                rotation: rotations.map { simd_normalize(simd_quatf(ix: $0[index * 4], iy: $0[index * 4 + 1], iz: $0[index * 4 + 2], r: $0[index * 4 + 3])) } ?? .identity,
                scale: scales.map { SIMD3($0[index * 3], $0[index * 3 + 1], $0[index * 3 + 2]) } ?? .one
            ).matrix
        }
    }

    // Orthographic cameras keep ymag as the half height; the width follows the view's aspect ratio, so xmag is
    // ignored, as in SceneKit.
    func camera(_ index: Int) -> MetalSprocketsSceneGraph.Camera? {
        guard document.cameras.indices.contains(index) else {
            return nil
        }
        let source = document.cameras[index]
        if let perspective = source.perspective {
            let far = perspective.zfar ?? 1000
            return MetalSprocketsSceneGraph.Camera(projection: PerspectiveProjection(verticalAngleOfView: .radians(perspective.yfov), depthMode: .standard(zClip: perspective.znear ... max(far, perspective.znear))))
        }
        if let orthographic = source.orthographic {
            return MetalSprocketsSceneGraph.Camera(projection: OrthographicProjection(halfHeight: orthographic.ymag, depthMode: .standard(zClip: orthographic.znear ... max(orthographic.zfar, orthographic.znear))))
        }
        return nil
    }
}

private func floats<T>(_ attribute: MetalMesh.VertexAttributeData, as type: T.Type) -> [T] {
    let size = attribute.format.size
    return attribute.bytes.withUnsafeBytes { bytes in
        (0..<attribute.count).map { bytes.loadUnaligned(fromByteOffset: $0 * size, as: T.self) }
    }
}

extension SceneGraph.AnimationClip.Property {
    // A KHR_lights_punctual light property, named below `/extensions/KHR_lights_punctual/lights/N/`.
    static func gltfLight(_ name: String) -> Self? {
        switch name {
        case "color": .lightColor
        case "intensity": .lightIntensity
        case "range": .lightRange
        case "spot/innerConeAngle": .lightInnerConeAngle
        case "spot/outerConeAngle": .lightOuterConeAngle
        default: nil
        }
    }

    // A camera property, named below `/cameras/N/`. The width follows the view, so xmag and aspectRatio are not
    // supported.
    static func gltfCamera(_ name: String) -> Self? {
        switch name {
        case "perspective/yfov": .cameraVerticalFieldOfView
        case "orthographic/ymag": .cameraHalfHeight
        case "perspective/znear", "orthographic/znear": .cameraNear
        case "perspective/zfar", "orthographic/zfar": .cameraFar
        default: nil
        }
    }
}

enum GLTFSceneGraphError: Error {
    case invalidNode(Int)
    case cycle(Int)
    case mixedVertexLayouts(Int)
    case invalidInstancing(String)
}

extension MetalSprocketsSceneGraph.Light {
    init(_ light: SwiftGLTF.Light) {
        switch light.type {
        case .directional:
            self.init(type: .directional, color: light.color, intensity: light.intensity)
        case .point:
            self.init(type: .point, color: light.color, intensity: light.intensity)
        case .spot:
            self = .spot(color: light.color, intensity: light.intensity, innerConeAngle: light.spot?.innerConeAngle ?? 0, outerConeAngle: light.spot?.outerConeAngle ?? .pi / 4)
        }
        if let range = light.range {
            self.range = range
        }
    }
}
