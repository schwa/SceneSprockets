import CoreGraphics
import Metal
import MetalSprockets
import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphDemos
import Testing
import simd

@Test(arguments: DemoCatalog.demos)
@MainActor
func demoBuildsUpdatesAndRenders(demo: Demo) throws {
    let scene = demo.make()
    #expect(!scene.sceneGraph.cameraNodes().isEmpty)
    #expect(!scene.sceneGraph.meshEntries().isEmpty || demo.id == "instancing")
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
func deformationDemoTubesFollowTheirSkeletons() throws {
    let demo = DeformationDemo()
    let graph = demo.sceneGraph
    for name in ["Blinn-Phong", "PBR"] {
        let nodes = graph.nodesWithWorldTransforms().map(\.node)
        let skeleton = try #require(nodes.first { $0.label == "\(name) Skeleton" })
        let tube = try #require(graph.meshEntries().first { $0.node.label == "\(name) Tube" })
        let positions = try #require(tube.deformed(revision: graph.revision)).mesh.positions()
        let skeletonX = skeleton.worldTransform.columns.3.x
        let baseX = positions.filter { $0.y < 0.05 }.map(\.x)
        // The base ring (weighted to joint 0, which never moves) stays around the skeleton.
        #expect(abs((baseX.min()! + baseX.max()!) / 2 - skeletonX) < 0.01, "\(name) tube base is not on its skeleton")
    }
}

// #70: the bump target moves vertices along the direction from the center, so vertices that share a position (one
// per face) move together and the surface does not tear.
@Test
@MainActor
func deformationDemoMorphKeepsSurfaceClosed() throws {
    let demo = DeformationDemo()
    let blob = try #require(demo.sceneGraph.meshEntries().first { $0.node.label == "PBR Blob" })
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
