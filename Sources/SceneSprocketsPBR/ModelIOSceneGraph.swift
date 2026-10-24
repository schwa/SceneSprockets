import GeometryLite3D
import Metal
import MetalKit
import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import ModelIO
import simd
import SwiftMesh

// An MDLAsset (OBJ, PLY, STL, ABC, USD, ...) as a scene graph, keeping its object hierarchy.
// Not imported: skins and blend shapes (see #31).
public struct ModelIOSceneGraph {
    public enum MaterialKind: Sendable {
        case pbr
        case blinnPhong
    }

    public var sceneGraph: SceneGraph
    // Keyframed transforms, sampled at their key times. Nil when nothing is animated.
    public var animation: SceneGraph.AnimationClip?
    public var warnings: [String]

    public init(url: URL, device: MTLDevice, materials: MaterialKind = .pbr) throws {
        let allocator = MTKMeshBufferAllocator(device: device)
        let asset = MDLAsset(url: url, vertexDescriptor: nil, bufferAllocator: allocator)
        guard asset.count > 0 else {
            throw ModelIOSceneGraphError.emptyAsset(url)
        }
        try self.init(asset: asset, device: device, materials: materials, label: url.deletingPathExtension().lastPathComponent)
    }

    public init(asset: MDLAsset, device: MTLDevice, materials: MaterialKind = .pbr, label: String? = nil) throws {
        var converter = try ModelIOConverter(device: device, materialKind: materials)
        let root = SceneGraph.Node(label: label)
        for index in 0..<asset.count {
            try converter.visit(asset.object(at: index), parent: root)
        }
        sceneGraph = SceneGraph(root: root)
        animation = converter.channels.isEmpty ? nil : SceneGraph.AnimationClip(name: label, channels: converter.channels)
        warnings = converter.warnings
    }
}

enum ModelIOSceneGraphError: Error {
    case emptyAsset(URL)
    case samplerCreationFailed
}

private struct ModelIOConverter {
    let device: MTLDevice
    let materialKind: ModelIOSceneGraph.MaterialKind
    let textureLoader: MTKTextureLoader
    let samplerDescriptor: MTLSamplerDescriptor
    let sampler: MTLSamplerState
    let placeholder: PBRMaterial.Binding
    var channels: [SceneGraph.AnimationClip.Channel] = []
    var warnings: [String] = []
    var materialCache: [ObjectIdentifier: any SceneSprockets.Material] = [:]
    var textureCache: [ObjectIdentifier: MTLTexture] = [:]

