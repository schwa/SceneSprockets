import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBR
import Testing
import simd
@testable import MetalSprocketsSceneGraph

// #76

@Test
func opacityIsInheritedByMeshEntries() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 1, height: 1).metalMesh(device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color(1), diffuse: .color(0), specular: .color(0), shininess: 1)
    let root = SceneGraph.Node()
    let parent = SceneGraph.Node(parent: root)
    let child = SceneGraph.Node(parent: parent, content: .mesh(quad, material: material))
    let graph = SceneGraph(root: root)
    #expect(graph.meshEntries().first?.opacity == 1)
    #expect(graph.meshEntries().first?.isTransparent == false)
    parent.opacity = 0.5
    child.opacity = 0.5
    let entry = try #require(graph.meshEntries().first)
    #expect(abs(entry.opacity - 0.25) < 1e-6)
    #expect(entry.isTransparent)
}

@Test
func fadeActionsChangeOpacity() {
    let node = SceneGraph.Node()
    let graph = SceneGraph(root: node)
    node.run(.fadeOut(duration: 2))
    graph.advanceActions(by: 1)
    #expect(abs(node.opacity - 0.5) < 1e-4)
    graph.advanceActions(by: 5)
    #expect(node.opacity == 0)
    node.run(.fadeIn(duration: 1))
    graph.advanceActions(by: 1)
    #expect(node.opacity == 1)
    node.run(.fadeOpacity(to: 0.2, duration: 1))
    graph.advanceActions(by: 1)
    #expect(abs(node.opacity - 0.2) < 1e-4)
    node.run(.fadeOpacity(by: 0.3, duration: 1))
    graph.advanceActions(by: 1)
    #expect(abs(node.opacity - 0.5) < 1e-4)
}

// #108: a PBR red quad at node opacity 0.5 in front of an emissive blue Blinn-Phong quad. Returns the center pixel
// (BGRA) and the renderer, so tests can check model reuse.
@MainActor
private func pbrOverBlue(opacity: Float, renderer pbrRenderer: PBRMaterialRenderer? = nil, fader: SceneGraph.Node? = nil) throws -> (pixel: SIMD4<UInt8>, renderer: PBRMaterialRenderer, fader: SceneGraph.Node, graph: SceneGraph) {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    let red = try PBRSceneMaterial(device: device, baseColor: [1, 0, 0, 1])
    let fader = fader ?? SceneGraph.Node(trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: red))
    root.addChild(fader)
    fader.opacity = opacity
    _ = SceneGraph.Node(parent: root, content: .mesh(quad, material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0, 0, 1]))))
    let pbrRenderer = pbrRenderer ?? PBRMaterialRenderer(device: device)
    let graph = SceneGraph(root: root)
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(SceneGraphElement(sceneGraph: graph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero), pbrRenderer])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return (value, pbrRenderer, fader, graph)
}

@Test
@MainActor
func pbrNodeOpacityBlends() throws {
    // Opaque, the lit red quad hides the blue one (its blue channel is only environment light). At half opacity,
    // blue shows through and red drops.
    let opaque = try pbrOverBlue(opacity: 1).pixel
    let half = try pbrOverBlue(opacity: 0.5).pixel
    #expect(Int(half.x) > Int(opaque.x) + 40)
    #expect(Int(half.z) < Int(opaque.z) - 40)
}

@Test
@MainActor
func pbrOpacityChangeReusesTheModel() throws {
    let first = try pbrOverBlue(opacity: 0.5)
    let entries = first.graph.meshEntries().filter { $0.material is PBRSceneMaterial }
    let model = try first.renderer.model(for: entries, structureRevision: first.graph.revision.structure)
    first.fader.opacity = 0.3
    let changed = first.graph.meshEntries().filter { $0.material is PBRSceneMaterial }
    #expect(try first.renderer.model(for: changed, structureRevision: first.graph.revision.structure) === model)
}

// A half-opaque red quad (opacity from its parent node) in front of an opaque blue quad: both colors show.
@Test(arguments: [false, true])
@MainActor
func nodeOpacityBlends(usesShaderMaterial: Bool) throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    func flat(_ color: SIMD3<Float>) throws -> any MetalSprocketsSceneGraph.Material {
        if usesShaderMaterial {
            // Facing the camera, rim is the plain color.
            return try ShaderMaterial.rim(color: SIMD4(color, 1))
        }
        return BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color))
    }
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    let fader = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0.5]))
    fader.opacity = 0.5
    _ = SceneGraph.Node(parent: fader, content: .mesh(quad, material: try flat([1, 0, 0])))
    _ = SceneGraph.Node(parent: root, content: .mesh(quad, material: try flat([0, 0, 1])))
    let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let renderers: [any SceneGraphMaterialRenderer] = [BlinnPhongMaterialRenderer(ambientLightColor: .zero), ShaderMaterialRenderer()]
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: renderers)).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    // BGRA.
    #expect(value.z > 100 && value.x > 100)
}
