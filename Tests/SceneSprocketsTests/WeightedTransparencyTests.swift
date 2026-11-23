import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import MetalSprocketsPBR
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

// #494: weighted blended order-independent transparency.
private let size = CGSize(width: 32, height: 32)

// Two half-transparent planes, red in front of blue, over a white background. `wrongOrder` forces the near plane to
// draw first, which sorted blending gets wrong.
@MainActor
private func render(pbr: Bool, orderIndependent: Bool, wrongOrder: Bool) throws -> SIMD4<UInt8> {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(30))))))
    func material(_ color: SIMD3<Float>) -> any SceneMaterial {
        if pbr {
            let material = PBRSceneMaterial(baseColor: color, opacity: 0.5, roughness: 1)
            material.pbrMaterial = material.pbrMaterial.with(uniforms: {
                var uniforms = material.pbrMaterial.uniforms
                uniforms.unlit = 1
                return uniforms
            }())
            return material
        }
        return BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, opacity: 0.5, emission: .color(color))
    }
    let near = root.addChild(SceneGraph.Node(shape: .plane(width: 4, height: 4), material: material([1, 0, 0]), transform: .init(translation: [0, 0, 0.5])))
    let far = root.addChild(SceneGraph.Node(shape: .plane(width: 4, height: 4), material: material([0, 0, 1])))
    if wrongOrder {
        near.renderingOrder = 0
        far.renderingOrder = 1
    }
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.background = .color([1, 1, 1, 1])
    sceneGraph.environment.orderIndependentTransparency = orderIndependent
    sceneGraph.environment.toneMapping = .none
    let renderer = try OffscreenRenderer(size: size, colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer(environmentIntensity: 0), BlinnPhongMaterialRenderer()])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    let isBGRA = texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb
    return isBGRA ? SIMD4(value.z, value.y, value.x, value.w) : value
}

private func distance(_ lhs: SIMD4<UInt8>, _ rhs: SIMD4<UInt8>) -> Int {
    (0..<3).map { abs(Int(lhs[$0]) - Int(rhs[$0])) }.max() ?? 0
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: [false, true])
@MainActor
func weightedTransparencyIgnoresDrawOrder(pbr: Bool) throws {
    // Sorted blending depends on the order: the forced wrong order puts blue over red.
    let sorted = try render(pbr: pbr, orderIndependent: false, wrongOrder: false)
    let sortedWrong = try render(pbr: pbr, orderIndependent: false, wrongOrder: true)
    #expect(distance(sorted, sortedWrong) > 20, "sorted \(sorted) vs wrong order \(sortedWrong)")

    let weighted = try render(pbr: pbr, orderIndependent: true, wrongOrder: false)
    let weightedWrong = try render(pbr: pbr, orderIndependent: true, wrongOrder: true)
    #expect(distance(weighted, weightedWrong) <= 2, "weighted \(weighted) vs wrong order \(weightedWrong)")
    // Both layers and the white background show through (each layer at alpha 0.5 lets a quarter through).
    #expect(weighted.x > weighted.y + 40 && weighted.z > weighted.y + 40, "\(weighted)")
    #expect(weighted.y > 20, "\(weighted)")
}

@Test
func orderIndependentTransparencyIsArchived() throws {
    var environment = SceneGraph.Environment()
    environment.orderIndependentTransparency = true
    let decoded = try JSONDecoder().decode(SceneGraph.Environment.self, from: JSONEncoder().encode(environment))
    #expect(decoded.orderIndependentTransparency)
}
