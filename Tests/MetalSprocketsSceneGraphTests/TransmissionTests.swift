import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBR
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphPBR

// #123: a smooth glass quad in front of an emissive green quad, or nothing. Returns the center pixel (BGRA).
@MainActor
private func glass(behind: Bool) throws -> SIMD4<UInt8> {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    let glass = try PBRSceneMaterial(device: device, baseColor: [1, 1, 1, 1], roughness: 0)
    glass.pbrMaterial.uniforms.transmissionFactor = 1
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: glass))
    if behind {
        let green = try PBRSceneMaterial(device: device, baseColor: [0, 0, 0, 1])
        green.pbrMaterial.uniforms.emissiveFactor = [0, 1, 0]
        _ = SceneGraph.Node(parent: root, content: .mesh(quad, material: green))
    }
    let graph = SceneGraph(root: root)
    let element = SceneGraphElement(sceneGraph: graph, aspectRatio: 1, renderers: [PBRMaterialRenderer(device: device)])
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

@Test
@MainActor
func glassShowsTheSceneBehindIt() throws {
    let empty = try glass(behind: false)
    let green = try glass(behind: true)
    #expect(Int(green.y) > Int(empty.y) + 60)
    #expect(Int(green.y) > Int(green.x) + 60)
}