    init(device: MTLDevice, materialKind: ModelIOSceneGraph.MaterialKind) throws {
        self.device = device
        self.materialKind = materialKind
        textureLoader = MTKTextureLoader(device: device)
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.mipFilter = .linear
        descriptor.sAddressMode = .repeat
        descriptor.tAddressMode = .repeat
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            throw ModelIOSceneGraphError.samplerCreationFailed
        }
        self.sampler = sampler
        samplerDescriptor = descriptor
        placeholder = try PBRMaterial.placeholderBinding(device: device)
    }

    func binding(_ texture: MTLTexture) throws -> PBRMaterial.Binding {
        try PBRMaterial.Binding(texture: texture, samplerDescriptor: samplerDescriptor, device: device)
    }

    mutating func visit(_ object: MDLObject, parent: SceneGraph.Node) throws {
        let node = SceneGraph.Node(parent: parent, label: object.name.isEmpty ? nil : object.name)
        if let transform = object.transform {
            node.transform = transform.matrix
            sampleAnimation(transform, node: node)
        }
        switch object {
        case let mesh as MDLMesh:
            if let (metalMesh, materials) = try convert(mesh) {
                node.content = .mesh(metalMesh, materials: materials)
            }
        case let camera as MDLCamera:
            if camera.projection == .perspective {
                let far = max(camera.farVisibilityDistance, camera.nearVisibilityDistance)
                node.content = .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(camera.fieldOfView), depthMode: .standard(zClip: camera.nearVisibilityDistance ... far))))
            } else {
                warnings.append("Camera \(object.name) skipped: only perspective cameras are supported")
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

    // Keyframed transforms become one TRS channel set, sampled at the key times with linear interpolation.
    mutating func sampleAnimation(_ transform: MDLTransformComponent, node: SceneGraph.Node) {
        let times = transform.keyTimes.map { Float($0.doubleValue) }
        guard times.count > 1 else {
            return
        }
        let samples = times.map { Transform3D(decomposing: transform.localTransform?(atTime: TimeInterval($0)) ?? transform.matrix) }
        let translations = samples.flatMap { [$0.translation.x, $0.translation.y, $0.translation.z] }
        let rotations = samples.flatMap { [$0.rotation.vector.x, $0.rotation.vector.y, $0.rotation.vector.z, $0.rotation.vector.w] }
        let scales = samples.flatMap { [$0.scale.x, $0.scale.y, $0.scale.z] }
        channels += [
            .init(target: node, path: .translation, sampler: .init(times: times, values: translations, interpolation: .linear)),
            .init(target: node, path: .rotation, sampler: .init(times: times, values: rotations, interpolation: .linear)),
            .init(target: node, path: .scale, sampler: .init(times: times, values: scales, interpolation: .linear)),
        ]
    }

    // Repacks to position, normal and texture coordinates (the layout both renderers read), one buffer.
    mutating func convert(_ mesh: MDLMesh) throws -> (MetalMesh, [any SceneSprockets.Material])? {
        guard mesh.vertexCount > 0, let submeshes = mesh.submeshes as? [MDLSubmesh], !submeshes.isEmpty else {
            return nil
        }
        if mesh.vertexAttributeData(forAttributeNamed: MDLVertexAttributeNormal) == nil {
            mesh.addNormals(withAttributeNamed: MDLVertexAttributeNormal, creaseThreshold: 0.5)
        }
        let descriptor = MDLVertexDescriptor()
        descriptor.attributes[0] = MDLVertexAttribute(name: MDLVertexAttributePosition, format: .float3, offset: 0, bufferIndex: 0)
        descriptor.attributes[1] = MDLVertexAttribute(name: MDLVertexAttributeNormal, format: .float3, offset: 12, bufferIndex: 0)
        descriptor.attributes[2] = MDLVertexAttribute(name: MDLVertexAttributeTextureCoordinate, format: .float2, offset: 24, bufferIndex: 0)
        descriptor.layouts[0] = MDLVertexBufferLayout(stride: 32)
        mesh.vertexDescriptor = descriptor

        let mtkMesh = try MTKMesh(mesh: mesh, device: device)
        let metalMesh = MetalMesh(mtkMesh: mtkMesh)
        let materials = try submeshes.map { try material($0.material) }
        return (metalMesh, materials)
    }

    mutating func material(_ source: MDLMaterial?) throws -> any SceneSprockets.Material {
        let key = source.map { ObjectIdentifier($0) }
        if let key, let cached = materialCache[key] {
            return cached
        }
        let baseColor = color(source?.property(with: .baseColor)) ?? [0.8, 0.8, 0.8, 1]
        let metallic = scalar(source?.property(with: .metallic)) ?? 0
        let roughness = scalar(source?.property(with: .roughness)) ?? 0.5
        let emission = color(source?.property(with: .emission)).map { SIMD3($0.x, $0.y, $0.z) } ?? .zero
        let baseColorTexture = try texture(source?.property(with: .baseColor), sRGB: true)
        let emissionTexture = try texture(source?.property(with: .emission), sRGB: true)

        let result: any SceneSprockets.Material
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
            if let normalTexture = try texture(source?.property(with: .tangentSpaceNormal), sRGB: false) {
                bindings[Int(kPBRTextureNormal.rawValue)] = try binding(normalTexture)
                uniforms.normal.enabled = 1
            }
            if let occlusionTexture = try texture(source?.property(with: .ambientOcclusion), sRGB: false) {
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
            let diffuse: BlinnPhongSceneMaterial.Source = baseColorTexture.map { .texture($0, sampler: sampler) } ?? .color(SIMD3(baseColor.x, baseColor.y, baseColor.z))
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
    func firstChannel(of map: MDLTexture) -> [UInt8]? {
        guard let data = map.texelDataWithTopLeftOrigin() else {
            return nil
        }
        let count = Int(map.dimensions.x) * Int(map.dimensions.y)
        let channels = Int(map.channelCount)
        return data.withUnsafeBytes { bytes -> [UInt8]? in
            switch map.channelEncoding {
            case .uInt8:
                guard bytes.count >= count * channels else { return nil }
                return (0..<count).map { bytes[$0 * channels] }
            case .uInt16:
                guard bytes.count >= count * channels * 2 else { return nil }
                let values = bytes.bindMemory(to: UInt16.self)
                return (0..<count).map { UInt8(values[$0 * channels] >> 8) }
            case .float32:
                guard bytes.count >= count * channels * 4 else { return nil }
                let values = bytes.bindMemory(to: Float.self)
                return (0..<count).map { UInt8(min(max(values[$0 * channels], 0), 1) * 255) }
            default:
                return nil
            }
        }
    }

    mutating func texture(_ property: MDLMaterialProperty?, sRGB: Bool) throws -> MTLTexture? {
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
                .textureStorageMode: MTLStorageMode.private.rawValue,
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
