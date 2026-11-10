import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
@testable import SceneSprockets
import SceneSprocketsBlinnPhong
@testable import SceneSprocketsGizmos
import simd
import Testing

// #154
@MainActor
struct TransformGizmoTests {
    // A camera 10 units back on +Z looking at the origin, in a 400x400 point view.
    let viewport = SceneViewport(
        cameraMatrix: LookAt(position: [0, 0, 10], target: .zero, up: [0, 1, 0]).cameraMatrix,
        projectionMatrix: PerspectiveProjection(verticalAngleOfView: .degrees(40), depthMode: .standard(zClip: 0.1 ... 100)).projectionMatrix(aspectRatio: 1),
        viewSize: [400, 400],
        drawableSize: [400, 400]
    )

    func screen(_ world: SIMD3<Float>) -> SIMD2<Float> {
        viewport.project(world)!.xy
    }

    func makeGizmo(_ mode: TransformGizmo.Mode = .translate) -> (TransformGizmo, SceneGraph.Node) {
        let node = SceneGraph.Node(label: "Target")
        return (TransformGizmo(target: node, mode: mode), node)
    }

    @Test
    func handlesStayTheSameSizeOnScreen() throws {
        let (gizmo, node) = makeGizmo()
        let near = try #require(gizmo.frame(viewport: viewport)).length
        node.worldPosition = [0, 0, -10]
        let far = try #require(gizmo.frame(viewport: viewport)).length
        #expect(abs(far / near - 2) < 0.01)
        // The axis handle is `size` points long on screen.
        let frame = try #require(gizmo.frame(viewport: viewport))
        let length = simd_distance(screen(frame.origin), screen(frame.origin + [frame.length, 0, 0]))
        #expect(abs(length - gizmo.size) < 0.5)
    }

    // #171
    @Test
    func worldSizeScalesWithTheCamera() throws {
        let (gizmo, node) = makeGizmo()
        gizmo.worldSize = 1.5
        let near = try #require(gizmo.frame(viewport: viewport))
        #expect(near.length == 1.5)
        let nearReach = simd_distance(screen(near.origin), screen(near.origin + [near.length, 0, 0]))
        #expect(gizmo.claimsTwoFingerGesture(at: screen(near.origin) + [nearReach - 1, 0], viewport: viewport))
        node.worldPosition = [0, 0, -10]
        #expect(try #require(gizmo.frame(viewport: viewport)).length == 1.5)
        #expect(!gizmo.claimsTwoFingerGesture(at: screen(near.origin) + [nearReach - 1, 0], viewport: viewport))
    }

    @Test
    func picksTheHandleUnderThePointer() throws {
        let (gizmo, _) = makeGizmo()
        let frame = try #require(gizmo.frame(viewport: viewport))
        #expect(gizmo.handle(at: screen([frame.length * 0.7, 0, 0]), viewport: viewport) == .axis(.x))
        #expect(gizmo.handle(at: screen([0, frame.length * 0.7, 0]), viewport: viewport) == .axis(.y))
        #expect(gizmo.handle(at: screen(.zero), viewport: viewport) == .center)
        // The XY plane square (perpendicular to Z) sits between the X and Y axes.
        #expect(gizmo.handle(at: screen([frame.length * 0.2, frame.length * 0.2, 0]), viewport: viewport) == .plane(.z))
        #expect(gizmo.handle(at: [10, 10], viewport: viewport) == nil)
    }

    @Test
    func draggingAnAxisMovesAlongItOnly() throws {
        let (gizmo, node) = makeGizmo()
        let frame = try #require(gizmo.frame(viewport: viewport))
        var changes = 0
        gizmo.onChange = { _ in changes += 1 }
        gizmo.beginDrag(at: screen([frame.length * 0.7, 0, 0]), viewport: viewport)
        // Drag up and to the right: only the X part counts.
        gizmo.drag(to: screen([frame.length * 0.7 + 1, 0.5, 0]), viewport: viewport)
        gizmo.endDrag()
        #expect(abs(node.worldPosition.x - 1) < 0.01)
        #expect(abs(node.worldPosition.y) < 1e-4 && abs(node.worldPosition.z) < 1e-4)
        #expect(changes == 1)
    }

