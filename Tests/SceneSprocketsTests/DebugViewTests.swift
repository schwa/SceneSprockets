import GeometryLite3D
import Metal
import MetalSprockets
import simd
import SwiftMesh
import Testing
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong

// #132: debug views replace every mesh's material.
private func render(_ mode: SceneGraphDebugMode?, mesh: MetalMesh) throws -> SIMD4<UInt8> {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, transform: simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 4, 1])), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
    _ = SceneGraph.Node(parent: root, transform: simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [1, 1, 3, 1])), content: .light(Light(type: .point, intensity: 5)))
    _ = SceneGraph.Node(parent: root, content: .mesh(mesh, material: BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.9, 0.2, 0.2]), specular: .color(0), shininess: 1)))
    let element = SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], debugMode: mode)
    let texture = try OffscreenRenderer(size: CGSize(width: 64, height: 64)).render(element).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(32, 32, 1, 1), mipmapLevel: 0)
    return value
}

@Test
@MainActor
func debugModesReplaceMaterials() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = try render(nil, mesh: box)
    // Blinn-Phong red (BGRA).
    #expect(material.z > material.y)

    let shaded = try render(.shaded, mesh: box)
    #expect(shaded.x == shaded.y && shaded.y == shaded.z && shaded.x > 100)

    // The front face points at the camera (+Z), so its normal color is about (0.5, 0.5, 1): blue is largest.
    let normals = try render(.normals, mesh: box)
    #expect(normals.x > normals.y && normals.x > normals.z)

    var colors: Set<SIMD4<UInt8>> = []
    for mode in SceneGraphDebugMode.allCases where mode != .wireframe {
        colors.insert(try render(mode, mesh: box))
    }
    #expect(colors.count == SceneGraphDebugMode.allCases.count - 1)
}

@Test
func debugLayoutMapsAttributesBySemantic() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let layout = SceneGraphDebugRenderer.vertexLayout(box.vertexDescriptor)
    #expect(layout.hasNormals)
    let position = try #require(box.vertexDescriptor.attributes.first { $0.semantic == .position })
    #expect(layout.descriptor.attributes[0].format == position.format)
    #expect(layout.descriptor.attributes[0].offset == position.offset)
    #expect(layout.descriptor.attributes[3].format == .invalid)
}
