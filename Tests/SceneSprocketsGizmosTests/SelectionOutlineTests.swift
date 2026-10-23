import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import Testing
import simd
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
@testable import SceneSprocketsGizmos

// #172
@MainActor
struct SelectionOutlineTests {
    let viewport = SceneViewport(
        cameraMatrix: LookAt(position: [0, 0, 10], target: .zero, up: [0, 1, 0]).cameraMatrix,
        projectionMatrix: PerspectiveProjection(verticalAngleOfView: .degrees(40), depthMode: .standard(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1),
        viewSize: [400, 400],
        drawableSize: [400, 400]
    )

    // Green outline around a 2x2 box at the origin, with a wide bar in front of its middle. Returns BGRA pixels.
    func render(xray: Bool) throws -> [UInt8] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let root = SceneGraph.Node()
        let camera = SceneGraph.Node(parent: root, content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40), depthMode: .standard(zClip: 0.1 ... 100)))))
        camera.transform = viewport.cameraMatrix
        let material = BlinnPhongSceneMaterial(ambient: .color(1), diffuse: .color(0.2), specular: .color(0), shininess: 1)
        let selected = SceneGraph.Node(parent: root, shape: .box(width: 2, height: 2, length: 1), material: material, device: device)
        _ = SceneGraph.Node(parent: root, shape: .box(width: 6, height: 0.5, length: 0.5), material: material, device: device, trs: .init(translation: [0, 0, 3]))
        let sceneGraph = SceneGraph(root: root)
        let outline = SelectionOutline(color: [0, 1, 0, 1], width: 6)
        outline.xray = xray
        let element = try #require(try outline.element(nodes: [selected], sceneGraph: sceneGraph, viewport: viewport))
        let renderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400), clearDepth: 0)
        let texture = try renderer.render(try MetalSprockets.Group {
            SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()], storesDepth: true)
            element
        }).texture
        var pixels = [UInt8](repeating: 0, count: 400 * 400 * 4)
        texture.getBytes(&pixels, bytesPerRow: 1_600, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
        return pixels
    }

    // 3 pixels outside the box's left edge (y = 0 is behind the bar, y = 0.8 is not).
    func pixel(_ pixels: [UInt8], leftOfEdgeAtY y: Float) throws -> ArraySlice<UInt8> {
        let point = try #require(viewport.project([-1, y, 0.5])).xy
        let offset = (Int(point.y) * 400 + Int(point.x) - 3) * 4
        return pixels[offset ..< offset + 4]
    }

    func isOutline(_ pixel: ArraySlice<UInt8>) -> Bool {
        let bgra = Array(pixel)
        return bgra[1] > 200 && bgra[2] < 80
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func objectsInFrontHideTheOutline() throws {
        let pixels = try render(xray: false)
        let visible = try pixel(pixels, leftOfEdgeAtY: 0.8)
        let hidden = try pixel(pixels, leftOfEdgeAtY: 0)
        #expect(isOutline(visible), "\(visible)")
        #expect(!isOutline(hidden), "\(hidden)")
    }

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func xrayDrawsOverEverything() throws {
        let pixels = try render(xray: true)
        let behindBar = try pixel(pixels, leftOfEdgeAtY: 0)
        #expect(isOutline(behindBar), "\(behindBar)")
    }
}
