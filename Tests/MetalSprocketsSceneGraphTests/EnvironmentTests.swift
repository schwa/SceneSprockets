import GeometryLite3D
import Metal
import MetalSprocketsPBR
import Testing
import simd
@testable import MetalSprocketsSceneGraph

private func context(for sceneGraph: SceneGraph) throws -> SceneGraphRenderContext {
    try #require(makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1))
}

private func sceneWithCamera() -> SceneGraph {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, content: .camera(Camera(projection: PerspectiveProjection())))
    return SceneGraph(root: root)
}

@Test
func pbrLightingUsesSceneEnvironment() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let map = try PBREnvironment(source: .uniform([0.5, 0.5, 0.5]), device: device, specularSize: 16, irradianceSize: 8)
    let sceneGraph = sceneWithCamera()
    sceneGraph.environment = SceneGraph.Environment(background: .environment(blur: 0.5), map: map, intensity: 2, rotation: 1)
    let renderer = PBRMaterialRenderer(device: device, environmentIntensity: 0.5)

    let lighting = renderer.lighting(context: try context(for: sceneGraph))
    #expect(lighting.environment === map)
    #expect(lighting.environmentIntensity == 1)
    #expect(lighting.environmentRotation == 1)
    #expect(try renderer.makeBackgroundElement(context: try context(for: sceneGraph)) != nil)
}

@Test
func pbrRendererFallsBackToItsEnvironment() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let renderer = PBRMaterialRenderer(device: device)
    let sceneGraph = sceneWithCamera()
    #expect(renderer.lighting(context: try context(for: sceneGraph)).environment === renderer.environment)
    #expect(try renderer.makeBackgroundElement(context: try context(for: sceneGraph)) == nil)

    sceneGraph.environment.background = .color([1, 0, 0, 1])
    #expect(try renderer.makeBackgroundElement(context: try context(for: sceneGraph)) == nil)
}
