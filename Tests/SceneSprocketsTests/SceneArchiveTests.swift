import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
import MetalSprocketsPBR
import SwiftMesh
import Testing
import simd
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import SceneSprocketsShaderMaterial

// #156
@MainActor
struct SceneArchiveTests {
    let device = MTLCreateSystemDefaultDevice()!
    let archive = SceneArchive(materialTypes: [BlinnPhongSceneMaterial.self, PBRSceneMaterial.self], environmentMapTypes: [PBREnvironment.self])

    func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(SceneArchive.pathExtension)
    }

    // A 2x2 RGBA texture with distinct pixels, including partial alpha.
    func makeTexture() -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm_srgb, width: 2, height: 2, mipmapped: false)
        descriptor.usage = .shaderRead
        let texture = device.makeTexture(descriptor: descriptor)!
        let pixels: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 10, 20, 30, 40]
        texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, withBytes: pixels, bytesPerRow: 8)
        return texture
    }

    func makeScene() throws -> SceneGraph {
        let root = SceneGraph.Node(label: "Root")
        let textured = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .texture(makeTexture(), tint: [1, 0.5, 0.25]), specular: .color(0.3), shininess: 24, opacity: 0.75, renderState: .init(blendMode: .add, fillMode: .lines))
        let box = SceneGraph.Node(parent: root, shape: .box(width: 2, height: 1, length: 0.5), material: textured, device: device, trs: .init(translation: [1, 2, 3], rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0]), scale: [1, 2, 1]))
        box.categoryBitMask = 5
        box.lightCategoryBitMask = 3
        box.renderingOrder = 2
        box.opacity = 0.5
        let metal = try PBRSceneMaterial(device: device, baseColor: [0.9, 0.7, 0.2, 1], metallic: 1, roughness: 0.3)
        let sphere = SceneGraph.Node(parent: box, shape: .sphere(radius: 0.4), material: metal, device: device)
        sphere.transform = float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [4, 5, 6, 1]))
        sphere.pivot = float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0.1, 0.2, 0.3, 1]))
        sphere.isVisible = false
        _ = SceneGraph.Node(parent: root, label: "Text", shape: .text("Hi", fontName: "Helvetica-Bold", fontSize: 0.5, extrusionDepth: 0.05), material: metal, device: device)
        var spot = Light.spot(color: [1, 0.9, 0.8], intensity: 30, range: 12, innerConeAngle: 0.3, outerConeAngle: 0.5)
        spot.range = 12
        _ = SceneGraph.Node(parent: root, label: "Spot", trs: .init(translation: [0, 5, 0]), content: .light(spot))
        _ = SceneGraph.Node(parent: root, label: "Sun", content: .light(Light(type: .directional)))
        _ = SceneGraph.Node(parent: root, label: "Camera", content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40), depthMode: .reversed(zClip: 0.1 ... 50)), categoryBitMask: 7)))
        _ = SceneGraph.Node(parent: root, label: "Ortho", content: .camera(Camera(projection: OrthographicProjection(halfHeight: 3))))
        let scene = SceneGraph(root: root)
        scene.environment = .init(background: .color([0.1, 0.2, 0.3, 1]), map: PBREnvironment.studio, intensity: 0.8, rotation: 1.2)
        scene.fog = .init(color: [0.5, 0.5, 0.6, 0.9], startDistance: 3, endDistance: 20, densityExponent: 2)
        scene.postProcessing = .init(exposure: 0.5, contrast: 1.1, saturation: 0.9, vignetteIntensity: 0.3, ambientOcclusion: .init(radius: 0.4, intensity: 0.7, sampleCount: 8))
        return scene
    }

    func sceneJSON(_ url: URL) throws -> String {
        try String(contentsOf: url.appendingPathComponent("scene.json"), encoding: .utf8)
    }

    @Test
    func roundTripKeepsEverythingItSaves() throws {
        let first = temporaryURL()
        let second = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let warnings = try archive.write(try makeScene(), to: first)
        #expect(warnings.isEmpty, "\(warnings)")
        let (loaded, readWarnings) = try archive.read(from: first, device: device)
        #expect(readWarnings.isEmpty, "\(readWarnings)")
        // Saving what was loaded gives the same file: nothing was lost or changed.
        try archive.write(loaded, to: second)
        #expect(try sceneJSON(first) == sceneJSON(second))

        let nodes = loaded.root.children
        #expect(nodes.map(\.label) == ["Box", "Text", "Spot", "Sun", "Camera", "Ortho"])
        let box = nodes[0]
        #expect(box.shape == .box(width: 2, height: 1, length: 0.5))
        #expect(box.categoryBitMask == 5 && box.lightCategoryBitMask == 3 && box.renderingOrder == 2 && box.opacity == 0.5)
        let sphere = try #require(box.children.first)
        #expect(!sphere.isVisible)
        #expect(sphere.pivot.columns.3 == [0.1, 0.2, 0.3, 1])
        guard case let .mesh(mesh, materials, _, _) = sphere.content, let pbr = materials.first as? PBRSceneMaterial else {
            Issue.record("sphere lost its mesh or material")
            return
        }
        #expect(mesh.vertexCount > 0)
        #expect(pbr.pbrMaterial.uniforms.baseColorFactor == [0.9, 0.7, 0.2, 1])
        #expect(loaded.environment.map === PBREnvironment.studio)
        #expect(loaded.fog?.densityExponent == 2)
        #expect(loaded.postProcessing?.ambientOcclusion?.sampleCount == 8)
    }

    @Test
    func texturesRoundTripExactly() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try archive.write(try makeScene(), to: url)
        let (loaded, _) = try archive.read(from: url, device: device)
        guard case let .mesh(_, materials, _, _) = loaded.root.children[0].content,
              let material = materials.first as? BlinnPhongSceneMaterial,
              case let .texture(texture, _, tint) = material.diffuse
        else {
            Issue.record("box lost its textured material")
            return
        }
        #expect(tint == [1, 0.5, 0.25])
        #expect(material.renderState.blendMode == .add && material.renderState.fillMode == .lines)
        // Read back through a shared copy: the loaded texture is private.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: texture.pixelFormat, width: 2, height: 2, mipmapped: false)
        descriptor.storageMode = .shared
        let copy = device.makeTexture(descriptor: descriptor)!
        let queue = device.makeCommandQueue()!
        let commandBuffer = queue.makeCommandBuffer()!
        let blit = commandBuffer.makeBlitCommandEncoder()!
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, to: copy, destinationSlice: 0, destinationLevel: 0, sliceCount: 1, levelCount: 1)
        blit.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var pixels = [UInt8](repeating: 0, count: 16)
        copy.getBytes(&pixels, bytesPerRow: 8, from: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0)
        #expect(pixels == [255, 0, 0, 255, 0, 255, 0, 128, 0, 0, 255, 255, 10, 20, 30, 40])
    }

    @Test
    func unsavedContentIsReported() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let root = SceneGraph.Node()
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color([1, 0, 0]), specular: .color(0), shininess: 1)
        _ = SceneGraph.Node(parent: root, label: "Generated", content: .mesh(MetalMesh(mesh: .box(), device: device), material: material))
        let warnings = try archive.write(SceneGraph(root: root), to: url)
        #expect(warnings.contains { $0.contains("Generated") && $0.contains("#158") })
    }

    // #162
    @Test
    func nodeFeaturesRoundTrip() throws {
        let first = temporaryURL()
        let second = temporaryURL()
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let root = SceneGraph.Node()
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color([1, 0, 0]), specular: .color(0), shininess: 1)
        let box = SceneGraph.Node(parent: root, label: "Box", shape: .box(), material: material, device: device)
        let jointA = SceneGraph.Node(parent: root, label: "A")
        let jointB = SceneGraph.Node(parent: jointA, label: "B")
        box.morphTargets = [.init(name: "Squash", positionDeltas: [[0, -1, 0], [0, 1, 0]], normalDeltas: [[1, 0, 0]])]
        box.morphWeights = [0.25]
        box.skin = .init(joints: [jointA, jointB], inverseBindMatrices: [.init(diagonal: [1, 1, 1, 1]), .init(diagonal: [2, 2, 2, 1])])
        box.skinVertices = [.init(joints: [0, 1, 0, 0], weights: [0.75, 0.25, 0, 0])]
        box.physicsBody = .init(type: .dynamic, shape: .capsule(height: 2, radius: 0.5), mass: 3, friction: 0.2, restitution: 0.6)
        jointA.physicsBody = .init(type: .static, shape: .convexHull)
        jointB.particleSystems = [SceneParticleSystem(ParticleSystem("Glow") { EmitterDescription("Glow") { RateModule(birthRate: 10) } }, seed: 7)]
        jointB.particleSystems[0].usesNodeTransform = false

        let warnings = try archive.write(SceneGraph(root: root), to: first)
        #expect(warnings.isEmpty, "\(warnings)")
        let (loaded, readWarnings) = try archive.read(from: first, device: device)
        #expect(readWarnings.isEmpty, "\(readWarnings)")
        try archive.write(loaded, to: second)
        #expect(try sceneJSON(first) == sceneJSON(second))

        let loadedBox = loaded.root.children[0]
        let loadedA = loaded.root.children[1]
        let loadedB = try #require(loadedA.children.first)
        #expect(loadedBox.morphTargets == box.morphTargets)
        #expect(loadedBox.morphWeights == [0.25])
        let skin = try #require(loadedBox.skin)
        #expect(skin.joints.count == 2 && skin.joints[0] === loadedA && skin.joints[1] === loadedB)
        #expect(skin.inverseBindMatrices == box.skin?.inverseBindMatrices)
        #expect(loadedBox.skinVertices == box.skinVertices)
        #expect(loadedBox.physicsBody == box.physicsBody)
        #expect(loadedA.physicsBody == jointA.physicsBody)
        let particles = try #require(loadedB.particleSystems.first)
        #expect(particles.seed == 7 && !particles.usesNodeTransform && particles.system.name == "Glow")
        #expect(try sceneJSON(first).contains(#""type" : "dynamic""#))
    }

    // #180
    func nearestClampSampler() -> MTLSamplerDescriptor {
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .nearest
        descriptor.magFilter = .nearest
        descriptor.mipFilter = .notMipmapped
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .mirrorRepeat
        descriptor.maxAnisotropy = 4
        return descriptor
    }

    func expectNearestClamp(_ descriptor: MTLSamplerDescriptor?) {
        #expect(descriptor?.minFilter == .nearest && descriptor?.magFilter == .nearest && descriptor?.mipFilter == .notMipmapped)
        #expect(descriptor?.sAddressMode == .clampToEdge && descriptor?.tAddressMode == .mirrorRepeat && descriptor?.maxAnisotropy == 4)
    }

    @Test
    func samplersRoundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let root = SceneGraph.Node()
        let placeholder = try PBRMaterial.placeholderBinding(device: device)
        var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
        bindings[Int(kPBRTextureBaseColor.rawValue)] = try .init(texture: makeTexture(), samplerDescriptor: nearestClampSampler(), device: device)
        var uniforms = PBRMaterialUniforms.defaults(baseColor: [1, 1, 1, 1], metallic: 0, roughness: 1)
        uniforms.baseColor.enabled = 1
        let pbr = PBRSceneMaterial(try PBRMaterial(uniforms: uniforms, textureBindings: bindings, device: device))
        _ = SceneGraph.Node(parent: root, label: "PBR", shape: .box(), material: pbr, device: device)
        let blinnPhong = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .texture(makeTexture(), sampler: nearestClampSampler()), specular: .color(0), shininess: 1)
        _ = SceneGraph.Node(parent: root, label: "BlinnPhong", shape: .box(), material: blinnPhong, device: device)

        let warnings = try archive.write(SceneGraph(root: root), to: url)
        #expect(warnings.isEmpty, "\(warnings)")
        let (loaded, _) = try archive.read(from: url, device: device)
        guard case let .mesh(_, pbrMaterials, _, _) = loaded.root.children[0].content, let loadedPBR = pbrMaterials.first as? PBRSceneMaterial,
              case let .mesh(_, blinnPhongMaterials, _, _) = loaded.root.children[1].content, let loadedBlinnPhong = blinnPhongMaterials.first as? BlinnPhongSceneMaterial,
              case let .texture(_, blinnPhongSampler, _) = loadedBlinnPhong.diffuse
        else {
            Issue.record("materials lost")
            return
        }
        expectNearestClamp(loadedPBR.pbrMaterial.textureBindings[Int(kPBRTextureBaseColor.rawValue)].samplerDescriptor)
        expectNearestClamp(blinnPhongSampler)
    }

    // Distinct bytes for each `seed`, so every slice and level differs.
    func pattern(_ count: Int, seed: Int) -> [UInt8] {
        var result: [UInt8] = []
        let offset = seed * 31
        for index in 0 ..< count {
            let value: Int = index * 7 + offset
            result.append(UInt8(truncatingIfNeeded: value))
        }
        return result
    }

    // Saves `texture` as a Blinn-Phong diffuse map and reads it back.
    func roundTrip(_ texture: MTLTexture) throws -> MTLTexture {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let root = SceneGraph.Node()
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .texture(texture), specular: .color(0), shininess: 1)
        _ = SceneGraph.Node(parent: root, shape: .box(), material: material, device: device)
        let warnings = try archive.write(SceneGraph(root: root), to: url)
        #expect(warnings.isEmpty, "\(warnings)")
        let (loaded, _) = try archive.read(from: url, device: device)
        guard case let .mesh(_, materials, _, _) = loaded.root.children[0].content, let blinnPhong = materials.first as? BlinnPhongSceneMaterial, case let .texture(result, _, _) = blinnPhong.diffuse else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return result
    }

    func bytes(of texture: MTLTexture, level: Int, slice: Int, bytesPerRow: Int, rows: Int, depth: Int = 1) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: bytesPerRow * rows * depth)
        let width = max(texture.width >> level, 1), height = max(texture.height >> level, 1)
        texture.getBytes(&result, bytesPerRow: bytesPerRow, bytesPerImage: bytesPerRow * rows, from: MTLRegionMake3D(0, 0, 0, width, height, depth), mipmapLevel: level, slice: slice)
        return result
    }

    @Test
    func storedMipLevelsRoundTrip() throws {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: 4, height: 2, mipmapped: true)
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        for level in 0 ..< texture.mipmapLevelCount {
            let width = max(4 >> level, 1), height = max(2 >> level, 1)
            texture.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: level, withBytes: pattern(width * height * 8, seed: level), bytesPerRow: width * 8)
        }
        let loaded = try roundTrip(texture)
        #expect(loaded.mipmapLevelCount == 3)
        for level in 0 ..< 3 {
            let width = max(4 >> level, 1), height = max(2 >> level, 1)
            #expect(bytes(of: loaded, level: level, slice: 0, bytesPerRow: width * 8, rows: height) == pattern(width * height * 8, seed: level))
        }
    }

    @Test
    func cubeTexturesRoundTrip() throws {
        let descriptor = MTLTextureDescriptor.textureCubeDescriptor(pixelFormat: .rgba8Unorm, size: 2, mipmapped: false)
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        for face in 0 ..< 6 {
            texture.replace(region: MTLRegionMake2D(0, 0, 2, 2), mipmapLevel: 0, slice: face, withBytes: pattern(16, seed: face), bytesPerRow: 8, bytesPerImage: 16)
        }
        let loaded = try roundTrip(texture)
        #expect(loaded.textureType == .typeCube)
        for face in 0 ..< 6 {
            #expect(bytes(of: loaded, level: 0, slice: face, bytesPerRow: 8, rows: 2) == pattern(16, seed: face))
        }
    }

    @Test
    func volumeTexturesRoundTrip() throws {
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type3D
        descriptor.pixelFormat = .r8Unorm
        descriptor.width = 4
        descriptor.height = 2
        descriptor.depth = 3
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        texture.replace(region: MTLRegionMake3D(0, 0, 0, 4, 2, 3), mipmapLevel: 0, slice: 0, withBytes: pattern(24, seed: 1), bytesPerRow: 4, bytesPerImage: 8)
        let loaded = try roundTrip(texture)
        #expect(loaded.textureType == .type3D && loaded.depth == 3)
        #expect(bytes(of: loaded, level: 0, slice: 0, bytesPerRow: 4, rows: 2, depth: 3) == pattern(24, seed: 1))
    }

    @Test
    func compressedTexturesRoundTrip() throws {
        // BC1: 8 bytes per 4x4 block. 8x8 is 2x2 blocks; level 1 (4x4) is one block.
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bc1_rgba, width: 8, height: 8, mipmapped: false)
        descriptor.mipmapLevelCount = 2
        descriptor.storageMode = .shared
        let texture = try #require(device.makeTexture(descriptor: descriptor))
        texture.replace(region: MTLRegionMake2D(0, 0, 8, 8), mipmapLevel: 0, withBytes: pattern(32, seed: 0), bytesPerRow: 16)
        texture.replace(region: MTLRegionMake2D(0, 0, 4, 4), mipmapLevel: 1, withBytes: pattern(8, seed: 1), bytesPerRow: 8)
        let loaded = try roundTrip(texture)
        #expect(loaded.pixelFormat == .bc1_rgba && loaded.mipmapLevelCount == 2)
        #expect(bytes(of: loaded, level: 0, slice: 0, bytesPerRow: 16, rows: 2) == pattern(32, seed: 0))
        #expect(bytes(of: loaded, level: 1, slice: 0, bytesPerRow: 8, rows: 1) == pattern(8, seed: 1))
    }

    // #163
    func pbrScene() throws -> (SceneGraph, PBRMaterialUniforms) {
        let material = try PBRSceneMaterial(device: device, baseColor: [0.9, 0.7, 0.2, 0.5], metallic: 0.25, roughness: 0.75)
        var uniforms = material.pbrMaterial.uniforms
        uniforms.emissiveFactor = [1, 0.5, 0]
        uniforms.ior = 1.7
        uniforms.clearcoatFactor = 0.4
        uniforms.unlit = 1
        uniforms.alphaMode = .mask
        uniforms.normal.enabled = 1
        uniforms.normal.texCoord = 1
        uniforms.normal.transform = simd_float3x3(columns: ([2, 0, 0], [0, 3, 0], [0.5, 0.25, 1]))
        material.pbrMaterial.uniforms = uniforms
        let root = SceneGraph.Node()
        _ = SceneGraph.Node(parent: root, label: "Sphere", shape: .sphere(), material: material, device: device)
        return (SceneGraph(root: root), material.pbrMaterial.uniforms)
    }

    func loadedUniforms(_ url: URL) throws -> PBRMaterialUniforms {
        let (loaded, _) = try archive.read(from: url, device: device)
        guard case let .mesh(_, materials, _, _) = loaded.root.children.first?.content, let pbr = materials.first as? PBRSceneMaterial else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return pbr.pbrMaterial.uniforms
    }

    @Test
    func pbrUniformsAreStoredByName() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (scene, uniforms) = try pbrScene()
        try archive.write(scene, to: url)
        let json = try sceneJSON(url)
        #expect(json.contains(#""metallicFactor" : 0.25"#))
        #expect(json.contains(#""alphaMode" : "mask""#))
        #expect(!json.contains(#""uniformsSize""#))
        let loaded = try loadedUniforms(url)
        #expect(loaded.baseColorFactor == uniforms.baseColorFactor)
        #expect(loaded.metallicFactor == 0.25 && loaded.roughnessFactor == 0.75)
        #expect(loaded.emissiveFactor == [1, 0.5, 0] && loaded.ior == 1.7 && loaded.clearcoatFactor == 0.4)
        #expect(loaded.unlit == 1 && loaded.alphaMode == .mask)
        #expect(loaded.normal.enabled == 1 && loaded.normal.texCoord == 1 && loaded.normal.transform == uniforms.normal.transform)
        #expect(loaded.baseColor.enabled == uniforms.baseColor.enabled)
    }

    // #160
    @Test
    func shaderMaterialRoundTripsByReference() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        var material = try ShaderMaterial.rim(color: [1, 0.5, 0, 0.5])
        material.parameters["tint"] = .float3([0.1, 0.2, 0.3])
        material.parameters["matrix"] = .float4x4(.init(diagonal: [1, 2, 3, 4]))
        material.parameters["texture"] = .texture(makeTexture())
        material.parameters["bytes"] = .buffer(try #require(device.makeBuffer(bytes: [UInt8](arrayLiteral: 1, 2, 3, 4), length: 4, options: .storageModeShared)))
        material.renderState = MaterialRenderState(blendMode: .add)
        let root = SceneGraph.Node()
        _ = SceneGraph.Node(parent: root, label: "Rim", shape: .sphere(), material: material, device: device)
        let shaderArchive = SceneArchive(materialTypes: [ShaderMaterial.self])
        let warnings = try shaderArchive.write(SceneGraph(root: root), to: url)
        #expect(warnings.isEmpty, "\(warnings)")
        let (loaded, readWarnings) = try shaderArchive.read(from: url, device: device)
        #expect(readWarnings.isEmpty)
        guard case let .mesh(_, materials, _, _) = loaded.root.children.first?.content, let shader = materials.first as? ShaderMaterial else {
            Issue.record("expected a ShaderMaterial")
            return
        }
        #expect(shader.vertexShader.reference.name == material.vertexShader.reference.name)
        #expect(shader.fragmentShader.reference.name == material.fragmentShader.reference.name)
        #expect(shader.isTransparent && shader.renderState.blendMode == .add)
        guard case let .float4(color) = shader.parameters["color"], case let .float3(tint) = shader.parameters["tint"], case let .float4x4(matrix) = shader.parameters["matrix"], case let .texture(texture) = shader.parameters["texture"], case let .buffer(buffer) = shader.parameters["bytes"] else {
            Issue.record("parameters missing: \(shader.parameters.keys.sorted())")
            return
        }
        #expect(color == [1, 0.5, 0, 0.5] && tint == [0.1, 0.2, 0.3] && matrix == .init(diagonal: [1, 2, 3, 4]))
        #expect(texture.width == 2 && buffer.length == 4 && buffer.contents().load(fromByteOffset: 3, as: UInt8.self) == 4)
    }

    @Test
    func shaderMaterialFromAnUnregisteredLibraryIsSkipped() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let source = """
        #include <metal_stdlib>
        using namespace metal;
        vertex float4 custom_vertex(uint id [[vertex_id]]) { return float4(0); }
        fragment float4 custom_fragment() { return float4(1); }
        """
        let library = try device.makeLibrary(source: source, options: nil)
        let material = ShaderMaterial(vertexShader: try VertexShader(ShaderFunction(library: library, name: "custom_vertex", type: .vertex)), fragmentShader: try FragmentShader(ShaderFunction(library: library, name: "custom_fragment", type: .fragment)))
        let root = SceneGraph.Node()
        _ = SceneGraph.Node(parent: root, label: "Custom", shape: .sphere(), material: material, device: device)
        let unregistered = try SceneArchive(materialTypes: [ShaderMaterial.self]).write(SceneGraph(root: root), to: url)
        #expect(unregistered.contains { $0.contains("Custom") && $0.contains("shaderLibraries") })
        // Registered, it saves and reads back.
        let registered = SceneArchive(materialTypes: [ShaderMaterial.self], shaderLibraries: ["custom": library])
        #expect(try registered.write(SceneGraph(root: root), to: url).isEmpty)
        let (loaded, _) = try registered.read(from: url, device: device)
        guard case let .mesh(_, materials, _, _) = loaded.root.children.first?.content, let shader = materials.first as? ShaderMaterial else {
            Issue.record("expected a ShaderMaterial")
            return
        }
        #expect(shader.vertexShader.reference.name == "custom_vertex")
    }

    // #164
    @Test
    func pbrTextureTransformsRoundTrip() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (scene, _) = try pbrScene()
        guard case let .mesh(_, materials, _, _) = scene.root.children[0].content, let pbr = materials.first as? PBRSceneMaterial else {
            Issue.record("expected a PBR mesh")
            return
        }
        pbr.pbrMaterial.textureTransforms = ["normalTexture": .init(slot: \.normal, offset: [0.25, 0.5], rotation: 0.3, scale: [2, 3])]
        let warnings = try archive.write(scene, to: url)
        #expect(!warnings.contains { $0.contains("texture transform") })
        let (loaded, _) = try archive.read(from: url, device: device)
        guard case let .mesh(_, loadedMaterials, _, _) = loaded.root.children.first?.content, let loadedPBR = loadedMaterials.first as? PBRSceneMaterial else {
            Issue.record("expected a PBR mesh")
            return
        }
        let transform = try #require(loadedPBR.pbrMaterial.textureTransforms["normalTexture"])
        #expect(transform.slot == \PBRMaterialUniforms.normal)
        #expect(transform.offset == [0.25, 0.5] && transform.rotation == 0.3 && transform.scale == [2, 3])
    }

    // Archives from before #163 stored the raw bytes.
    @Test
    func rawPBRUniformsStillRead() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let (scene, uniforms) = try pbrScene()
        try archive.write(scene, to: url)
        let sceneURL = url.appendingPathComponent("scene.json")
        var object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: sceneURL)) as? [String: Any])
        var root = try #require(object["root"] as? [String: Any])
        var child = try #require((root["children"] as? [[String: Any]])?.first)
        var mesh = try #require(child["mesh"] as? [String: Any])
        var material = try #require((mesh["materials"] as? [[String: Any]])?.first)
        var value = try #require(material["value"] as? [String: Any])
        let bytes = withUnsafeBytes(of: uniforms) { Data($0) }
        value["parameters"] = nil
        value["uniforms"] = bytes.base64EncodedString()
        value["uniformsSize"] = bytes.count
        material["value"] = value
        mesh["materials"] = [material]
        child["mesh"] = mesh
        root["children"] = [child]
        object["root"] = root
        try JSONSerialization.data(withJSONObject: object).write(to: sceneURL)
        let loaded = try loadedUniforms(url)
        #expect(loaded.ior == 1.7 && loaded.alphaMode == .mask && loaded.normal.transform == uniforms.normal.transform)
    }

    // #159
    @Test
    func sceneJSONIsReadable() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let root = SceneGraph.Node()
        _ = SceneGraph.Node(parent: root, transform: .init(diagonal: [1, 2, 3, 1]), content: .light(Light(type: .directional)))
        try archive.write(try makeScene(), to: url)
        let json = try sceneJSON(url)
        #expect(json.contains(#""background" : "none""#) || json.contains(#""background" : {"#))
        #expect(json.contains(#""blendMode" : "add""#))
        #expect(!json.contains(#": {\n\n"#))
        // Number arrays are on one line.
        #expect(json.range(of: #"\[\s*-?\d[^\]]*\n"#, options: .regularExpression) == nil)
        let url2 = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url2) }
        try archive.write(SceneGraph(root: root), to: url2)
        let lightJSON = try sceneJSON(url2)
        #expect(lightJSON.contains(#""type" : "directional""#))
        #expect(lightJSON.contains(#""background" : "none""#))
        #expect(lightJSON.contains("[1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 3, 0, 0, 0, 0, 1]"))
        let (loaded, _) = try archive.read(from: url2, device: device)
        #expect(loaded.root.children.first?.transform == .init(diagonal: [1, 2, 3, 1]))
    }

    // #159: archives written before it used synthesized enum objects.
    @Test
    func oldEnumFormatStillReads() throws {
        let decoder = JSONDecoder()
        #expect(try decoder.decode(Light.LightType.self, from: Data(#"{"spot": {}}"#.utf8)) == .spot)
        #expect(try decoder.decode(Light.LightType.self, from: Data(#""point""#.utf8)) == .point)
        #expect(try decoder.decode(MaterialRenderState.BlendMode.self, from: Data(#"{"screen": {}}"#.utf8)) == .screen)
        guard case .none = try decoder.decode(SceneGraph.Environment.Background.self, from: Data(#"{"none": {}}"#.utf8)) else {
            Issue.record("expected .none")
            return
        }
        guard case let .color(color) = try decoder.decode(SceneGraph.Environment.Background.self, from: Data(#"{"color": {"_0": [1, 0, 0, 1]}}"#.utf8)) else {
            Issue.record("expected .color")
            return
        }
        #expect(color == [1, 0, 0, 1])
        guard case let .environment(blur) = try decoder.decode(SceneGraph.Environment.Background.self, from: Data(#"{"environment": {"blur": 0.5}}"#.utf8)) else {
            Issue.record("expected .environment")
            return
        }
        #expect(blur == 0.5)
    }

    // #161
    @Test
    func constraintsRoundTripWithNodeReferences() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let root = SceneGraph.Node(label: "Root")
        let group = SceneGraph.Node(parent: root, label: "Group")
        let target = SceneGraph.Node(parent: group, label: "Target")
        let follower = SceneGraph.Node(parent: root, label: "Follower")
        follower.constraints = [
            .lookAt(target: target, worldUp: [0, 0, 1]),
            SceneGraph.Constraint(.distance(target: target, minimum: 1, maximum: .infinity), influenceFactor: 0.5, isEnabled: false),
            .replicator(target: target, orientation: false, orientationOffset: simd_quatf(angle: 1, axis: [0, 1, 0])),
            .billboard(freeAxes: .y),
            .inverseKinematics(chainRoot: root, target: target, iterations: 4),
            .acceleration(damping: 0.25),
            .transform { _, trs in trs },
        ]
        let warnings = try archive.write(SceneGraph(root: root), to: url)
        #expect(warnings.contains { $0.contains("Follower") && $0.contains("transform constraints") })
        let (loaded, readWarnings) = try archive.read(from: url, device: device)
        #expect(readWarnings.isEmpty)
        let loadedFollower = try #require(loaded.root.children.first { $0.label == "Follower" })
        let loadedTarget = try #require(loaded.root.children.first { $0.label == "Group" }?.children.first)
        #expect(loadedTarget.label == "Target")
        let constraints = loadedFollower.constraints
        try #require(constraints.count == 6)
        guard case let .lookAt(lookAtTarget, worldUp, _) = constraints[0].kind else {
            Issue.record("expected lookAt")
            return
        }
        #expect(lookAtTarget === loadedTarget && worldUp == [0, 0, 1])
        guard case let .distance(distanceTarget, minimum, maximum) = constraints[1].kind else {
            Issue.record("expected distance")
            return
        }
        #expect(distanceTarget === loadedTarget && minimum == 1 && maximum == .infinity)
        #expect(constraints[1].influenceFactor == 0.5 && !constraints[1].isEnabled)
        guard case let .replicator(_, _, orientation, _, _, orientationOffset, _) = constraints[2].kind else {
            Issue.record("expected replicator")
            return
        }
        #expect(!orientation && abs(orientationOffset.angle - 1) < 0.0001)
        guard case let .billboard(freeAxes) = constraints[3].kind, case let .inverseKinematics(chainRoot, _, iterations, _) = constraints[4].kind, case let .acceleration(_, _, damping) = constraints[5].kind else {
            Issue.record("expected billboard, inverseKinematics, acceleration")
            return
        }
        #expect(freeAxes == .y && chainRoot === loaded.root && iterations == 4 && damping == 0.25)
    }
}
