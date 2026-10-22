import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import SwiftMesh
import Testing
import simd
@testable import SceneSprocket
@testable import SceneSprocketShaderMaterial
@testable import SceneSprocketBlinnPhong

// #84: a quad at z = 0.5 (`near`) in front of one at z = 0 (`far`), seen from z = 3. Returns BGRA at `pixel`.
@MainActor
private func render(near: any SceneSprocket.Material, far: (any SceneSprocket.Material)?, farDrawsLast: Bool = false, pixel: (x: Int, y: Int) = (8, 8)) throws -> SIMD4<UInt8> {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let quad = SceneGraph.Shape.plane(width: 2, height: 2).metalMesh(device: device)
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 3]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40)))))
    if let far {
        let farNode = SceneGraph.Node(parent: root, content: .mesh(quad, material: far))
        farNode.renderingOrder = farDrawsLast ? 1 : -1
    }
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 0.5]), content: .mesh(quad, material: near))
    let renderers: [any SceneGraphMaterialRenderer] = [BlinnPhongMaterialRenderer(ambientLightColor: .zero), ShaderMaterialRenderer()]
    let texture = try OffscreenRenderer(size: CGSize(width: 16, height: 16)).render(SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: renderers)).texture
    var value = SIMD4<UInt8>.zero
    texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(pixel.x, pixel.y, 1, 1), mipmapLevel: 0)
    return value
}

private func glow(_ color: SIMD3<Float>, _ state: MaterialRenderState = .init(), opacity: Float = 1) -> BlinnPhongSceneMaterial {
    BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, opacity: opacity, emission: .color(color), renderState: state)
}

private func isHigh(_ value: UInt8) -> Bool { value > 200 }
private func isLow(_ value: UInt8) -> Bool { value < 20 }

@Test
@MainActor
func addBlendAddsColor() throws {
    let state = MaterialRenderState(blendMode: .add)
    #expect(glow([1, 0, 0], state).isTransparent)
    let value = try render(near: glow([1, 0, 0], state), far: glow([0, 0, 1]))
    #expect(isHigh(value.z) && isHigh(value.x) && isLow(value.y))
}

@Test
@MainActor
func multiplyBlendMultiplies() throws {
    // Yellow times magenta is red.
    let value = try render(near: glow([1, 1, 0], MaterialRenderState(blendMode: .multiply)), far: glow([1, 0, 1]))
    #expect(isHigh(value.z) && isLow(value.y) && isLow(value.x))
}

@Test
@MainActor
func replaceIgnoresOpacity() throws {
    let value = try render(near: glow([1, 0, 0], MaterialRenderState(blendMode: .replace), opacity: 0.5), far: glow([0, 0, 1]))
    #expect(isHigh(value.z) && isLow(value.x))
}

@Test
@MainActor
func depthReadAndWriteCanBeTurnedOff() throws {
    // The far quad draws last; normally the near one hides it.
    #expect(isLow(try render(near: glow([1, 0, 0]), far: glow([0, 0, 1]), farDrawsLast: true).x))
    // Not reading depth, it draws over the near quad.
    #expect(isHigh(try render(near: glow([1, 0, 0]), far: glow([0, 0, 1], MaterialRenderState(readsFromDepthBuffer: false)), farDrawsLast: true).x))
    // The near quad not writing depth has the same effect.
    #expect(isHigh(try render(near: glow([1, 0, 0], MaterialRenderState(writesToDepthBuffer: false)), far: glow([0, 0, 1]), farDrawsLast: true).x))
}

@Test
@MainActor
func colorWriteMaskKeepsOtherChannels() throws {
    // White writing only red over blue leaves magenta.
    let value = try render(near: glow([1, 1, 1], MaterialRenderState(colorWriteMask: .red)), far: glow([0, 0, 1]))
    #expect(isHigh(value.z) && isHigh(value.x) && isLow(value.y))
}

@Test
@MainActor
func linesFillModeDrawsEdgesOnly() throws {
    // Near the top middle, away from the quad's edges and its diagonal.
    let pixel = (x: 8, y: 3)
    #expect(isHigh(try render(near: glow([1, 1, 1]), far: nil, pixel: pixel).z))
    #expect(isLow(try render(near: glow([1, 1, 1], MaterialRenderState(fillMode: .lines)), far: nil, pixel: pixel).z))
}

@Test
@MainActor
func shaderMaterialUsesRenderState() throws {
    // Facing the camera, rim is the plain color.
    let near = try ShaderMaterial(vertexShader: ShaderMaterial.rim(color: [1, 0, 0, 1]).vertexShader, fragmentShader: ShaderMaterial.rim(color: [1, 0, 0, 1]).fragmentShader, parameters: ["color": .float4([1, 0, 0, 1])], renderState: MaterialRenderState(blendMode: .add))
    #expect(near.isTransparent)
    let value = try render(near: near, far: glow([0, 0, 1]))
    #expect(isHigh(value.z) && isHigh(value.x))
}
