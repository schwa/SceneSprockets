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

// #602: ambient light is a light node, like SCNLight's .ambient type.

@Test
func ambientLightsAreSummedAndKeptOutOfDirectLights() {
    let lights: [(worldTransform: simd_float4x4, light: Light)] = [
        (.identity, Light(type: .ambient, color: [1, 0, 0], intensity: 0.5)),
        (.identity, Light(type: .point, intensity: 2)),
        (.identity, Light(type: .ambient, color: [0, 1, 0], intensity: 0.25))
    ]
    var context = RenderContext(viewMatrix: .identity, projectionMatrix: .identity, cameraMatrix: .identity, lights: lights, revision: .init(structure: 0, transform: 0), environment: .init())
    context.lightCategoryBitMasks = [.max, .max, .max]
    #expect(context.ambientLight == [0.5, 0.25, 0])
    #expect(context.lightingLights(cameraPosition: .zero).count == 1)
}

// A quad facing the camera, its brightness from ambient light only.
@MainActor
private func centerBrightness(_ material: any SceneMaterial, renderer: any MaterialRenderer, ambient: Light?, ambientMask: UInt = .max) throws -> Int {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    // A directional light from behind the quad lights nothing on its front, but stops the default light.
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: .pi, axis: [0, 1, 0])), content: .light(Light(type: .directional, intensity: 1))))
    if let ambient {
        let node = root.addChild(SceneGraph.Node(content: .light(ambient)))
        node.lightCategoryBitMask = ambientMask
    }
    root.addChild(SceneGraph.Node(content: .mesh(MetalMesh(mesh: .quad(extents: [4, 4]), device: device), material: material)))
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [renderer])).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(8, 8, 1, 1), mipmapLevel: 0)
    return Int(value.x) + Int(value.y) + Int(value.z)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func ambientLightNodesLightEveryRenderer() throws {
    let ambient = Light(type: .ambient, color: [1, 1, 1], intensity: 0.5)
    let cases: [(String, any SceneMaterial, any MaterialRenderer)] = [
        ("Blinn-Phong", BlinnPhongSceneMaterial(color: [1, 1, 1]), BlinnPhongMaterialRenderer(ambientLightColor: .zero)),
        ("PBR", PBRSceneMaterial(baseColor: [1, 1, 1], roughness: 1), PBRMaterialRenderer(environmentIntensity: 0)),
        ("ShaderMaterial", ShaderMaterial.lit(color: [1, 1, 1]), ShaderMaterialRenderer())
    ]
    for (name, material, renderer) in cases {
        let dark = try centerBrightness(material, renderer: renderer, ambient: nil)
        let lit = try centerBrightness(material, renderer: renderer, ambient: ambient)
        // The quad is not in the ambient light's categories.
        let masked = try centerBrightness(material, renderer: renderer, ambient: ambient, ambientMask: 0b10)
        #expect(dark < 30, "\(name) dark \(dark)")
        #expect(lit > dark + 100, "\(name) dark \(dark) lit \(lit)")
        #expect(masked < 30, "\(name) masked \(masked)")
    }
}
