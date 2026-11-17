import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import SwiftMesh
import Testing

// #409: scene-wide techniques must affect Blinn-Phong and PBR meshes the same way. Each test renders one red plane that
// fills the view, once per material family, and checks the effect of one technique on the center pixel. The table of
// techniques is Sources/SceneSprockets/Documentation.docc/MaterialParity.md.

enum MaterialFamily: String, CaseIterable, CustomTestStringConvertible {
    case blinnPhong
    case pbr

    var testDescription: String { rawValue }

    func material(opacity: Float = 1) -> any SceneMaterial {
        switch self {
        case .blinnPhong:
            BlinnPhongSceneMaterial(ambient: .color([0.8, 0.1, 0.1]), diffuse: .color([0.8, 0.1, 0.1]), specular: .color(0), shininess: 1, opacity: opacity)
        case .pbr:
            PBRSceneMaterial(baseColor: [0.8, 0.1, 0.1], opacity: opacity, metallic: 0, roughness: 0.8)
        }
    }

    var renderer: any MaterialRenderer {
        switch self {
        case .blinnPhong:
            BlinnPhongMaterialRenderer(ambientLightColor: [1, 1, 1])
        case .pbr:
            PBRMaterialRenderer()
        }
    }
}

private struct ParityScene {
    var family: MaterialFamily
    var opacity: Float = 1
    var isVisible = true
    var fog: SceneGraph.Fog?
    var postProcessing: SceneGraph.PostProcessing?
    var debugMode: DebugMode?
    // A morph target that moves the plane this far along x, at weight 1.
    var morphOffset: Float?

    @MainActor
    func centerPixel() throws -> SIMD4<UInt8> {
        let root = SceneGraph.Node()
        root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
        root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .light(Light(type: .point, intensity: 10))))
        let mesh = SceneGraph.Shape.plane(width: 4, height: 4).metalMesh()
        let plane = root.addChild(SceneGraph.Node(content: .mesh(mesh, material: family.material(opacity: opacity))))
        plane.isVisible = isVisible
        if let morphOffset {
            plane.morphTargets = [SceneGraph.MorphTarget(positionDeltas: Array(repeating: [morphOffset, 0, 0], count: mesh.vertexCount))]
            plane.morphWeights = [1]
        }
        let sceneGraph = SceneGraph(root: root)
        sceneGraph.fog = fog
        sceneGraph.postProcessing = postProcessing
        let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [family.renderer], debugMode: debugMode)
        let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
        let texture = try renderer.render(element).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
        return value
    }
}

// BGRA: red is `z`.
private func isRed(_ value: SIMD4<UInt8>) -> Bool {
    Int(value.z) > Int(value.x) + 40 && Int(value.z) > Int(value.y) + 40
}

private func isBlack(_ value: SIMD4<UInt8>) -> Bool {
    value.x < 4 && value.y < 4 && value.z < 4
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialFamily.allCases)
@MainActor
func parityBaselineDrawsRed(_ family: MaterialFamily) throws {
    #expect(isRed(try ParityScene(family: family).centerPixel()))
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialFamily.allCases)
@MainActor
func parityHiddenNodeIsNotDrawn(_ family: MaterialFamily) throws {
    #expect(isBlack(try ParityScene(family: family, isVisible: false).centerPixel()))
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialFamily.allCases)
@MainActor
func parityMaterialOpacityBlendsWithTheBackground(_ family: MaterialFamily) throws {
    let opaque = try ParityScene(family: family).centerPixel()
    let half = try ParityScene(family: family, opacity: 0.5).centerPixel()
    let none = try ParityScene(family: family, opacity: 0).centerPixel()
    #expect(half.z < opaque.z && half.z > 10, "opaque \(opaque) half \(half)")
    #expect(isBlack(none), "\(none)")
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialFamily.allCases)
@MainActor
func parityFullFogReplacesTheColor(_ family: MaterialFamily) throws {
    let fog = SceneGraph.Fog(color: [0, 1, 0, 1], startDistance: 0, endDistance: 0.5)
    let value = try ParityScene(family: family, fog: fog).centerPixel()
    #expect(value.y > 240 && value.z < 15 && value.x < 15, "\(value)")
}

@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialFamily.allCases)
@MainActor
func parityZeroSaturationMakesGrey(_ family: MaterialFamily) throws {
    let value = try ParityScene(family: family, postProcessing: SceneGraph.PostProcessing(saturation: 0)).centerPixel()
    #expect(abs(Int(value.z) - Int(value.y)) < 4 && abs(Int(value.y) - Int(value.x)) < 4 && value.z > 10, "\(value)")
}

// A debug view replaces the material, so both families give exactly the same color.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func parityDebugViewsMatch() throws {
    for mode in DebugMode.allCases {
        let blinnPhong = try ParityScene(family: .blinnPhong, debugMode: mode).centerPixel()
        let pbr = try ParityScene(family: .pbr, debugMode: mode).centerPixel()
        #expect(blinnPhong == pbr, "\(mode): \(blinnPhong) vs \(pbr)")
    }
}

// Morph targets move the drawn vertices: the plane leaves the center of the view.
@Test(.enabled(if: deviceSupportsMetal4), arguments: MaterialFamily.allCases)
@MainActor
func parityMorphTargetsMoveTheMesh(_ family: MaterialFamily) throws {
    #expect(isBlack(try ParityScene(family: family, morphOffset: 10).centerPixel()))
}