    @Test
    func translationSnaps() throws {
        let (gizmo, node) = makeGizmo()
        gizmo.snapping.translation = 0.5
        let frame = try #require(gizmo.frame(viewport: viewport))
        gizmo.beginDrag(at: screen([frame.length * 0.7, 0, 0]), viewport: viewport)
        gizmo.drag(to: screen([frame.length * 0.7 + 0.8, 0, 0]), viewport: viewport)
        #expect(abs(node.worldPosition.x - 1) < 1e-4)
    }

    @Test
    func rotatingAboutZ() throws {
        let (gizmo, node) = makeGizmo(.rotate)
        let frame = try #require(gizmo.frame(viewport: viewport))
        let radius = frame.length * 0.9
        // A quarter turn counterclockwise around +Z (toward the camera).
        gizmo.beginDrag(at: screen([radius, 0, 0]), viewport: viewport)
        gizmo.drag(to: screen([0, radius, 0]), viewport: viewport)
        let rotated = node.worldOrientation.act([1, 0, 0])
        #expect(simd_distance(rotated, [0, 1, 0]) < 0.01)
    }

    @Test
    func scalingAnAxisAndUniformly() throws {
        let (gizmo, node) = makeGizmo(.scale)
        let frame = try #require(gizmo.frame(viewport: viewport))
        gizmo.beginDrag(at: screen([frame.length * 0.5, 0, 0]), viewport: viewport)
        gizmo.drag(to: screen([frame.length, 0, 0]), viewport: viewport)
        gizmo.endDrag()
        #expect(abs(node.trs.scale.x - 2) < 0.01 && node.trs.scale.y == 1)
        gizmo.beginDrag(at: screen(.zero) + [5, 0], viewport: viewport)
        gizmo.drag(to: screen(.zero) + [10, 0], viewport: viewport)
        #expect(simd_distance(node.trs.scale, [4, 2, 2]) < 0.05)
    }

    @Test
    func localSpaceFollowsTheNode() throws {
        let (gizmo, node) = makeGizmo()
        node.trs.rotation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        gizmo.space = .local
        let frame = try #require(gizmo.frame(viewport: viewport))
        #expect(simd_distance(frame.axis(.x), [0, 1, 0]) < 1e-4)
    }

