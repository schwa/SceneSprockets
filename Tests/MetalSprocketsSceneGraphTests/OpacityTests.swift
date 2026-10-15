import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
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
