import Foundation
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import simd
import SwiftMesh
import Testing

// #391: the main actor edits and steps the graph while another thread renders the presenter's snapshots.

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func presenterSnapshotsRenderWhileTheGraphIsEdited() async throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let box = MetalMesh(mesh: .box(), device: device)
    let material = BlinnPhongSceneMaterial(ambient: .color(0.2), diffuse: .color(0.8), specular: .color(0), shininess: 1)
    let root = SceneGraph.Node()
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 6]), content: .camera(Camera(projection: PerspectiveProjection()))))
    let emitter = root.addChild(SceneGraph.Node())
    emitter.particleSystems = [SceneParticleSystem(ParticleSystem("Glow") { EmitterDescription("Glow") { RateModule(birthRate: 200) } }, seed: 1)]
    let presenter = ScenePresenter(sceneGraph: SceneGraph(root: root))

    // Used only by the rendering thread.
    nonisolated(unsafe) let renderer = try OffscreenRenderer(size: CGSize(width: 16, height: 16))
    let renders = RenderCounter()
    let done = RenderCounter()
    let thread = Thread {
        while done.value == 0 {
            let element = SceneGraphElement(presentation: presenter.takePresentation(), aspectRatio: 1, renderers: [BlinnPhongMaterialRenderer()])
            if (try? renderer.render(element)) != nil {
                renders.increment()
            }
        }
    }
    thread.start()

    // Structural and transform edits on the main actor, many times while the other thread renders.
    var nodes: [SceneGraph.Node] = []
    for frame in 0 ..< 200 {
        let node = root.addChild(SceneGraph.Node(transform: .init(translation: [Float(frame % 7) - 3, 0, 0]), content: .mesh(box, material: material)))
        node.text = SceneText("\(frame)")
        nodes.append(node)
        if nodes.count > 20 {
            nodes.removeFirst().removeFromParent()
        }
        nodes.first?.transform = .init(translation: [0, Float(frame) * 0.01, 0])
        presenter.step(frameTime: Float(frame) / 60)
        await Task.yield()
    }
    while renders.value < 20 {
        try await Task.sleep(for: .milliseconds(5))
    }
    done.increment()
    #expect(renders.value >= 20)
}

private final class RenderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