    // The overlay pass draws over the scene even where scene geometry is nearer the camera (reversed depth there).
    @Test(.enabled(if: deviceSupportsMetal4))
    func drawsOverTheScene() throws {
        let root = SceneGraph.Node()
        root.addChild(SceneGraph.Node(content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(40), depthMode: .standard(zClip: 0.1 ... 100))))))
        root.children[0].transform = viewport.cameraMatrix
        // A box in front of the gizmo's X handle.
        let box = SceneGraph.Node(parent: root, shape: .box(width: 3, height: 1, length: 1), material: BlinnPhongSceneMaterial(ambient: .color(1), diffuse: .color(0.2), specular: .color(0), shininess: 1), trs: .init(translation: [0.8, 0, 2]))
        let (gizmo, _) = makeGizmo()
        let overlay = try #require(try gizmo.overlay(viewport: viewport))
        let renderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400), clearDepth: 0)
        let texture = try renderer.render(try MetalSprockets.Group {
            SceneGraphElement(sceneGraph: SceneGraph(root: root), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])
            ManipulatorOverlayPass(content: overlay)
        }).texture
        _ = box
        // The box itself is drawn: a pixel of it away from the handles is grey.
        var boxPixel = [UInt8](repeating: 0, count: 4)
        let boxPoint = screen([1.9, -0.4, 2.5])
        texture.getBytes(&boxPixel, bytesPerRow: 4, from: MTLRegionMake2D(Int(boxPoint.x), Int(boxPoint.y), 1, 1), mipmapLevel: 0)
        #expect(boxPixel[0] > 10, "\(boxPixel)")
        var pixels = [UInt8](repeating: 0, count: 400 * 400 * 4)
        texture.getBytes(&pixels, bytesPerRow: 1_600, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
        let point = screen([try #require(gizmo.frame(viewport: viewport)).length * 0.5, 0, 0])
        let offset = (Int(point.y) * 400 + Int(point.x)) * 4
        #expect(pixels[offset + 2] > 200 && Int(pixels[offset + 2]) - Int(pixels[offset + 1]) > 80, "\(pixels[offset ..< offset + 4])")
    }

    // #262: the handles draw the same far from the world origin, with the camera and target moved together.
    @Test(.enabled(if: deviceSupportsMetal4), arguments: [TransformGizmo.Mode.translate, .rotate, .scale])
    func drawsTheSameFarFromOrigin(mode: TransformGizmo.Mode) throws {
        func render(offset: SIMD3<Float>) throws -> [UInt8] {
            let viewport = SceneViewport(
                cameraMatrix: LookAt(position: offset + [3, 4, 10], target: offset, up: [0, 1, 0]).cameraMatrix,
                projectionMatrix: self.viewport.projectionMatrix,
                viewSize: [200, 200],
                drawableSize: [200, 200]
            )
            let node = SceneGraph.Node(label: "Target")
            node.worldPosition = offset
            let gizmo = TransformGizmo(target: node, mode: mode)
            let overlay = try #require(try gizmo.overlay(viewport: viewport))
            let renderer = try OffscreenRenderer(size: CGSize(width: 200, height: 200), clearDepth: 0)
            let texture = try renderer.render(ManipulatorOverlayPass(content: overlay)).texture
            var pixels = [UInt8](repeating: 0, count: 200 * 200 * 4)
            texture.getBytes(&pixels, bytesPerRow: 800, from: MTLRegionMake2D(0, 0, 200, 200), mipmapLevel: 0)
            return pixels
        }
        let near = try render(offset: .zero)
        // 2^20: exact in Float, so only the drawing math can differ.
        let far = try render(offset: [1_048_576, 0, 1_048_576])
        let differing = stride(from: 0, to: near.count, by: 4).count { index in
            (0..<3).contains { abs(Int(near[index + $0]) - Int(far[index + $0])) > 40 }
        }
        #expect(differing < 40, "\(differing) of 40000 pixels differ")
    }

    // #178: pinch and twist on the gizmo scale and turn the target.
    @Test
    func pinchAndTwistScaleAndTurnTheTarget() {
        let (gizmo, node) = makeGizmo()
        #expect(gizmo.claimsTwoFingerGesture(at: screen(.zero) + [20, 20], viewport: viewport))
        #expect(!gizmo.claimsTwoFingerGesture(at: screen(.zero) + [gizmo.size + 10, 0], viewport: viewport))
        var events: [String] = []
        gizmo.onBegin = { _ in events.append("begin") }
        gizmo.onEnd = { _ in events.append("end") }
        gizmo.beginTwoFingerGesture(viewport: viewport)
        gizmo.twoFingerGesture(scale: 2, rotation: .pi / 2, viewport: viewport)
        gizmo.endTwoFingerGesture()
        #expect(events == ["begin", "end"])
        #expect(simd_distance(node.trs.scale, [2, 2, 2]) < 0.0001)
        // A clockwise quarter turn on screen, seen from +Z: +X turns to -Y.
        #expect(simd_distance(node.worldOrientation.act([1, 0, 0]), [0, -1, 0]) < 0.01)
    }

    // #168: the view ring turns about the view direction.
    @Test
    func viewRingRotatesAboutTheViewDirection() throws {
        let (gizmo, node) = makeGizmo(.rotate)
        let frame = try #require(gizmo.frame(viewport: viewport))
        let start = screen(frame.origin + frame.cameraRight * frame.length * 1.1)
        #expect(gizmo.handle(at: start, viewport: viewport) == .view)
        gizmo.beginDrag(at: start, viewport: viewport)
        gizmo.drag(to: screen(frame.origin + frame.cameraUp * frame.length * 1.1), viewport: viewport)
        gizmo.endDrag()
        // A quarter turn counterclockwise on screen: +X turns to +Y.
        #expect(simd_distance(node.worldOrientation.act([1, 0, 0]), [0, 1, 0]) < 0.01)
    }

    // #168: dragging inside the rings turns the node freely.
    @Test
    func trackballTurnsTheNearSideWithTheDrag() {
        let (gizmo, node) = makeGizmo(.rotate)
        let center = screen(.zero)
        #expect(gizmo.handle(at: center + [5, 5], viewport: viewport) == .center)
        gizmo.beginDrag(at: center + [5, 5], viewport: viewport)
        // pi / 2 radians at 0.01 radians per point.
        gizmo.drag(to: center + [5 + Float.pi / 2 / 0.01, 5], viewport: viewport)
        gizmo.endDrag()
        // The side facing the camera (+Z) turned right (+X).
        #expect(simd_distance(node.worldOrientation.act([0, 0, 1]), [1, 0, 0]) < 0.01)
    }

    // #169: the camera looks down -Z, so the Z axis points at it and the XY plane faces it.
    @Test
    func handlesPointingAtTheCameraFade() throws {
        let (gizmo, _) = makeGizmo()
        let frame = try #require(gizmo.frame(viewport: viewport))
        #expect(gizmo.opacity(of: .axis(.z), frame: frame) == 0)
        #expect(gizmo.opacity(of: .axis(.x), frame: frame) == 1)
        #expect(gizmo.opacity(of: .plane(.z), frame: frame) == 1)
        // The XZ and YZ planes are seen edge-on.
        #expect(gizmo.opacity(of: .plane(.y), frame: frame) == 0)
        // A faded handle cannot be picked: the Z axis projects onto the center, which wins anyway, so test a plane.
        let yzCorner = frame.origin + (frame.axis(.y) + frame.axis(.z)) * frame.length * 0.25
        #expect(gizmo.handle(at: screen(yzCorner), viewport: viewport) != .plane(.x))
    }

    @Test
    func ringsSplitIntoFrontAndBackHalves() throws {
        let (gizmo, _) = makeGizmo(.rotate)
        let frame = try #require(gizmo.frame(viewport: viewport))
        // The X ring (in the YZ plane) is seen edge-on: half in front of the center, half behind.
        let ring = try #require(gizmo.outlines(frame).first { $0.handle == .axis(.x) }).points
        let runs = TransformGizmo.ringRuns(ring, frame: frame)
        #expect(runs.contains(where: \.isFront) && runs.contains { !$0.isFront })
        for run in runs {
            for point in run.points.dropFirst().dropLast() {
                #expect((simd_dot(point - frame.origin, frame.cameraForward) <= frame.length * 1e-4) == run.isFront)
            }
        }
        // The Z ring faces the camera: all of it is in front (on the plane through the center).
        let facing = try #require(gizmo.outlines(frame).first { $0.handle == .axis(.z) }).points
        #expect(TransformGizmo.ringRuns(facing, frame: frame).allSatisfy { $0.isFront })
    }

    @Test(.enabled(if: deviceSupportsMetal4))
    func drawsItsHandles() throws {
        let (gizmo, _) = makeGizmo()
        let overlay = try #require(try gizmo.overlay(viewport: viewport))
        let renderer = try OffscreenRenderer(size: CGSize(width: 400, height: 400))
        let texture = try renderer.render(try RenderPass { overlay }).texture
        var pixels = [UInt8](repeating: 0, count: 400 * 400 * 4)
        texture.getBytes(&pixels, bytesPerRow: 1_600, from: MTLRegionMake2D(0, 0, 400, 400), mipmapLevel: 0)
        // Halfway along the X handle: SwiftUI red (BGRA, sRGB encoded, so green and blue are not 0).
        let point = screen([try #require(gizmo.frame(viewport: viewport)).length * 0.5, 0, 0])
        let offset = (Int(point.y) * 400 + Int(point.x)) * 4
        #expect(pixels[offset + 2] > 200 && Int(pixels[offset + 2]) - Int(pixels[offset + 1]) > 80, "\(pixels[offset ..< offset + 4])")
    }
}
