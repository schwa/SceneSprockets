import CoreGraphics
import DemoKit
import GeometryLite3D
import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsBlinnPhong
@testable import SceneSprocketsDemos
import Testing
import simd

@Test(arguments: DemoCatalog.demos)
@MainActor
func demoBuildsUpdatesAndRenders(demo: Demo) throws {
    let scene = demo.make()
    #expect(!scene.sceneGraph.cameraNodes().isEmpty)
    #expect(!scene.sceneGraph.meshEntries().isEmpty)
    for frame in 0..<3 {
        scene.update(time: Float(frame) / 60, deltaTime: 1 / 60)
    }
    #expect(!scene.sceneGraph.meshEntries().isEmpty)

    let size = CGSize(width: 64, height: 64)
    let element = SceneGraphElement(sceneGraph: scene.sceneGraph, cameraMatrix: scene.initialCameraMatrix, aspectRatio: 1, renderers: scene.renderers)
    let texture = try OffscreenRenderer(size: size).render(element).texture
    var pixels = [UInt8](repeating: 0, count: 64 * 64 * 4)
    texture.getBytes(&pixels, bytesPerRow: 64 * 4, from: MTLRegionMake2D(0, 0, 64, 64), mipmapLevel: 0)
    let litPixels = stride(from: 0, to: pixels.count, by: 4).filter { pixels[$0] > 8 || pixels[$0 + 1] > 8 || pixels[$0 + 2] > 8 }.count
    // Some demos have small objects at 64×64, so the bar is low.
    #expect(litPixels > 40, "\(demo.title) rendered almost nothing")
}

// #69: the skinned tubes must sit on their skeletons, so bending curls them in place; with inverse bind matrices from
// the joints' world transforms they were offset and swung around far-away pivots.
@Test
@MainActor
func deformationSlideTubeFollowsItsSkeleton() throws {
    let graph = try keynoteShowing("Deformation").sceneGraph
    let nodes = graph.nodesWithWorldTransforms().map(\.node)
    let skeleton = try #require(nodes.first { $0.label == "Skeleton" })
    let tube = try #require(graph.meshEntries().first { $0.node.label == "Tube" })
    let positions = try #require(tube.deformed(revision: graph.revision)).mesh.positions()
    let skeletonX = skeleton.worldTransform.columns.3.x
    let baseX = positions.filter { $0.y < 0.05 }.map(\.x)
    // The base ring (weighted to joint 0, which never moves) stays around the skeleton.
    #expect(abs((baseX.min()! + baseX.max()!) / 2 - skeletonX) < 0.01, "tube base is not on its skeleton")
}

