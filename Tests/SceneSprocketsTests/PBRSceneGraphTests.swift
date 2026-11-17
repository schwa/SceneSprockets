import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBR
@testable import SceneSprockets
@testable import SceneSprocketsPBR
import simd
import SwiftMesh
import Testing

@Test(.enabled(if: deviceSupportsMetal4))
func pbrModelIsBuiltFromSceneGraph() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = PBRSceneMaterial(baseColor: [1, 0, 0], metallic: 0, roughness: 0.5)

    let root = SceneGraph.Node()
    let translation = simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [2, 3, 4, 1]))
    root.addChild(SceneGraph.Node(transform: Transform3D(storing: translation), content: .mesh(box, material: material)))
    root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))

    let model = try PBRSceneGraphModelBuilder().makeModel(entries: SceneGraph(root: root).meshEntries())

    let instances = model.opaqueInstances
    #expect(instances.count == 2)
    #expect(instances.contains { $0.worldMatrix.columns.3 == SIMD4<Float>(2, 3, 4, 1) })
    #expect(model.bounds.max.x > 2)
}

@Test
func pbrPrimitiveHonorsIndexTypeAndPrimitiveType() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    var mesh = MetalMesh(mesh: .box(), device: device)
    let indices: [UInt16] = [9, 9, 0, 1, 2, 3]
    let buffer = try #require(device.makeBuffer(bytes: indices, length: indices.count * 2, options: .storageModeShared))
    mesh.submeshes = [MetalMesh.Submesh(indexBuffer: buffer, indexBufferOffset: 4, indexCount: 4, indexType: .uint16, primitiveType: .line)]

    let node = SceneGraph.Node(content: .mesh(mesh, material: PBRSceneMaterial()))
    let primitive = pbrPrimitiveInput(entry: SceneGraph(root: node).meshEntries()[0], attributes: mesh.vertexAttributeData(), skinned: false)
    #expect(primitive.indices == [0, 1, 2, 3])
    #expect(primitive.primitiveType == .line)
}

@Test(.enabled(if: deviceSupportsMetal4))
func pbrModelIsReusedUntilStructureChanges() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = PBRSceneMaterial()
    let root = SceneGraph.Node()
    let node = root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    let sceneGraph = SceneGraph(root: root)
    let renderer = PBRMaterialRenderer()

    let first = try renderer.model(for: sceneGraph.meshEntries(), structureRevision: sceneGraph.revision.structure)
    node.transform.translation = [1, 0, 0]
    let second = try renderer.model(for: sceneGraph.meshEntries(), structureRevision: sceneGraph.revision.structure)
    #expect(first === second)

    root.addChild(SceneGraph.Node(content: .mesh(box, material: material)))
    let third = try renderer.model(for: sceneGraph.meshEntries(), structureRevision: sceneGraph.revision.structure)
    #expect(third !== second)
    #expect(third.opaqueInstances.count == 2)
}

@Test
func morphTargetsReachPBRPrimitiveAndPose() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let up = SceneGraph.MorphTarget(positionDeltas: Array(repeating: [0, 1, 0], count: box.vertexCount))
    let node = SceneGraph.Node(content: .mesh(box, material: PBRSceneMaterial()))
    node.morphTargets = [up]
    node.morphWeights = [0.5]
    let entries = SceneGraph(root: node).meshEntries()

    let primitive = pbrPrimitiveInput(entry: entries[0], attributes: box.vertexAttributeData(), skinned: false)
    let targets = try #require(primitive.morphTargets).targets
    #expect(targets.count == 1)
    #expect(targets[0].positionOffsets?.count == box.vertexCount)
    #expect(targets[0].positionOffsets?[0] == [0, 1, 0])
    #expect(pbrPose(for: entries).morphWeights == [[0.5]])
}

@Test
func morphTargetsWithWrongVertexCountAreIgnored() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let node = SceneGraph.Node(content: .mesh(box, material: PBRSceneMaterial()))
    node.morphTargets = [SceneGraph.MorphTarget(positionDeltas: [[0, 1, 0]])]
    let primitive = pbrPrimitiveInput(entry: SceneGraph(root: node).meshEntries()[0], attributes: box.vertexAttributeData(), skinned: false)
    #expect(primitive.morphTargets == nil)
}

@Test(.enabled(if: deviceSupportsMetal4))
func pbrModelIsBuiltForEachBufferLayout() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    for layout in [MetalMesh.BufferLayout.interleaved, .separateBuffers] {
        let box = MetalMesh(mesh: .box(), device: device, bufferLayout: layout)
        let node = SceneGraph.Node(content: .mesh(box, material: PBRSceneMaterial()))
        let model = try PBRSceneGraphModelBuilder().makeModel(entries: SceneGraph(root: node).meshEntries())
        #expect(model.opaqueInstances.count == 1)
    }
}

@Test
func pbrLightDirectionFollowsNodeRotation() {
    // Rotate -90° about X: the node's -Z axis points down (-Y).
    let angle = -Float.pi / 2
    let rotation = simd_float4x4(simd_quatf(angle: angle, axis: [1, 0, 0]))
    let light = pbrLight(worldTransform: rotation, light: Light(type: .directional))
    #expect(light.type == .directional)
    #expect(simd_distance(light.direction, [0, -1, 0]) < 0.001)
}

