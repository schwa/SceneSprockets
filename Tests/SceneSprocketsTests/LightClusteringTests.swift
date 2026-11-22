import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsLighting
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import simd
import SwiftMesh
import Testing

// #519: clustered light assignment gives the same image as looping over every light.

@Test
func automaticClusteringNeedsManyLights() {
    #expect(!LightClustering.automatic.isEnabled(lightCount: LightClustering.automaticMinimumLightCount - 1))
    #expect(LightClustering.automatic.isEnabled(lightCount: LightClustering.automaticMinimumLightCount))
    #expect(LightClustering.on.isEnabled(lightCount: 1))
    #expect(!LightClustering.off.isEnabled(lightCount: 1_000))
}

// Cluster indices are into every light, so a batch lit by only some lights must not use them.
@Test
@MainActor
func batchesWithSomeLightsDropTheClusters() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let lights: [(worldTransform: simd_float4x4, light: Light)] = [(.identity, Light(type: .point, range: 2)), (.identity, Light(type: .point, range: 2))]
    var context = RenderContext(viewMatrix: .identity, projectionMatrix: PerspectiveProjection().projectionMatrix(aspectRatio: 1), cameraMatrix: .identity, lights: lights, revision: .init(structure: 0, transform: 0), environment: .init())
    context.lightCategoryBitMasks = [.max, 0b10]
    context.lightClusters = try context.makeLightClusters(clustering: .on, device: device)
    #expect(context.lightClusters != nil)
    func entry(categoryBitMask: UInt) -> SceneGraph.MeshEntry {
        let mesh = MetalMesh(mesh: .quad(extents: [1, 1]), device: device)
        let material = BlinnPhongSceneMaterial(color: [1, 1, 1])
        let node = SceneGraph.Node(content: .mesh(mesh, material: material))
        node.categoryBitMask = categoryBitMask
        return SceneGraph.MeshEntry(node: node, worldTransform: .identity, mesh: mesh, submeshIndex: 0, material: material, castsShadow: true, receivesShadow: true)
    }
    // Lit by both lights, then by only the first.
    let all = entry(categoryBitMask: 0b10)
    let some = entry(categoryBitMask: 0b01)
    let batches = renderBatches([all, some], context: context)
    #expect(batches.map { $0.context.lightClusters != nil } == [true, false])
}

// A floor seen at an angle, lit by a grid of colored short-range point lights, plus one directional light.
@MainActor
func makeManyLightsScene(material: any SceneMaterial, device: MTLDevice, lightsPerSide: Int = 8) -> SceneGraph {
    let root = SceneGraph.Node()
    let pitch = -atan2(Float(5), 7)
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 5, 7], rotation: simd_quatf(angle: pitch, axis: [1, 0, 0])), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(50))))))
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: -.pi / 3, axis: [1, 0, 0])), content: .light(Light(type: .directional, intensity: 0.1))))
    for row in 0 ..< lightsPerSide {
        for column in 0 ..< lightsPerSide {
            let x = (Float(column) / Float(lightsPerSide - 1) - 0.5) * 10
            let z = (Float(row) / Float(lightsPerSide - 1) - 0.5) * 10
            let color = SIMD3<Float>(column.isMultiple(of: 3) ? 1 : 0.2, row.isMultiple(of: 2) ? 1 : 0.3, (row + column) % 3 == 1 ? 1 : 0.2)
            root.addChild(SceneGraph.Node(transform: .init(translation: [x, 0.4, z]), content: .light(Light(type: .point, color: color, intensity: 2, range: 1.6))))
        }
    }
    root.addChild(SceneGraph.Node(transform: .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])), content: .mesh(MetalMesh(mesh: .quad(extents: [14, 14]), device: device), material: material)))
    return SceneGraph(root: root)
}

@MainActor
private func renderPixels(_ sceneGraph: SceneGraph, renderer: any MaterialRenderer, clustering: LightClustering, size: Int = 96) throws -> [SIMD4<UInt8>] {
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [renderer]).lightClustering(clustering)
    let texture = try OffscreenRenderer(size: CGSize(width: size, height: size)).render(element).texture
    var pixels = [SIMD4<UInt8>](repeating: .zero, count: size * size)
    texture.getBytes(&pixels, bytesPerRow: size * 4, from: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0)
    return pixels
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func clusteredLightingMatchesEveryLight() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let cases: [(String, any SceneMaterial, any MaterialRenderer)] = [
        ("Blinn-Phong", BlinnPhongSceneMaterial(color: [1, 1, 1]), BlinnPhongMaterialRenderer(ambientLightColor: .zero)),
        ("PBR", PBRSceneMaterial(baseColor: [1, 1, 1], roughness: 0.6), PBRMaterialRenderer(environmentIntensity: 0))
    ]
    for (name, material, renderer) in cases {
        let scene = makeManyLightsScene(material: material, device: device)
        let reference = try renderPixels(scene, renderer: renderer, clustering: .off)
        let clustered = try renderPixels(scene, renderer: renderer, clustering: .on)
        let litPixels = reference.filter { Int($0.x) + Int($0.y) + Int($0.z) > 150 }.count
        #expect(litPixels > reference.count / 20, "\(name): too few lit pixels (\(litPixels)) to compare")
        let differences = zip(reference, clustered).map { pair in
            let difference = SIMD4<Int>(truncatingIfNeeded: pair.0) &- SIMD4<Int>(truncatingIfNeeded: pair.1)
            return max(abs(difference.x), abs(difference.y), abs(difference.z))
        }
        let largestDifference = differences.max() ?? 0
        // Lights are summed in a different order, so a rounding step is allowed.
        #expect(largestDifference <= 2, "\(name): clustered image differs by \(largestDifference)")
    }
}
