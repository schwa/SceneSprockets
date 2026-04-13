import GeometryLite3D
import Metal
import MetalSprocketsAddOnsShaders
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphPBR
import simd
import SwiftGLTF
import SwiftMesh

// A glTF scene as a scene graph. Not supported: EXT_mesh_gpu_instancing copies, KHR_node_visibility,
// orthographic cameras, and animation channels that target materials, lights, cameras or visibility.
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
                node.trs = SceneGraph.TRS(
                    translation: source.translation ?? .zero,
                    rotation: source.rotation.map { simd_quatf(vector: $0) } ?? simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                    scale: source.scale ?? .one
                )
            }
            nodes[index] = node

            if let meshIndex = source.mesh?.index, let converted = try mesh(meshIndex) {
                node.content = .mesh(converted.mesh, materials: converted.materials)
                node.morphTargets = converted.morphTargets
                node.morphWeights = source.weights ?? converted.defaultWeights
                if let skin = source.skin?.index, !converted.skinVertices.isEmpty {
                    node.skinVertices = converted.skinVertices
                    skinNodes.append((node, skin))
                }
            }
            // A glTF node can hold a mesh, a camera and a light; the scene graph has one content per node.
            var extras: [SceneGraph.Node.Content] = []
            if let cameraIndex = source.camera?.index {
                if let camera = camera(cameraIndex) {
                    extras.append(.camera(camera))
                } else {
                    warnings.append("Camera \(cameraIndex) skipped: only perspective cameras are supported")
                }
            }
            if let light = source.punctualLight(in: document) {
                extras.append(.light(MetalSprocketsAddOnsShaders.Light(light)))
            }
            for content in extras {
                if case .empty = node.content {
                    node.content = content
                } else {
                    _ = SceneGraph.Node(parent: node, label: source.name, content: content)
                }
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

        let animations = asset.animations.map { clip in
            SceneGraph.AnimationClip(name: clip.name, channels: clip.channels.compactMap { channel in
                guard case let .node(index, property) = channel.target, nodes.indices.contains(index), let node = nodes[index] else {
                    return nil
                }
                let path: SceneGraph.AnimationClip.Path = switch property {
                case .translation: .translation
                case .rotation: .rotation
                case .scale: .scale
                case .weights: .weights
                }
                let interpolation: SceneGraph.AnimationClip.Interpolation = switch channel.interpolation {
                case .step: .step
                case .linear: .linear
                case .cubicSpline: .cubicSpline
                }
                return SceneGraph.AnimationClip.Channel(target: node, path: path, sampler: .init(times: channel.times, values: channel.values, interpolation: interpolation))
            })
        }
        let skippedChannels = asset.animations.flatMap(\.channels).filter { if case .node = $0.target { false } else { true } }.count
        if skippedChannels > 0 {
            warnings.append("\(skippedChannels) animation channels skipped: only node channels are supported")
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
        let label = document.meshes[index].name
        let mesh = MetalMesh(device: device, attributes: attributes, submeshes: submeshes, label: label)
        let meshMaterials: [any MetalSprocketsSceneGraph.Material] = primitives.map { primitive in
            materials[primitive.key].map { PBRSceneMaterial($0) } ?? defaultMaterial
        }
        return ConvertedMesh(mesh: mesh, materials: meshMaterials, skinVertices: skinVertices, morphTargets: morphTargets, defaultWeights: defaultWeights)
    }

    func camera(_ index: Int) -> MetalSprocketsSceneGraph.Camera? {
        guard document.cameras.indices.contains(index), let perspective = document.cameras[index].perspective else {
            return nil
        }
        let far = perspective.zfar ?? 1000
        return MetalSprocketsSceneGraph.Camera(projection: PerspectiveProjection(verticalAngleOfView: .radians(perspective.yfov), depthMode: .standard(zClip: perspective.znear ... max(far, perspective.znear))))
    }
}

private func floats<T>(_ attribute: MetalMesh.VertexAttributeData, as type: T.Type) -> [T] {
    let size = attribute.format.size
    return attribute.bytes.withUnsafeBytes { bytes in
        (0..<attribute.count).map { bytes.loadUnaligned(fromByteOffset: $0 * size, as: T.self) }
    }
}

enum GLTFSceneGraphError: Error {
    case invalidNode(Int)
    case cycle(Int)
    case mixedVertexLayouts(Int)
}

extension MetalSprocketsAddOnsShaders.Light {
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
