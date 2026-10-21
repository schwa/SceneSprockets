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

// #145
@Test
@MainActor
func softParticlesFadeIntoGeometry() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    func brightness(softness: Float) throws -> UInt8 {
        var system = glowSystem()
        system.layers[0].modules[SpriteModule.self]?.softness = softness
        // Few enough that additive blending does not saturate.
        system.layers[0].modules[RateModule.self]?.birthRate = 60
        system.layers[0].modules[ColorOverLifeModule.self] = ColorOverLifeModule(color: .constant([0.2, 0.2, 0.2, 1]))
        let root = SceneGraph.Node()
        _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(30)))))
        _ = SceneGraph.Node(parent: root).particleSystems = [SceneParticleSystem(system, seed: 3)]
        // A black wall just behind the particles.
        _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, -0.6]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: try ShaderMaterial.rim(color: [0, 0, 0, 1])))
        let sceneGraph = SceneGraph(root: root)
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), colorUsage: SceneGraphShadows.requiredColorUsage, depthUsage: SceneGraphShadows.requiredDepthUsage)
        var value = SIMD4<UInt8>.zero
        for _ in 0..<5 {
            sceneGraph.advanceParticles(by: 1.0 / 30.0)
            let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
            texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
        }
        return value.x
    }
    let hard = try brightness(softness: 0)
    let soft = try brightness(softness: 2)
    #expect(hard > 40)
    #expect(soft < hard / 2, "hard \(hard) soft \(soft)")
}

// #144
@Test
func collidersFollowTheNodeTransform() throws {
    var transform = simd_float4x4(simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))
    transform.columns = (transform.columns.0 * 2, transform.columns.1 * 2, transform.columns.2 * 2, [1, 2, 3, 1])
    let sphere = Collider.sphere(center: [1, 0, 0], radius: 0.5).transformed(by: transform)
    guard case let .sphere(center, radius) = sphere.shape else {
        Issue.record("not a sphere")
        return
    }
    #expect(simd_distance(center, [1, 4, 3]) < 1e-5)
    #expect(abs(radius - 1) < 1e-5)
    // The floor y = 0 turns to face -x and moves to x = 1.
    let plane = Collider.plane(normal: [0, 1, 0], distance: 0).transformed(by: transform)
    guard case let .plane(normal, distance) = plane.shape else {
        Issue.record("not a plane")
        return
    }
    #expect(simd_distance(normal, [-1, 0, 0]) < 1e-5)
    #expect(abs(distance - -1) < 1e-5)
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
