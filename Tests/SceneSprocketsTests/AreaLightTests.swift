import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsPBR
import simd
import Testing

// #509: rectangular area lights in PBR.
private let size = CGSize(width: 64, height: 64)

// A rough gray floor seen from above, with an area light `height` above its middle, facing down (or up).
@MainActor
private func floorBrightness(areaSize: SIMD2<Float>, facesDown: Bool = true, roughness: Float = 1, metallic: Float = 0, pixel: SIMD2<Int> = [32, 32]) throws -> Int {
    let root = SceneGraph.Node()
    let lookDown = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 4, 0], rotation: lookDown), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60))))))
    var light = Light(type: .area, intensity: 3)
    light.areaSize = areaSize
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 1, 0], rotation: facesDown ? lookDown : simd_quatf(angle: .pi / 2, axis: [1, 0, 0])), content: .light(light)))
    root.addChild(SceneGraph.Node(shape: .plane(width: 20, height: 20), material: PBRSceneMaterial(baseColor: [0.5, 0.5, 0.5], metallic: metallic, roughness: roughness), transform: .init(rotation: lookDown)))
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.intensity = 0
    let renderer = try OffscreenRenderer(size: size)
    let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [PBRMaterialRenderer(environmentIntensity: 0)])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(pixel.x, pixel.y, 1, 1), mipmapLevel: 0)
    return Int(value.x) + Int(value.y) + Int(value.z)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func areaLightLightsWhatItFaces() throws {
    let lit = try floorBrightness(areaSize: [1, 1])
    #expect(lit > 60, "\(lit)")
    // Facing away from the floor: nothing.
    #expect(try floorBrightness(areaSize: [1, 1], facesDown: false) < 5)
    // A larger rectangle of the same brightness gives more light.
    #expect(try floorBrightness(areaSize: [3, 3]) > lit + 30)
    // Light falls off away from the rectangle.
    #expect(try floorBrightness(areaSize: [1, 1], pixel: [4, 32]) < lit / 2)
}

// A smooth metal floor mirrors the rectangle: bright under it, dark just outside its reflection.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func areaLightHasSharpSpecularOnSmoothSurfaces() throws {
    let inside = try floorBrightness(areaSize: [1, 1], roughness: 0.1, metallic: 1)
    let outside = try floorBrightness(areaSize: [1, 1], roughness: 0.1, metallic: 1, pixel: [32, 12])
    #expect(inside > 150, "\(inside)")
    #expect(outside < inside / 3, "\(outside) vs \(inside)")
}

@Test
func areaLightSizeIsArchived() throws {
    var light = Light(type: .area, range: 5)
    light.areaSize = [2, 0.5]
    #expect(try JSONDecoder().decode(Light.self, from: JSONEncoder().encode(light)) == light)
}
