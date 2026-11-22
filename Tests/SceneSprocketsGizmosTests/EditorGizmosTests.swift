import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
@testable import SceneSprocketsGizmos
import simd
import Testing

// #406: grid, axes, light and camera icons, and bounds.
@MainActor
struct EditorGizmosTests {
    let camera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60)))
    var viewport: Viewport {
        Viewport(cameraMatrix: LookAt(position: [0, 8, 8], target: .zero, up: [0, 1, 0]).cameraMatrix, camera: camera, viewSize: [200, 200], drawableSize: [200, 200])
    }

    @Test
    func shapesForEachOption() throws {
        let root = SceneGraph.Node()
        let light = root.addChild(.light(.point(intensity: 1), transform: .init(translation: [2, 3, 0])))
        root.addChild(.camera(.default, transform: .init(translation: [-2, 1, 4])))
        let box = root.addChild(SceneGraph.Node(shape: .box(width: 2, height: 1, length: 1), material: BlinnPhongSceneMaterial(color: [1, 1, 1]), transform: .init(translation: [0, 0.5, 0])))
        let graph = SceneGraph(root: root)

        #expect(EditorGizmos.shapes(sceneGraph: graph, viewport: viewport, options: []).isEmpty)
        let grid = EditorGizmos.shapes(sceneGraph: graph, viewport: viewport, options: .grid)
        // 21 lines each way, all on y = 0.
        #expect(grid.first?.lines.count == 42)
        #expect(grid.flatMap(\.lines).flatMap(\.self).allSatisfy { $0.y == 0 })
        #expect(EditorGizmos.shapes(sceneGraph: graph, viewport: viewport, options: .axes).count == 3)
        let icons = EditorGizmos.shapes(sceneGraph: graph, viewport: viewport, options: .lightsAndCameras)
        #expect(icons.count == 2 && icons.allSatisfy(\.isOverlay))
        // Bounds only for selected nodes, in world space around the box.
        #expect(EditorGizmos.shapes(sceneGraph: graph, viewport: viewport, options: .bounds).isEmpty)
        let bounds = try #require(EditorGizmos.shapes(sceneGraph: graph, viewport: viewport, options: .bounds, selected: [box.id]).first)
        let points = bounds.lines.flatMap(\.self)
        #expect(points.allSatisfy { abs($0.x) <= 1.001 && $0.y >= -0.001 && $0.y <= 1.001 && abs($0.z) <= 0.501 })
        #expect(bounds.lines.count == 6)

        // Clicking on the light's icon picks it; empty space picks nothing.
        let lightIcon = try #require(icons.first { $0.node === light })
        let onIcon = try #require(viewport.project(lightIcon.lines[0][0]))
        #expect(EditorGizmos.hitTest(SIMD2(onIcon.x, onIcon.y), sceneGraph: graph, viewport: viewport) === light)
        #expect(EditorGizmos.hitTest([2, 2], sceneGraph: graph, viewport: viewport) == nil)
    }

    // The grid draws, and scene geometry in front of it hides it.
    @Test(.enabled(if: deviceSupportsMetal4))
    func gridDrawsBehindGeometry() throws {
        func render(withBox: Bool) throws -> (center: SIMD4<UInt8>, gridPixels: Int) {
            let root = SceneGraph.Node()
            root.addChild(SceneGraph.Node(transform: Transform3D(storing: viewport.cameraMatrix), content: .camera(camera)))
            if withBox {
                root.addChild(SceneGraph.Node(shape: .box(width: 3, height: 3, length: 3), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0, 0, 1]))))
            }
            let graph = SceneGraph(root: root)
            let viewport = self.viewport
            let element = SceneGraphElement(sceneGraph: graph, aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer(ambientLightColor: .zero)]) { _ in
                try EditorGizmos.element(sceneGraph: graph, viewport: viewport, options: [.grid])
            }
            let texture = try OffscreenRenderer(size: CGSize(width: 200, height: 200)).render(element).texture
            var pixels = [SIMD4<UInt8>](repeating: .zero, count: 200 * 200)
            texture.getBytes(&pixels, bytesPerRow: 800, from: MTLRegionMake2D(0, 0, 200, 200), mipmapLevel: 0)
            // BGRA: grid lines have red and green lit; the box is pure blue. The upper middle of the view is where
            // the box stands, and only grid lines behind it could appear there.
            var behindBox = 0
            for row in 72..<100 {
                for column in 82..<118 where pixels[row * 200 + column].y > 40 && pixels[row * 200 + column].z > 40 {
                    behindBox += 1
                }
            }
            return (pixels[85 * 200 + 100], behindBox)
        }
        let open = try render(withBox: false)
        let covered = try render(withBox: true)
        #expect(open.gridPixels > 50, "\(open.gridPixels)")
        // The box hides the grid lines behind it.
        #expect(covered.gridPixels == 0, "\(covered.gridPixels)")
        #expect(covered.center.x > 200 && covered.center.y < 40, "\(covered.center)")
    }
}
