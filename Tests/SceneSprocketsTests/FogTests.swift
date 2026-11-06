import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

@Test
func fogAmountFollowsStartEndAndExponent() {
    let fog = SceneGraph.Fog(color: [1, 1, 1, 0.8], startDistance: 10, endDistance: 20, densityExponent: 2)
    #expect(fog.amount(atDistance: 5) == 0)
    #expect(abs(fog.amount(atDistance: 15) - 0.25 * 0.8) < 1e-5)
    #expect(abs(fog.amount(atDistance: 50) - 0.8) < 1e-5)
}

// A near box and a far box on a black background; red fog that starts past the near box.
@Test
@MainActor
func fogTintsFarGeometryOnly() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color([0.2, 0.2, 0.2]), diffuse: .color([0.2, 0.2, 0.2]), specular: .color(0), shininess: 1)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: 0.1 ... 200)))))
    _ = SceneGraph.Node(parent: root, content: .light(Light(type: .directional, color: [0.2, 0.2, 0.2], intensity: 1)))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [-1.5, 0, -4]), content: .mesh(box, material: material))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [12, 0, -40], scale: [8, 8, 8]), content: .mesh(box, material: material))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.fog = SceneGraph.Fog(color: [1, 0, 0, 1], startDistance: 10, endDistance: 30)

    let size = 64
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])).texture
    func pixel(_ point: SIMD3<Float>) -> SIMD4<UInt8> {
        let context = makeRenderContext(sceneGraph: sceneGraph, camera: nil, cameraMatrix: nil, aspectRatio: 1)!
        let clip = context.projectionMatrix * context.viewMatrix * SIMD4(point, 1)
        let x = Int((clip.x / clip.w + 1) / 2 * Float(size))
        let y = Int((1 - clip.y / clip.w) / 2 * Float(size))
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(x, y, 1, 1), mipmapLevel: 0)
        return value
    }
    // BGRA.
    let near = pixel([-1.5, 0, -3.5])
    let far = pixel([12, 0, -36])
    #expect(Int(far.z) > Int(far.x) + 100) // Far box is red.
    #expect(abs(Int(near.z) - Int(near.x)) < 10) // Near box stays grey.
    let corner = { () -> SIMD4<UInt8> in
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0)
        return value
    }()
    #expect(corner.z < 3) // Background is not fogged.
}
