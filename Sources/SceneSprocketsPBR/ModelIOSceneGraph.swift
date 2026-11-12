import GeometryLite3D
import Metal
import MetalKit
import MetalSprocketsPBR
import MetalSupport
import ModelIO
import SceneSprockets
import SceneSprocketsBlinnPhong
import simd
import SwiftMesh

// A Model I/O asset converted to a scene graph, with its object hierarchy; ModelFile.load is the public entry point
// (#371).
//
// Model I/O reads OBJ, PLY, STL, ABC, USD and more. The conversion keeps meshes, materials, cameras, lights and
// keyframed transforms, including orthographic cameras, and skins with their joint animation. It does not import
// blend shapes: Model I/O does not expose them.
struct ModelIOImport {
    var sceneGraph: SceneGraph
    // The keyframed transforms, sampled at their key times; empty if nothing is animated.
    var animations: [SceneGraph.AnimationClip]
    var warnings: [String]

    /// Loads a file with Model I/O and converts it.
    ///
    /// - Parameters:
    ///   - url: The file to load.
    ///   - materials: The kind of scene material to make.
    /// - Throws: An error if the file is empty or the conversion fails.
    init(url: URL, materials: ModelFile.MaterialKind = .pbr) throws {
        let allocator = MTKMeshBufferAllocator(device: _MTLCreateSystemDefaultDevice())
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        // swiftlint:disable:next empty_count - MDLAsset has no isEmpty
        guard asset.count > 0 else {
            throw ModelIOSceneGraphError.emptyAsset(url)
        }
        try self.init(asset: asset, materials: materials, label: url.deletingPathExtension().lastPathComponent)
    }

    /// Converts an asset that is already loaded.
    ///
    /// - Parameters:
    ///   - asset: The asset to convert.
    ///   - materials: The kind of scene material to make.
    ///   - label: The label of the root node.
    /// - Throws: An error if the conversion fails.
    init(asset: MDLAsset, materials: ModelFile.MaterialKind = .pbr, label: String? = nil) throws {
        var converter = try ModelIOConverter(materialKind: materials)
        let root = SceneGraph.Node(label: label)
        for index in 0..<asset.count {
            try converter.visit(asset.object(at: index), parent: root)
        }
        converter.resolveSkins()
        sceneGraph = SceneGraph(root: root)
        animations = converter.channels.isEmpty ? [] : [SceneGraph.AnimationClip(name: label, channels: converter.channels)]
        warnings = converter.warnings
    }
}

enum ModelIOSceneGraphError: Error {
    case emptyAsset(URL)
}

private struct ModelIOConverter {
    let device: MTLDevice
    let materialKind: ModelFile.MaterialKind
    let textureLoader: MTKTextureLoader
    let samplerDescriptor: MTLSamplerDescriptor
    let placeholder: PBRMaterial.Binding
    var channels: [SceneGraph.AnimationClip.Channel] = []
    var warnings: [String] = []
    var materialCache: [ObjectIdentifier: any SceneMaterial] = [:]
    var textureCache: [ObjectIdentifier: MTLTexture] = [:]
    // Joint nodes per MDLSkeleton, in its jointPaths order.
    var skeletonJoints: [ObjectIdentifier: [SceneGraph.Node]] = [:]
    // Skinned meshes, resolved after the walk because a mesh can come before its skeleton.
    var pendingSkins: [(node: SceneGraph.Node, bind: MDLAnimationBindComponent, skeleton: MDLSkeleton)] = []

    init(materialKind: ModelFile.MaterialKind) throws {
        device = _MTLCreateSystemDefaultDevice()
        self.materialKind = materialKind
        textureLoader = MTKTextureLoader(device: device)
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        samplerDescriptor = descriptor
        placeholder = try PBRMaterial.placeholderBinding(device: device)
    }

    func binding(_ texture: MTLTexture) throws -> PBRMaterial.Binding {
        try PBRMaterial.Binding(texture: texture, samplerDescriptor: samplerDescriptor, device: device)
    }

