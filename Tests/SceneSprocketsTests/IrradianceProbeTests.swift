import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsLighting
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import Testing

// #532: irradiance probe volumes.

@Test
func irradianceSHEvaluatesConstantAndDirection() {
    // Red light from above (+Y): constant plus a y term.
    let sh = IrradianceSH(red: [0.5, 0.5, 0, 0], green: .zero, blue: .zero)
    #expect(simd_distance(sh.evaluate(normal: [0, 1, 0]), [1, 0, 0]) < 1e-5)
    #expect(simd_distance(sh.evaluate(normal: [0, -1, 0]), [0, 0, 0]) < 1e-5)
    #expect(simd_distance(sh.evaluate(normal: [1, 0, 0]), [0.5, 0, 0]) < 1e-5)
}

@Test
func probeVolumeBlendsTrilinearly() throws {
    // Two probes along x: 0 on the left, 1 on the right.
    let left = IrradianceSH(red: [0, 0, 0, 0], green: .zero, blue: .zero)
    let right = IrradianceSH(red: [1, 0, 0, 0], green: .zero, blue: .zero)
    let volume = SceneGraph.ProbeVolume(resolution: [2, 1, 1], coefficients: [left, right])
    #expect(try #require(volume.irradiance(atLocal: [0, 0, 0])).red.x == 0.5)
    #expect(try #require(volume.irradiance(atLocal: [-0.25, 0, 0])).red.x == 0)
    #expect(try #require(volume.irradiance(atLocal: [0.4, 0, 0])).red.x == 1)
    #expect(volume.irradiance(atLocal: [0.6, 0, 0]) == nil)
    #expect(SceneGraph.ProbeVolume(resolution: [2, 1, 1]).irradiance(atLocal: .zero) == nil)
}

// A glowing red floor below and a glowing blue ceiling above a probe volume, with nothing else lighting the scene.
@MainActor
private func makeRoom() -> (SceneGraph, probes: SceneGraph.Node) {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 4]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    func glow(_ color: SIMD3<Float>) -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color))
    }
    root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 20, height: 0.1, length: 20), material: glow([1, 0, 0]), transform: .init(translation: [0, -2, 0])))
    root.addChild(SceneGraph.Node(label: "Ceiling", shape: .box(width: 20, height: 0.1, length: 20), material: glow([0, 0, 1]), transform: .init(translation: [0, 2, 0])))
    let probes = root.addChild(SceneGraph.Node(label: "Probes", transform: .init(scale: [3, 3, 3])))
    probes.probeVolume = SceneGraph.ProbeVolume(resolution: [2, 2, 2])
    var sceneGraph = SceneGraph(linearRoot: root)
    sceneGraph.environment.intensity = 0
    return (sceneGraph, probes)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func captureSeesRedBelowAndBlueAbove() throws {
    let (sceneGraph, probes) = makeRoom()
    try SceneGraph.ProbeVolume.capture(sceneGraph: sceneGraph, node: probes, renderers: [BlinnPhongMaterialRenderer()], faceSize: 16)
    let volume = try #require(probes.probeVolume)
    #expect(volume.coefficients.count == 8)
    let sh = try #require(volume.irradiance(atLocal: .zero))
    let up = sh.evaluate(normal: [0, 1, 0])
    let down = sh.evaluate(normal: [0, -1, 0])
    #expect(up.z > up.x + 0.2, "up \(up)")
    #expect(down.x > down.z + 0.2, "down \(down)")
}

// A white sphere in the volume is lit blue from above and red from below by the probes alone.
@Test(.enabled(if: deviceSupportsMetal4), arguments: ["Blinn-Phong", "PBR"])
@MainActor
func probesLightObjectsInside(rendererName: String) throws {
    let (sceneGraph, probes) = makeRoom()
    let blinnPhong = BlinnPhongMaterialRenderer()
    try SceneGraph.ProbeVolume.capture(sceneGraph: sceneGraph, node: probes, renderers: [blinnPhong], faceSize: 16)
    let isPBR = rendererName == "PBR"
    let white: any SceneMaterial = isPBR ? PBRSceneMaterial(baseColor: [1, 1, 1], roughness: 1) : BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(1), specular: .color(0), shininess: 1)
    let sphere = sceneGraph.root.addChild(SceneGraph.Node(label: "Sphere", shape: .sphere(radius: 0.8), material: white))
    let renderers: [any MaterialRenderer] = [blinnPhong, PBRMaterialRenderer(environmentIntensity: 0)]
    func pixels() throws -> [SIMD4<UInt8>] {
        let size = 64
        let texture = try OffscreenRenderer(size: CGSize(width: size, height: size)).render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: renderers)).texture
        var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
        texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
        let isBGRA = texture.pixelFormat == .bgra8Unorm || texture.pixelFormat == .bgra8Unorm_srgb
        return isBGRA ? pixels.map { SIMD4($0.z, $0.y, $0.x, $0.w) } : pixels
    }
    let lit = try pixels()
    let top = lit[22 * 64 + 32]
    let bottom = lit[42 * 64 + 32]
    #expect(Int(top.z) > Int(top.x) + 20, "top \(top)")
    #expect(Int(bottom.x) > Int(bottom.z) + 20, "bottom \(bottom)")

    // Without probes the sphere gets no light at all.
    probes.probeVolume = nil
    let unlit = try pixels()[22 * 64 + 32]
    #expect(Int(unlit.x) + Int(unlit.z) < 10, "unlit \(unlit)")
    _ = sphere
}

@Test
@MainActor
func probeVolumeIsArchived() throws {
    let node = SceneGraph.Node()
    node.probeVolume = SceneGraph.ProbeVolume(resolution: [2, 1, 1], coefficients: [IrradianceSH(red: [1, 2, 3, 4], green: .zero, blue: .zero), .zero])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(Archive.pathExtension)
    defer { try? FileManager.default.removeItem(at: url) }
    let archive = Archive(materialTypes: [])
    try archive.write(SceneGraph(linearRoot: SceneGraph.Node(children: [node])), to: url)
    let (loaded, _) = try archive.read(from: url)
    #expect(loaded.root.children.first?.probeVolume == node.probeVolume)
}