@MainActor
func keynoteShowing(_ title: String) throws -> KeynoteDemo {
    let keynote = KeynoteDemo()
    keynote.show(slide: try #require(KeynoteDemo.titles.firstIndex(of: title)))
    return keynote
}

// #70: the bump target moves vertices along the direction from the center, so vertices that share a position (one
// per face) move together and the surface does not tear.
@Test
@MainActor
func deformationSlideMorphKeepsSurfaceClosed() throws {
    let demo = try keynoteShowing("Deformation")
    let blob = try #require(demo.sceneGraph.meshEntries().first { $0.node.label == "Blob" })
    let positions = blob.mesh.positions()
    let deltas = try #require(blob.node.morphTargets.first).positionDeltas
    var deltaByPosition: [SIMD3<Int32>: SIMD3<Float>] = [:]
    for (position, delta) in zip(positions, deltas) {
        let key = SIMD3<Int32>((position * 10_000).rounded(.toNearestOrEven))
        if let existing = deltaByPosition[key] {
            #expect(simd_distance(existing, delta) < 1e-4)
        } else {
            deltaByPosition[key] = delta
        }
    }
}

// #112: the orthographic toggle swaps the camera's projection; it still renders, and a tap ray (built like SceneView's)
// through a shape's projected center hits that shape.
@Test
@MainActor
func sceneKitFeaturesOrthographicToggle() throws {
    let scene = SceneKitFeaturesDemo()
    scene[flag: "Orthographic"] = true
    scene.update(time: 0, deltaTime: 0)
    let cameraNode = try #require(scene.sceneGraph.cameraNodes().first?.node)
    guard case let .camera(camera) = cameraNode.content else {
        Issue.record("Expected a camera")
        return
    }
    #expect(camera.projection is OrthographicProjection)

    let viewSize = SIMD2<Float>(64, 64)
    let viewProjection = ViewProjection(viewMatrix: scene.initialCameraMatrix.inverse, projection: camera.projection, viewSize: viewSize)
    // The torus has a hole at its center; the sphere does not.
    let target = try #require(scene.sceneGraph.meshEntries().first { $0.node.label == "Sphere" }?.node)
    let point = try #require(viewProjection.project(target.worldPosition))
    let hit = scene.sceneGraph.hitTest(viewProjection.ray(through: [point.x, point.y]), categoryBitMask: camera.categoryBitMask).first
    #expect(hit?.node === target)

    scene[flag: "Orthographic"] = false
    scene.update(time: 0, deltaTime: 0)
    guard case let .camera(perspective) = cameraNode.content else {
        return
    }
    #expect(perspective.projection is PerspectiveProjection)
}

// #110: the opacity slider fades every shape through their group, and Fade takes the text out and back in.
@Test
@MainActor
func sceneKitFeaturesOpacityAndFade() throws {
    let scene = SceneKitFeaturesDemo()
    scene[value: "Shapes Opacity"] = 0.5
    scene.update(time: 0, deltaTime: 0)
    let shapes = scene.sceneGraph.meshEntries().filter { $0.node.parent?.label?.hasPrefix("Holder") == true }
    #expect(shapes.count == 6)
    #expect(shapes.allSatisfy { abs($0.opacity - 0.5) < 1e-6 && $0.isTransparent })

    let text = try #require(scene.sceneGraph.meshEntries().first { $0.node.label == "Glyphs" }?.node.parent)
    let fade = try #require(scene.actions.first { $0.name == "Fade" })
    fade.perform()
    scene.sceneGraph.advanceActions(by: 0.6)
    #expect(text.opacity < 1e-4)
    scene.sceneGraph.advanceActions(by: 1)
    #expect(text.opacity == 1)
}

// #111: the Blinn-Phong extras are in the scene, and the Cull Mode choice reaches the sphere's material.
@Test
@MainActor
func sceneKitFeaturesBlinnPhongExtras() throws {
    let scene = SceneKitFeaturesDemo()
    func material(_ label: String) throws -> BlinnPhongSceneMaterial {
        try #require(scene.sceneGraph.meshEntries().first { $0.node.label == label }?.material as? BlinnPhongSceneMaterial)
    }
    guard case .color(let emission) = try material("Emissive Sphere").emission else {
        Issue.record("Expected a color emission")
        return
    }
    #expect(emission != .zero)
    #expect(try material("Normal-Mapped Box").normalMap != nil)
    #expect(try material("Culled Sphere").cullMode == .none)
    scene[value: "Cull Mode"] = 2
    scene.update(time: 0, deltaTime: 0)
    #expect(try material("Culled Sphere").cullMode == .front)
}

// The bump map's normals tilt up (+Y, green above 0.5) on the upper half of each bump and down on the lower half.
@Test
@MainActor
func bumpNormalMapPointsUpOnTop() throws {
    let texture = try #require(SceneKitFeaturesDemo.bumpNormalMap(size: 128))
    func green(row: Int) -> UInt8 {
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, row, 1, 1), mipmapLevel: 0)
        return value.y
    }
    // The first cell spans rows 0..<32 and is centered on row 16.
    #expect(green(row: 8) > 160)
    #expect(green(row: 24) < 96)
}

// The catalog and the app's picker come from one list (#116); ids must still be unique.
@Test
@MainActor
func catalogMatchesAppAndIDsAreUnique() {
    #expect(SceneGraphDemos.all.map { $0.metadata.id.rawValue } == DemoCatalog.demos.map(\.id))
    #expect(Set(DemoCatalog.demos.map(\.id)).count == DemoCatalog.demos.count)
}

@Test
@MainActor
func demoParametersHaveDefaults() {
    for demo in DemoCatalog.demos {
        let scene = demo.make()
        for parameter in scene.parameters {
            #expect(scene.values[parameter.name] == parameter.defaultValue)
        }
    }
}