    mutating func visit(_ object: MDLObject, parent: SceneGraph.Node) throws {
        let node = parent.addChild(SceneGraph.Node(label: object.name.isEmpty ? nil : object.name))
        if let transform = object.transform {
            node.transform = Transform3D(storing: transform.matrix)
            sampleAnimation(transform, node: node)
        }
        switch object {
        case let mesh as MDLMesh:
            let bind = mesh.componentConforming(to: MDLComponent.self) as? MDLAnimationBindComponent
            if let (metalMesh, materials, skinVertices) = try convert(mesh) {
                node.content = .mesh(metalMesh, materials: materials)
                if let bind, let skeleton = bind.skeleton {
                    if let skinVertices {
                        node.skinVertices = skinVertices
                        pendingSkins.append((node, bind, skeleton))
                    } else {
                        warnings.append("Mesh \(object.name): skin skipped, no joint indices and weights")
                    }
                }
            }
        case let skeleton as MDLSkeleton:
            makeJoints(skeleton, parent: node)
        case let camera as MDLCamera:
            let far = max(camera.farVisibilityDistance, camera.nearVisibilityDistance)
            let zClip = camera.nearVisibilityDistance ... far
            switch camera.projection {
            case .perspective:
                node.content = .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(camera.fieldOfView), depthMode: .standard(zClip: zClip))))
            case .orthographic:
                // Model I/O passes USD's verticalAperture through; for orthographic cameras USD measures it in tenths
                // of a scene unit (#302).
                node.content = .camera(Camera(projection: OrthographicProjection(halfHeight: camera.sensorVerticalAperture / 20, depthMode: .standard(zClip: zClip))))
            @unknown default:
                warnings.append("Camera \(object.name) skipped: unsupported projection \(camera.projection.rawValue)")
            }
        case let light as MDLLight:
            if let converted = convert(light) {
                node.content = .light(converted)
            } else {
                warnings.append("Light \(object.name) skipped: unsupported type \(light.lightType.rawValue)")
            }
        default:
            break
        }
        for child in object.children.objects {
            try visit(child, parent: node)
        }
    }

    // Joint nodes under the skeleton's node, posed with the rest transforms. A joint path's parent is the path
    // without its last component, as in USD.
    mutating func makeJoints(_ skeleton: MDLSkeleton, parent: SceneGraph.Node) {
        let rest = skeleton.jointRestTransforms.float4x4Array
        var nodesByPath: [String: SceneGraph.Node] = [:]
        var joints: [SceneGraph.Node] = []
        for (index, path) in skeleton.jointPaths.enumerated() {
            let components = path.split(separator: "/")
            let parentPath = components.dropLast().joined(separator: "/")
            let jointParent = nodesByPath[parentPath] ?? parent
            let joint = jointParent.addChild(SceneGraph.Node(label: components.last.map(String.init)))
            if rest.indices.contains(index) {
                joint.transform = Transform3D(storing: rest[index])
            }
            nodesByPath[path] = joint
            joints.append(joint)
        }
        skeletonJoints[ObjectIdentifier(skeleton)] = joints
        if let animation = (skeleton.componentConforming(to: MDLComponent.self) as? MDLAnimationBindComponent)?.jointAnimation as? MDLPackedJointAnimation {
            sampleJointAnimation(animation, nodesByPath: nodesByPath)
        }
    }

    // Each animated joint gets TRS channels sampled at the union of the key times.
    mutating func sampleJointAnimation(_ animation: MDLPackedJointAnimation, nodesByPath: [String: SceneGraph.Node]) {
        let keyTimes = Set(animation.translations.times + animation.rotations.times + animation.scales.times).sorted()
        guard keyTimes.count > 1 else {
            return
        }
        let translations = keyTimes.map { animation.translations.float3Array(atTime: $0) }
        let rotations = keyTimes.map { animation.rotations.floatQuaternionArray(atTime: $0) }
        let scales = keyTimes.map { animation.scales.float3Array(atTime: $0) }
        let times = keyTimes.map { Float($0) }
        for (index, path) in animation.jointPaths.enumerated() {
            guard let joint = nodesByPath[path] else {
                warnings.append("Joint animation for \(path) skipped: no such joint")
                continue
            }
            var channelValues: [(SceneGraph.AnimationClip.Path, [Float])] = []
            if translations.allSatisfy({ $0.indices.contains(index) }) {
                channelValues.append((.translation, translations.flatMap { [$0[index].x, $0[index].y, $0[index].z] }))
            }
            if rotations.allSatisfy({ $0.indices.contains(index) }) {
                channelValues.append((.rotation, rotations.flatMap { [$0[index].vector.x, $0[index].vector.y, $0[index].vector.z, $0[index].vector.w] }))
            }
            if scales.allSatisfy({ $0.indices.contains(index) }) {
                channelValues.append((.scale, scales.flatMap { [$0[index].x, $0[index].y, $0[index].z] }))
            }
            channels += channelValues.map { .init(target: joint, path: $0.0, sampler: .init(times: times, values: $0.1, interpolation: .linear)) }
        }
    }

    // Up to four influences per vertex, the largest weights, normalized.
    // swiftlint:disable:next discouraged_optional_collection - nil means the mesh has no joint attributes
    func skinVertices(_ mesh: MDLMesh) -> [SceneGraph.SkinVertex]? {
        guard let indices = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeJointIndices),
              let weights = mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeJointWeights) else {
            return nil
        }
        let indexCount = Int(indices.format.rawValue & 0xFFFF)
        let weightCount = Int(weights.format.rawValue & 0xFFFF)
        guard indexCount > 0, indexCount == weightCount else {
            return nil
        }
        var result: [SceneGraph.SkinVertex] = []
        result.reserveCapacity(mesh.vertexCount)
        for vertex in 0..<mesh.vertexCount {
            let indexPointer = UnsafeRawPointer(indices.dataStart).advanced(by: vertex * indices.stride)
            let weightPointer = UnsafeRawPointer(weights.dataStart).advanced(by: vertex * weights.stride)
            var influences: [(joint: UInt16, weight: Float)] = []
            for slot in 0..<indexCount {
                guard let joint = Self.integer(indexPointer, slot: slot, format: indices.format), let weight = Self.float(weightPointer, slot: slot, format: weights.format) else {
                    return nil
                }
                influences.append((UInt16(clamping: joint), weight))
            }
            let strongest = influences.sorted { $0.weight > $1.weight }.prefix(4)
            var joints = SIMD4<UInt16>.zero
            var values = SIMD4<Float>.zero
            for (slot, influence) in strongest.enumerated() {
                joints[slot] = influence.joint
                values[slot] = influence.weight
            }
            let total = values.sum()
            result.append(SceneGraph.SkinVertex(joints: joints, weights: total > 0 ? values / total : [1, 0, 0, 0]))
        }
        return result
    }

    static func integer(_ pointer: UnsafeRawPointer, slot: Int, format: MDLVertexFormat) -> Int? {
        switch format.rawValue & 0xFFFF0000 {
        case MDLVertexFormat.uCharBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot, as: UInt8.self))
        case MDLVertexFormat.charBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot, as: Int8.self))
        case MDLVertexFormat.uShortBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot * 2, as: UInt16.self))
        case MDLVertexFormat.shortBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot * 2, as: Int16.self))
        case MDLVertexFormat.uIntBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot * 4, as: UInt32.self))
        case MDLVertexFormat.intBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot * 4, as: Int32.self))
        case MDLVertexFormat.floatBits.rawValue: Int(pointer.loadUnaligned(fromByteOffset: slot * 4, as: Float.self))
        default: nil
        }
    }

    static func float(_ pointer: UnsafeRawPointer, slot: Int, format: MDLVertexFormat) -> Float? {
        switch format.rawValue & 0xFFFF0000 {
        case MDLVertexFormat.floatBits.rawValue: pointer.loadUnaligned(fromByteOffset: slot * 4, as: Float.self)
        case MDLVertexFormat.halfBits.rawValue: Float(pointer.loadUnaligned(fromByteOffset: slot * 2, as: Float16.self))
        case MDLVertexFormat.uCharNormalizedBits.rawValue: Float(pointer.loadUnaligned(fromByteOffset: slot, as: UInt8.self)) / 255
        case MDLVertexFormat.uShortNormalizedBits.rawValue: Float(pointer.loadUnaligned(fromByteOffset: slot * 2, as: UInt16.self)) / 65_535
        default: nil
        }
    }

    // Inverse bind matrices map the mesh's bind pose into each joint's space: inverse(bind) * geometryBindTransform.
    mutating func resolveSkins() {
        for (node, bind, skeleton) in pendingSkins {
            guard let skeletonJoints = skeletonJoints[ObjectIdentifier(skeleton)] else {
                warnings.append("Skin on \(node.label ?? "mesh") skipped: its skeleton is not in the asset's hierarchy")
                continue
            }
            let bindTransforms = skeleton.jointBindTransforms.float4x4Array
            var jointIndices = Array(skeletonJoints.indices)
            if let paths = bind.jointPaths, !paths.isEmpty {
                let lookup = Dictionary(skeleton.jointPaths.enumerated().map { ($1, $0) }) { first, _ in first }
                let mapped = paths.compactMap { lookup[$0] }
                guard mapped.count == paths.count else {
                    warnings.append("Skin on \(node.label ?? "mesh") skipped: joints missing from its skeleton")
                    node.skinVertices = []
                    continue
                }
                jointIndices = mapped
            }
            guard jointIndices.allSatisfy({ bindTransforms.indices.contains($0) }) else {
                warnings.append("Skin on \(node.label ?? "mesh") skipped: missing bind transforms")
                node.skinVertices = []
                continue
            }
            let double = bind.geometryBindTransform
            let geometryBind = simd_float4x4(columns: (SIMD4<Float>(double.columns.0), SIMD4<Float>(double.columns.1), SIMD4<Float>(double.columns.2), SIMD4<Float>(double.columns.3)))
            node.skin = SceneGraph.Skin(
                joints: jointIndices.map { skeletonJoints[$0] },
                inverseBindMatrices: jointIndices.map { bindTransforms[$0].inverse * geometryBind }
            )
        }
    }

    // Keyframed transforms become one TRS channel set, sampled at the key times with linear interpolation.
    mutating func sampleAnimation(_ transform: MDLTransformComponent, node: SceneGraph.Node) {
        let times = transform.keyTimes.map { Float($0.doubleValue) }
        guard times.count > 1 else {
            return
        }
        let samples = times.map { Transform3D(nearestTo: transform.localTransform?(atTime: TimeInterval($0)) ?? transform.matrix) }
        let translations = samples.flatMap { [$0.translation.x, $0.translation.y, $0.translation.z] }
        let rotations = samples.flatMap { [$0.rotation.quaternion.vector.x, $0.rotation.quaternion.vector.y, $0.rotation.quaternion.vector.z, $0.rotation.quaternion.vector.w] }
        let scales = samples.flatMap { [$0.scale.x, $0.scale.y, $0.scale.z] }
        channels += [
            .init(target: node, path: .translation, sampler: .init(times: times, values: translations, interpolation: .linear)),
            .init(target: node, path: .rotation, sampler: .init(times: times, values: rotations, interpolation: .linear)),
            .init(target: node, path: .scale, sampler: .init(times: times, values: scales, interpolation: .linear))
        ]
    }

    // Repacks to position, normal and texture coordinates (the layout both renderers read), one buffer.
    // Also returns the skin vertices, if the mesh has joint attributes.
    // swiftlint:disable:next large_tuple discouraged_optional_collection
    mutating func convert(_ mesh: MDLMesh) throws -> (MetalMesh, [any SceneMaterial], [SceneGraph.SkinVertex]?)? {
        guard mesh.vertexCount > 0, let submeshes = mesh.submeshes as? [MDLSubmesh], !submeshes.isEmpty else {
            return nil
        }
        if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
            mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
        }
        // After addNormals, which can split vertices; before the repack, which drops the joint attributes.
        let skinVertices = skinVertices(mesh)
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
        mesh.vertexDescriptor = descriptor

        let mtkMesh = try MTKMesh(mesh: mesh, device: device)
        let metalMesh = MetalMesh(mtkMesh: mtkMesh)
        let materials = try submeshes.map { try material($0.material) }
        return (metalMesh, materials, skinVertices)
    }

    mutating func material(_ source: MDLMaterial?) throws -> any SceneMaterial {
        let key = source.map { ObjectIdentifier($0) }
        if let key, let cached = materialCache[key] {
            return cached
        }
        let baseColor = color(source?.property(with: .baseColor)) ?? [0.8, 0.8, 0.8, 1]
        let metallic = scalar(source?.property(with: .metallic)) ?? 0
        let roughness = scalar(source?.property(with: .roughness)) ?? 0.5
        let emission = color(source?.property(with: .emission)).map { SIMD3($0.x, $0.y, $0.z) } ?? .zero
        let baseColorTexture = texture(source?.property(with: .baseColor), sRGB: true)
        let emissionTexture = texture(source?.property(with: .emission), sRGB: true)

        let result: any SceneMaterial
        switch materialKind {
        case .pbr:
            var uniforms = PBRMaterialUniforms.defaults(baseColor: baseColor, metallic: metallic, roughness: roughness)
            uniforms.emissiveFactor = emission
            var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
            if let baseColorTexture {
                bindings[Int(kPBRTextureBaseColor.rawValue)] = try binding(baseColorTexture)
                uniforms.baseColor.enabled = 1
            }
            if let emissionTexture {
                bindings[Int(kPBRTextureEmissive.rawValue)] = try binding(emissionTexture)
                uniforms.emissive.enabled = 1
                if emission == .zero {
                    uniforms.emissiveFactor = [1, 1, 1]
                }
            }
            if let normalTexture = texture(source?.property(with: .tangentSpaceNormal), sRGB: false) {
                bindings[Int(kPBRTextureNormal.rawValue)] = try binding(normalTexture)
                uniforms.normal.enabled = 1
            }
            if let occlusionTexture = texture(source?.property(with: .ambientOcclusion), sRGB: false) {
                bindings[Int(kPBRTextureOcclusion.rawValue)] = try binding(occlusionTexture)
                uniforms.occlusion.enabled = 1
            }
            // Model I/O has separate metallic and roughness maps; PBR reads roughness from green and metallic from
            // blue of one texture. Their factors multiply the texture, so a mapped value's factor is 1.
            let metallicMap = textureSource(source?.property(with: .metallic))
            let roughnessMap = textureSource(source?.property(with: .roughness))
            if metallicMap != nil || roughnessMap != nil, let packed = packMetallicRoughness(metallic: metallicMap, roughness: roughnessMap) {
                bindings[Int(kPBRTextureMetallicRoughness.rawValue)] = try binding(packed)
                uniforms.metallicRoughness.enabled = 1
                uniforms.metallicFactor = metallicMap == nil ? metallic : 1
                uniforms.roughnessFactor = roughnessMap == nil ? roughness : 1
            }
            if baseColor.w < 1 {
                uniforms.alphaMode = .blend
            }
            result = PBRSceneMaterial(try PBRMaterial(name: source?.name, uniforms: uniforms, textureBindings: bindings, device: device))
        case .blinnPhong:
            let diffuse: BlinnPhongSceneMaterial.Source = baseColorTexture.map { .texture($0, sampler: samplerDescriptor) } ?? .color(SIMD3(baseColor.x, baseColor.y, baseColor.z))
            let specular = color(source?.property(with: .specular)).map { SIMD3($0.x, $0.y, $0.z) } ?? [0.2, 0.2, 0.2]
            let shininess = scalar(source?.property(with: .specularExponent)) ?? 32
            result = BlinnPhongSceneMaterial(ambient: .color(SIMD3(baseColor.x, baseColor.y, baseColor.z) * 0.1), diffuse: diffuse, specular: .color(specular), shininess: shininess)
        }
        if let key {
            materialCache[key] = result
        }
        return result
    }

    func color(_ property: MDLMaterialProperty?) -> SIMD4<Float>? {
        guard let property else {
            return nil
        }
        switch property.type {
        case .float3:
            return SIMD4(property.float3Value, 1)
        case .float4:
            return property.float4Value
        case .float:
            let value = property.floatValue
            return SIMD4(value, value, value, 1)
        case .color:
            // swiftlint:disable:next force_unwrapping - the linear sRGB color space always exists
            guard let color = property.color, let components = color.converted(to: CGColorSpace(name: CGColorSpace.linearSRGB)!, intent: .defaultIntent, options: nil)?.components, components.count >= 3 else {
                return nil
            }
            return SIMD4(Float(components[0]), Float(components[1]), Float(components[2]), components.count > 3 ? Float(components[3]) : 1)
        default:
            return nil
        }
    }

    func scalar(_ property: MDLMaterialProperty?) -> Float? {
        guard let property, property.type == .float else {
            return nil
        }
        return property.floatValue
    }

    func textureSource(_ property: MDLMaterialProperty?) -> MDLTexture? {
        guard let property, property.type == .texture else {
            return nil
        }
        return property.textureSamplerValue?.texture
    }

    // An RGBA8 texture with roughness in green and metallic in blue (255 where a map is missing), at the larger
    // map's size. Maps are read from their first channel, sampled nearest.
    mutating func packMetallicRoughness(metallic: MDLTexture?, roughness: MDLTexture?) -> MTLTexture? {
        let maps = [metallic, roughness].compactMap(\.self)
        let width = maps.map { Int($0.dimensions.x) }.max() ?? 0
        let height = maps.map { Int($0.dimensions.y) }.max() ?? 0
        guard width > 0, height > 0 else {
            return nil
        }
        // swiftlint:disable:next discouraged_optional_collection - nil means no usable map
        func channel(_ map: MDLTexture?) -> [UInt8]? {
            guard let map else {
                return Array(repeating: 255, count: width * height)
            }
            guard let values = firstChannel(of: map) else {
                warnings.append("Texture \(map.name) skipped: unsupported texel format")
                return nil
            }
            let mapWidth = Int(map.dimensions.x)
            let mapHeight = Int(map.dimensions.y)
            return (0..<(width * height)).map { index in
                let x = index % width * mapWidth / width
                let y = index / width * mapHeight / height
                return values[y * mapWidth + x]
            }
        }
        guard let metallicValues = channel(metallic), let roughnessValues = channel(roughness) else {
            return nil
        }
        let pixels = (0..<(width * height)).flatMap { [UInt8(255), roughnessValues[$0], metallicValues[$0], UInt8(255)] }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "Metallic Roughness"
        texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0, withBytes: pixels, bytesPerRow: width * 4)
        return texture
    }

    // First channel of each texel, as 0...255, rows top first. Nil for formats other than 8-bit, 16-bit or float.
    // swiftlint:disable:next discouraged_optional_collection - nil means an unsupported format
    func firstChannel(of map: MDLTexture) -> [UInt8]? {
        guard let data = map.texelDataWithTopLeftOrigin() else {
            return nil
        }
        let count = Int(map.dimensions.x) * Int(map.dimensions.y)
        let channels = Int(map.channelCount)
        // swiftlint:disable:next discouraged_optional_collection - nil means an unsupported format
        return data.withUnsafeBytes { bytes -> [UInt8]? in
            switch map.channelEncoding {
            case .uInt8:
                guard bytes.count >= count * channels else {
                    return nil
                }
                return (0..<count).map { bytes[$0 * channels] }
            case .uInt16:
                guard bytes.count >= count * channels * 2 else {
                    return nil
                }
                let values = bytes.bindMemory(to: UInt16.self)
                return (0..<count).map { UInt8(values[$0 * channels] >> 8) }
            case .float32:
                guard bytes.count >= count * channels * 4 else {
                    return nil
                }
                let values = bytes.bindMemory(to: Float.self)
                return (0..<count).map { UInt8(min(max(values[$0 * channels], 0), 1) * 255) }
            default:
                return nil
            }
        }
    }

    mutating func texture(_ property: MDLMaterialProperty?, sRGB: Bool) -> MTLTexture? {
        guard let property, property.type == .texture, let source = property.textureSamplerValue?.texture else {
            return nil
        }
        let key = ObjectIdentifier(source)
        if let cached = textureCache[key] {
            return cached
        }
        do {
            let texture = try textureLoader.newTexture(texture: source, options: [
                .SRGB: sRGB,
                .generateMipmaps: true,
                .textureUsage: MTLTextureUsage.shaderRead.rawValue,
                .textureStorageMode: MTLStorageMode.private.rawValue
            ])
            textureCache[key] = texture
            return texture
        } catch {
            warnings.append("Texture \(source.name) skipped: \(error)")
            return nil
        }
    }

    func convert(_ light: MDLLight) -> Light? {
        let physical = light as? MDLPhysicallyPlausibleLight
        let color: SIMD3<Float> = physical?.color.flatMap { color in
            // swiftlint:disable:next force_unwrapping - the linear sRGB color space always exists
            guard let linear = color.converted(to: CGColorSpace(name: CGColorSpace.linearSRGB)!, intent: .defaultIntent, options: nil), let components = linear.components, components.count >= 3 else {
                return nil
            }
            return SIMD3(Float(components[0]), Float(components[1]), Float(components[2]))
        } ?? [1, 1, 1]
        let intensity = physical.map { $0.lumens > 0 ? $0.lumens : 1 } ?? 1
        var result: Light
        switch light.lightType {
        case .directional:
            result = Light(type: .directional, color: color, intensity: intensity)
        case .point:
            result = Light(type: .point, color: color, intensity: intensity)
        case .spot:
            let inner = (physical?.innerConeAngle ?? 22.5) * .pi / 180
            let outer = (physical?.outerConeAngle ?? 30) * .pi / 180
            result = .spot(color: color, intensity: intensity, innerConeAngle: inner / 2, outerConeAngle: outer / 2)
        default:
            return nil
        }
        if let physical, physical.attenuationEndDistance > 0 {
            result.range = physical.attenuationEndDistance
        }
        return result
    }
}
