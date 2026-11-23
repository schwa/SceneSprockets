import CoreGraphics
import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import Testing

// #510: view-space normals and screen-space velocity from the G-buffer pre-pass.
private let size = 64

// Copies a private texture's pixel into shared memory as Float16 values.
private func read(_ texture: MTLTexture, x: Int, y: Int, components: Int) throws -> [Float] {
    let device = texture.device
    let bytesPerPixel = components * 2
    let buffer = try #require(device.makeBuffer(length: bytesPerPixel, options: .storageModeShared))
    let queue = try #require(device.makeCommandQueue())
    let commandBuffer = try #require(queue.makeCommandBuffer())
    let blit = try #require(commandBuffer.makeBlitCommandEncoder())
    blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: x, y: y, z: 0), sourceSize: MTLSize(width: 1, height: 1, depth: 1), to: buffer, destinationOffset: 0, destinationBytesPerRow: bytesPerPixel, destinationBytesPerImage: bytesPerPixel)
    blit.endEncoding()
    commandBuffer.commit()
    commandBuffer.waitUntilCompleted()
    let values = buffer.contents().bindMemory(to: Float16.self, capacity: components)
    return (0..<components).map { Float(values[$0]) }
}

@MainActor
private func makeScene() -> (SceneGraph, SceneGraph.Node) {
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40))))))
    let sphere = root.addChild(SceneGraph.Node(shape: .sphere(radius: 1), material: BlinnPhongSceneMaterial(ambient: .color(0.5), diffuse: .color(0.5), specular: .color(0), shininess: 1)))
    return (SceneGraph(linearRoot: root), sphere)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func gBufferHasViewSpaceNormalsAndVelocity() throws {
    let (sceneGraph, sphere) = makeScene()
    let gBuffer = GBuffer()
    let renderer = try OffscreenRenderer(size: CGSize(width: size, height: size), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
    func render() throws {
        _ = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()]).gBuffer(gBuffer))
    }
    try render()
    let normals = try #require(gBuffer.normals)
    let velocity = try #require(gBuffer.velocity)
    // The middle of the sphere faces the camera; its right side faces +X; the background is empty.
    let center = try read(normals, x: size / 2, y: size / 2, components: 4)
    #expect(center[2] > 0.95 && center[3] == 1, "\(center)")
    let right = try read(normals, x: size / 2 + 12, y: size / 2, components: 4)
    #expect(right[0] > 0.5, "\(right)")
    #expect(try read(normals, x: 1, y: 1, components: 4)[3] == 0)
    // Nothing has moved yet.
    let still = try read(velocity, x: size / 2, y: size / 2, components: 2)
    #expect(abs(still[0]) < 1e-3 && abs(still[1]) < 1e-3, "\(still)")

    // Moved right by 0.2: each pixel of the sphere moved right in texture coordinates.
    sphere.transform.translation.x = 0.2
    try render()
    let moved = try read(velocity, x: size / 2, y: size / 2, components: 2)
    #expect(moved[0] > 0.01 && abs(moved[1]) < 1e-3, "\(moved)")
}

// Without a G-buffer the pre-pass does not run and the context has none.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func gBufferIsOffByDefault() throws {
    let (sceneGraph, _) = makeScene()
    var seen: GBuffer?
    let element = SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])
        .renderStage(.afterOpaque) { context, _ in
            seen = context.gBuffer
            return nil
        }
    _ = try OffscreenRenderer(size: CGSize(width: size, height: size), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage).render(element)
    #expect(seen == nil)
}
