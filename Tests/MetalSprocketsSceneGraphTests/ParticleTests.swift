import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph
@testable import MetalSprocketsSceneGraphShaderMaterial

// A bright cloud of still, long-lived additive particles at the emitter.
private func glowSystem() -> ParticleSystem {
    ParticleSystem("Glow") {
        EmitterDescription("Glow") {
            ShapeModule(shape: .sphere(radius: 0.2))
            RateModule(birthRate: 2_000)
            LifetimeModule(range: 0.5...0.5)
            VelocityModule(velocity: .zero)
            GravityModule(acceleration: .zero)
            SizeOverLifeModule(curve: .constant(0.5))
            ColorOverLifeModule(color: .constant([1, 1, 1, 1]))
            SpriteModule(blendMode: .additive)
        }
    }
}

@MainActor
private func centerPixel(_ sceneGraph: SceneGraph, frames: Int, deltaTime: Float = 1.0 / 30.0) throws -> SIMD4<UInt8> {
    let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
    var value = SIMD4<UInt8>.zero
    for _ in 0..<frames {
        sceneGraph.advanceParticles(by: deltaTime)
        let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
    }
    return value
}

@MainActor
private func makeScene() -> (SceneGraph, emitter: SceneGraph.Node) {
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(30)))))
    let emitter = SceneGraph.Node(parent: root)
    emitter.particleSystems = [SceneParticleSystem(glowSystem(), seed: 3)]
    return (SceneGraph(root: root), emitter)
}

@Test
@MainActor
func particlesDrawInFrontAndAreHiddenBehindMeshes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (sceneGraph, _) = makeScene()
    #expect(try centerPixel(sceneGraph, frames: 5).x > 200)
    // A black-faced box in front hides them (reversed depth test).
    _ = SceneGraph.Node(parent: sceneGraph.root, trs: .init(translation: [0, 0, 2]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: try ShaderMaterial.rim(color: [0, 0, 0, 1])))
    #expect(try centerPixel(sceneGraph, frames: 1).x < 5)
}

@Test
@MainActor
func particlesFollowTheNode() throws {
    let (sceneGraph, emitter) = makeScene()
    emitter.transform = .init(translation: [3, 0, 0])
    #expect(try centerPixel(sceneGraph, frames: 5).x < 5)
}

@Test
@MainActor
func hiddenNodesStopEmitting() throws {
    let (sceneGraph, emitter) = makeScene()
    let runtime = try emitter.particleSystems[0].runtime()
    _ = try centerPixel(sceneGraph, frames: 10)
    #expect(runtime.aliveParticleCount > 100)
    // Hidden systems keep simulating, so the 0.5 s particles die and none replace them.
    emitter.isVisible = false
    _ = try centerPixel(sceneGraph, frames: 30)
    #expect(runtime.aliveParticleCount == 0)
    #expect(runtime.emitters.allSatisfy { !$0.isEmitting })
    emitter.isVisible = true
    _ = try centerPixel(sceneGraph, frames: 1)
    #expect(runtime.emitters.allSatisfy { $0.isEmitting })
}
