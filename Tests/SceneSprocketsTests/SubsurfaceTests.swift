import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsPBR
import simd
import Testing

// #538: approximate subsurface scattering on PBR materials (wrapped diffuse, tinted).
private let size = 64

// A white sphere lit from +x, seen from +z: its left half is past the terminator.
@MainActor
private func render(subsurface: (color: SIMD3<Float>, strength: Float, radius: Float)?) throws -> [SIMD4<UInt8>] {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0])), content: .light(.directional(intensity: 3))))
    let material = PBRSceneMaterial(baseColor: [1, 1, 1], roughness: 1)
    if let subsurface {
        var uniforms = material.uniforms
        uniforms.subsurfaceColor = subsurface.color
        uniforms.subsurfaceStrength = subsurface.strength
        uniforms.subsurfaceRadius = subsurface.radius
        material.uniforms = uniforms
    }
    root.addChild(SceneGraph.Node(shape: .sphere(radius: 1), material: material))
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.intensity = 0
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size))
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer(environmentIntensity: 0)])).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    let isBGRA = texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb
    return isBGRA ? pixels.map { SIMD4($0.z, $0.y, $0.x, $0.w) } : pixels
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func subsurfaceLightsPastTheTerminator() throws {
    // Just past the terminator, on the unlit side.
    let pixel = (size / 2) * size + size / 2 - 4
    let plain = try render(subsurface: nil)
    let scattered = try render(subsurface: ([1, 0.3, 0.2], 1, 0.6))
    #expect(Int(plain[pixel].x) < 10, "\(plain[pixel])")
    // Reddish light wraps around.
    #expect(Int(scattered[pixel].x) > Int(plain[pixel].x) + 30, "\(scattered[pixel])")
    #expect(scattered[pixel].x > scattered[pixel].z)
    // Facing the light, wrapping adds little.
    let lit = (size / 2) * size + size / 2 + 12
    #expect(abs(Int(scattered[lit].y) - Int(plain[lit].y)) < Int(plain[lit].y) / 8, "\(plain[lit]) -> \(scattered[lit])")
}

@Test
@MainActor
func subsurfaceIsArchived() throws {
    let material = PBRSceneMaterial()
    var uniforms = material.uniforms
    uniforms.subsurfaceColor = [1, 0.5, 0.25]
    uniforms.subsurfaceStrength = 0.75
    uniforms.subsurfaceRadius = 0.4
    material.uniforms = uniforms
    let sceneGraph = SceneGraph(linearRoot: SceneGraph.Node(children: [SceneGraph.Node(shape: .box(), material: material)]))
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = Archive(materialTypes: [PBRSceneMaterial.self])
    try archive.write(sceneGraph, to: url)
    let (loaded, _) = try archive.read(from: url)
    guard case let .mesh(_, materials, _, _) = try #require(loaded.root.children.first).content, let loadedMaterial = materials.first as? PBRSceneMaterial else {
        Issue.record("No PBR material")
        return
    }
    #expect(loadedMaterial.uniforms.subsurfaceColor == [1, 0.5, 0.25])
    #expect(loadedMaterial.uniforms.subsurfaceStrength == 0.75)
    #expect(loadedMaterial.uniforms.subsurfaceRadius == 0.4)
}