// #114: PBRSceneMaterial.renderState reaches the PBR renderer, and fading keeps it.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func pbrRenderStateIsApplied() throws {
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh()
    func centerPixel(_ renderState: PBRRenderState) throws -> SIMD4<UInt8> {
        let root = SceneGraph.Node()
        root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
        let material = PBRSceneMaterial(baseColor: [0, 0, 0])
        material.uniforms.emissiveFactor = [1, 0, 0]
        material.renderState = renderState
        root.addChild(SceneGraph.Node(content: .mesh(quad, material: material)))
        let graph = SceneGraph(root: root)
        graph.environment.background = .color([0, 0, 0, 1])
        let element = SceneGraphElement(sceneGraph: graph, aspectRatio: 1, renderers: [PBRMaterialRenderer(environmentIntensity: 0)])
        let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(element).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
        return value
    }
    #expect(try centerPixel(PBRRenderState()).z > 200)
    #expect(try centerPixel(PBRRenderState(colorWriteMask: [.green, .blue, .alpha])).z < 10)

    let additive = PBRSceneMaterial()
    additive.renderState = PBRRenderState(blendMode: .additive)
    #expect(additive.isTransparent)
    let faded = PBRSceneMaterial.faded(additive.pbrMaterial, opacity: 0.5)
    #expect(faded.renderState == additive.renderState)
}

// #368: plain PBR materials are made without `try`, from an RGB color and a separate opacity.
@Test(.enabled(if: deviceSupportsMetal4))
func pbrSceneMaterialFromRGBAndOpacity() {
    let material = PBRSceneMaterial(baseColor: [0.2, 0.4, 0.6], opacity: 0.5, metallic: 1, roughness: 0.3)
    #expect(material.pbrMaterial.uniforms.baseColorFactor == SIMD4<Float>(0.2, 0.4, 0.6, 0.5))
    #expect(material.pbrMaterial.uniforms.metallicFactor == 1)
    #expect(PBRSceneMaterial().pbrMaterial.uniforms.baseColorFactor == SIMD4<Float>(1, 1, 1, 1))
}

// #479: an app changes the renderer's settings on the main thread while SceneView's render thread reads them. The
// race is on plain values, so it only shows with the thread sanitizer (--sanitize=thread).
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func pbrRendererSettingsCanChangeWhileAFrameIsLit() async throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(content: .camera(Camera.default)))
    root.addChild(SceneGraph.Node(content: .light(Light(type: .directional, intensity: 1))))
    let context = try #require(makeRenderContext(sceneGraph: SceneGraph(root: root), camera: nil, cameraMatrix: nil, aspectRatio: 1))
    let renderer = PBRMaterialRenderer()
    nonisolated(unsafe) let unsafeRenderer = renderer
    nonisolated(unsafe) let unsafeContext = context
    let rendering = Task.detached {
        for _ in 0..<2_000 {
            _ = unsafeRenderer.lighting(context: unsafeContext)
        }
    }
    for index in 0..<2_000 {
        renderer.exposure = Float(index % 4)
        renderer.environmentIntensity = Float(index % 3)
        renderer.environment = .studio
    }
    await rendering.value
    #expect(renderer.exposure == Float(1_999 % 4))
}

// #479: changing a live material's uniforms shows on the next frame, without a structure change. A change that moves
// it to another pass (opaque to blended) rebuilds the model.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func pbrMaterialChangesShowOnTheNextFrame() throws {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    let material = PBRSceneMaterial(baseColor: [0, 0, 0])
    material.uniforms.emissiveFactor = [1, 0, 0]
    root.addChild(SceneGraph.Node(content: .mesh(SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(), material: material)))
    let graph = SceneGraph(root: root)
    graph.environment.background = .color([0, 0, 0, 1])
    let renderer = PBRMaterialRenderer(environmentIntensity: 0)
    let offscreen = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    func centerPixel() throws -> SIMD4<UInt8> {
        let texture = try offscreen.render(SceneGraphElement(sceneGraph: graph, aspectRatio: 1, renderers: [renderer])).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
        return value
    }
    let red = try centerPixel()
    let revision = graph.revision.structure
    material.uniforms.emissiveFactor = [0, 1, 0]
    #expect(graph.revision.structure == revision)
    let green = try centerPixel()
    #expect(red.z > 200 && red.y < 50, "\(red)")
    #expect(green.y > 200 && green.z < 50, "\(green)")

    var blended = material.uniforms
    blended.alphaMode = .blend
    blended.emissiveFactor = [0, 0, 1]
    material.uniforms = blended
    #expect(material.isTransparent)
    let blue = try centerPixel()
    #expect(blue.x > 200 && blue.y < 50, "\(blue)")
}

// #479: an app can change a PBR material on one thread while a render thread reads it. Run with --sanitize=thread.
@Test(.enabled(if: deviceSupportsMetal4))
func pbrMaterialCanChangeWhileAFrameReadsIt() async {
    let material = PBRSceneMaterial(baseColor: [1, 1, 1])
    let rendering = Task.detached {
        for _ in 0..<2_000 {
            _ = material.pbrMaterial.isBlended
        }
    }
    for index in 0..<2_000 {
        material.uniforms.roughnessFactor = Float(index % 10) / 10
        material.renderState = index.isMultiple(of: 2) ? PBRRenderState() : PBRRenderState(blendMode: .additive)
    }
    await rendering.value
    #expect(material.uniforms.roughnessFactor == 0.9)
}

// #375: PBRSceneMaterial wraps a shared PBRMaterial, so it is a class: assigning shares it, visibly.
@Test(.enabled(if: deviceSupportsMetal4))
func pbrSceneMaterialHasReferenceSemantics() {
    let a = PBRSceneMaterial(baseColor: [1, 0, 0])
    let b = a
    #expect(a === b)
    b.renderState.blendMode = .additive
    #expect(a.renderState.blendMode == .additive)
}
