import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsPBR
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

// #123: a smooth glass quad in front of an emissive green quad, or nothing. Returns the center pixel (BGRA).
// `blinnPhong` (#129) makes the green quad Blinn-Phong instead of PBR.
@MainActor
private func glass(behind: Bool, blinnPhong: Bool = false) throws -> SIMD4<UInt8> {
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh()
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    let glass = try PBRSceneMaterial(baseColor: [1, 1, 1, 1], roughness: 0)
    glass.pbrMaterial.uniforms.transmissionFactor = 1
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: glass))
    if behind, blinnPhong {
        let green = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0, 1, 0]))
        _ = SceneGraph.Node(parent: root, content: .mesh(quad, material: green))
    } else if behind {
        let green = try PBRSceneMaterial(baseColor: [0, 0, 0, 1])
        green.pbrMaterial.uniforms.emissiveFactor = [0, 1, 0]
        _ = SceneGraph.Node(parent: root, content: .mesh(quad, material: green))
    }
    let graph = SceneGraph(root: root)
    let element = SceneGraphElement(sceneGraph: graph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero), PBRMaterialRenderer()])
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

// #130: a white quad behind glass, lit by a red light whose mask includes the quad or not. Returns the center
// pixel (BGRA).
@MainActor
private func glassOverLitQuad(lightReachesQuad: Bool) throws -> SIMD4<UInt8> {
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh()
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    let glass = try PBRSceneMaterial(baseColor: [1, 1, 1, 1], roughness: 0)
    glass.pbrMaterial.uniforms.transmissionFactor = 1
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: glass))
    let quadNode = SceneGraph.Node(parent: root, content: .mesh(quad, material: try PBRSceneMaterial(baseColor: [1, 1, 1, 1], roughness: 1)))
    quadNode.categoryBitMask = 2
    let light = SceneGraph.Node(parent: root, content: .light(Light(type: .directional, color: [1, 0, 0], intensity: 10)))
    // Never the glass (mask 1), whose smooth surface would reflect the light straight at the camera.
    light.lightCategoryBitMask = lightReachesQuad ? 2 : 4
    let renderer = PBRMaterialRenderer(environmentIntensity: 0)
    let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [renderer])
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return value
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func lightMasksApplyBehindGlass() throws {
    let lit = try glassOverLitQuad(lightReachesQuad: true)
    let masked = try glassOverLitQuad(lightReachesQuad: false)
    #expect(Int(lit.z) > 60)
    #expect(Int(masked.z) < Int(lit.z) / 4)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func glassShowsBlinnPhongBehindIt() throws {
    let empty = try glass(behind: false)
    let green = try glass(behind: true, blinnPhong: true)
    #expect(Int(green.y) > Int(empty.y) + 60)
    #expect(Int(green.y) > Int(green.x) + 60)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func glassShowsTheSceneBehindIt() throws {
    let empty = try glass(behind: false)
    let green = try glass(behind: true)
    #expect(Int(green.y) > Int(empty.y) + 60)
    #expect(Int(green.y) > Int(green.x) + 60)
}
