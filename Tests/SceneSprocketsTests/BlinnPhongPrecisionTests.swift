import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import Testing

// #253: a quad lit by a point light, everything shifted by `offset`. Returns BGRA pixels.
@MainActor
private func render(offset: SIMD3<Float>) throws -> [SIMD4<UInt8>] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0.6), specular: .color(1), shininess: 64)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: offset + [0, 0, 1.5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60)))))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: offset + [0.25, 0.25, 0.5]), content: .light(Light(type: .point, intensity: 2)))
    _ = SceneGraph.Node(parent: root, trs: .init(translation: offset), content: .mesh(quad, material: material))
    let size = 32
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero)])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    return pixels
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func blinnPhongShadesTheSameFarFromOrigin() throws {
    let near = try render(offset: .zero)
    // 2^20 m: Float spacing 0.125 m, so world-space shading is visibly blocky. Offsets are exact in Float.
    let far = try render(offset: [1_048_576, 0, 1_048_576])
    let differences = zip(near, far).map { a, b in
        (0..<3).map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0
    }
    #expect(near.contains { $0.z > 50 }, "the quad should be lit")
    #expect((differences.max() ?? 0) <= 3, "max channel difference \(differences.max() ?? 0)")
}
