import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
@testable import SceneSprockets
@testable import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import Testing

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
    root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(30))))))
    let emitter = root.addChild(SceneGraph.Node())
    emitter.particleSystems = [SceneParticleSystem(glowSystem(), seed: 3)]
    return (SceneGraph(root: root), emitter)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func particlesDrawInFrontAndAreHiddenBehindMeshes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let (sceneGraph, _) = makeScene()
    #expect(try centerPixel(sceneGraph, frames: 5).x > 200)
    // A black-faced box in front hides them (reversed depth test).
    sceneGraph.root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 2]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: ShaderMaterial.rim(color: [0, 0, 0]))))
    #expect(try centerPixel(sceneGraph, frames: 1).x < 5)
}

@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func particlesFollowTheNode() throws {
    let (sceneGraph, emitter) = makeScene()
    emitter.transform = .init(translation: [3, 0, 0])
    #expect(try centerPixel(sceneGraph, frames: 5).x < 5)
}

// #145
@Test(.enabled(if: deviceSupportsMetal4))
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
        root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(30))))))
        let emitter = root.addChild(SceneGraph.Node())
        emitter.particleSystems = [SceneParticleSystem(system, seed: 3)]
        // A black wall just behind the particles.
        root.addChild(SceneGraph.Node(transform: .init(translation: [0, 0, -0.6]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: ShaderMaterial.rim(color: [0, 0, 0]))))
        let sceneGraph = SceneGraph(root: root)
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32), colorUsage: Shadows.requiredColorUsage, depthUsage: Shadows.requiredDepthUsage)
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
func collidersFollowTheNodeTransform() {
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

@Test(.enabled(if: deviceSupportsMetal4))
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

// #474: ScenePresenter publishes snapshots that a renderer may draw after a newer edit was applied. An older frame must
// not apply its older description again, which rebuilt the emitters and dropped what was set on them.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func olderFrameDoesNotReapplyAnOlderDescription() throws {
    let system = SceneParticleSystem(glowSystem(), seed: 3)
    system.advance(by: 1.0 / 60.0, worldTransform: matrix_identity_float4x4, isHidden: false)
    let older = system.makeFrame()
    _ = try system.simulate(older, view: matrix_identity_float4x4)
    // New emitter ids, so applying either description rebuilds the emitters.
    system.system = glowSystem()
    let emitter = try #require(try system.runtime().emitters.first)
    _ = try system.simulate(older, view: matrix_identity_float4x4)
    #expect(try system.runtime().emitters.first === emitter)
}

// #480: single emitters are turned on and off, and given a mesh, from the editing side. The values go to the render
// side with each frame, so they also hold after a new description rebuilds the emitters.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func emitterStateIsSetFromTheEditingSide() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let system = SceneParticleSystem(glowSystem(), seed: 3)
    let mesh = try EmitterMesh(device: device, positions: [[0, 0, 0], [1, 0, 0], [0, 1, 0]], indices: [0, 1, 2])
    func step() throws {
        system.advance(by: 1.0 / 60.0, worldTransform: matrix_identity_float4x4, isHidden: false)
        _ = try system.simulate(system.makeFrame(), view: matrix_identity_float4x4)
    }
    try step()
    #expect(try system.runtime().emitters[0].isEmitting)
    #expect(try system.runtime().emitters[0].mesh == nil)

    system.setEmitting(false, forEmitterAt: 0)
    system.setEmitterMesh(mesh)
    try step()
    #expect(try !system.runtime().emitters[0].isEmitting)
    #expect(try system.runtime().emitters[0].mesh === mesh)

    // New emitter ids rebuild the emitters.
    system.system = glowSystem()
    try step()
    #expect(try !system.runtime().emitters[0].isEmitting)
    #expect(try system.runtime().emitters[0].mesh === mesh)

    system.setEmitting(nil, forEmitterAt: 0)
    system.setEmitterMesh(nil)
    system.system = glowSystem()
    try step()
    #expect(try system.runtime().emitters[0].isEmitting)
    #expect(try system.runtime().emitters[0].mesh == nil)
}

// #392: a window's SceneView and a visionOS immersive space can render the same scene at once, on two threads.
@Test(.enabled(if: deviceSupportsMetal4))
@MainActor
func twoThreadsCanSimulateTheSameSystem() async throws {
    let system = SceneParticleSystem(glowSystem(), seed: 3)
    system.advance(by: 1.0 / 60.0, worldTransform: matrix_identity_float4x4, isHidden: false)
    let frame = system.makeFrame()
    _ = try system.simulate(frame, view: matrix_identity_float4x4)
    nonisolated(unsafe) let unsafeSystem = system
    nonisolated(unsafe) let unsafeFrame = frame
    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<4 {
            group.addTask {
                for _ in 0..<500 {
                    _ = try? unsafeSystem.simulate(unsafeFrame, view: matrix_identity_float4x4)
                }
            }
        }
    }
}
