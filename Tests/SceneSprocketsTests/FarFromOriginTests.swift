import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

// #257: shadows, the screen-space shadow mask, fog and culling far from the world origin.

private func pose(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float> = [0, 1, 0]) -> simd_float4x4 {
    let forward = simd_normalize(eye - target)
    let right = simd_normalize(simd_cross(up, forward))
    return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(simd_cross(forward, right), 0), SIMD4(forward, 0), SIMD4(eye, 1)))
}

// A floor, a floating box shadowing it, a directional light and fog; all under a parent at `offset`.
@MainActor
private func render(offset: SIMD3<Float>, kind: MaterialKind) throws -> [SIMD4<UInt8>] {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material: any SceneSprockets.Material = switch kind {
    case .shaderMaterial: try ShaderMaterial.rim(color: [0.8, 0.8, 0.8, 1])
    case .blinnPhong: BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.7), specular: .color(0), shininess: 1)
    case .pbr: try PBRSceneMaterial(baseColor: [0.8, 0.8, 0.8, 1], metallic: 0, roughness: 0.3)
    }
    let root = SceneGraph.Node()
    let world = SceneGraph.Node(parent: root, trs: .init(translation: offset))
    _ = SceneGraph.Node(parent: world, transform: pose(eye: [0, 3, 3], target: .zero), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60)))))
    _ = SceneGraph.Node(parent: world, transform: pose(eye: .zero, target: [-0.5, -1, -0.2]), content: .light(Light(type: .directional)))
    _ = SceneGraph.Node(parent: world, trs: .init(translation: [0, -0.05, 0], scale: [4, 0.1, 4]), content: .mesh(box, material: material))
    _ = SceneGraph.Node(parent: world, trs: .init(translation: [0, 0.75, 0], scale: [0.5, 0.5, 0.5]), content: .mesh(box, material: material))
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.fog = SceneGraph.Fog(color: [0.3, 0.4, 0.9, 1], startDistance: 2, endDistance: 7)
    let size = 64
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
    let renderers: [any SceneGraphMaterialRenderer] = [BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1]), ShaderMaterialRenderer(), PBRMaterialRenderer()]
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers, shadows: SceneGraphShadows(intensity: 0.8))
    let texture = try renderer.render(element).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    return pixels
}

enum MaterialKind: CaseIterable, Sendable {
    case blinnPhong, shaderMaterial, pbr
}

// #257, #254.
@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialKind.allCases)
@MainActor
func shadowsAndFogMatchFarFromOrigin(kind: MaterialKind) throws {
    let near = try render(offset: .zero, kind: kind)
    // 2^20 m: Float spacing 0.125 m. Exact in Float, so only the renderer's math can differ.
    let far = try render(offset: [1_048_576, 0, 1_048_576], kind: kind)
    let differences = zip(near, far).map { a, b in
        (0..<3).map { abs(Int(a[$0]) - Int(b[$0])) }.max() ?? 0
    }
    let badPixels = differences.filter { $0 > 8 }.count
    // A few edge pixels may round differently.
    #expect(badPixels <= near.count / 200, "\(badPixels) pixels differ by more than 8, max \(differences.max() ?? 0)")
}

// Culling: a small mesh just inside the view's edge, near a camera far from the origin, must not be culled.
@Test
func cullingKeepsMeshesNearTheEdgeFarFromOrigin() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let offset = SIMD3<Float>(1_048_576, 0, 1_048_576)
    let root = SceneGraph.Node()
    let camera = SceneGraph.Node(parent: root, trs: .init(translation: offset), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(90)))))
    // 90° frustum: at distance d the right edge is x = d. Each 2 cm box sits 1 cm inside the edge, at distances out
    // to 50 m.
    let mesh = MetalMesh(mesh: .box(extents: [0.02, 0.02, 0.02]), device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color(1), diffuse: .color(0), specular: .color(0), shininess: 1)
    for distance in stride(from: Float(1), through: 50, by: 1) {
        _ = SceneGraph.Node(parent: root, trs: .init(translation: offset + [distance - 0.02, 0, -distance]), content: .mesh(mesh, material: material))
    }
    let sceneGraph = SceneGraph(root: root)
    let context = try #require(makeRenderContext(sceneGraph: sceneGraph, camera: camera, cameraMatrix: nil, aspectRatio: 1))
    let entries = sceneGraph.meshEntries()
    let visible = meshEntriesInFrustum(entries, projectionMatrix: context.projectionMatrix, cameraMatrix: context.cameraMatrix)
    #expect(visible.allSatisfy { $0 }, "culled: \(visible.indices.filter { !visible[$0] }.map { $0 + 1 })")
}
