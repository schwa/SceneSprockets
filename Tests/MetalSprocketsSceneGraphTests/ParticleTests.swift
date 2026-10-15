import CoreGraphics
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsParticles
import SwiftMesh
import Testing
import simd
@testable import MetalSprocketsSceneGraph

// #50
@Test
func particlesEmitMoveAndDie() {
    let system = ParticleSystem(seed: 1)
    system.birthRate = 10
    system.lifetime = 1
    system.direction = [0, 1, 0]
    system.spreadAngle = 0
    system.speed = 2
    let node = SceneGraph.Node(trs: .init(translation: [5, 0, 0]))
    node.particleSystems = [system]
    let sceneGraph = SceneGraph(root: node)
    for _ in 0..<10 {
        sceneGraph.advanceParticles(by: 0.05)
    }
    #expect(system.particleCount == 5)
    // Straight up from the node at speed 2.
    #expect(system.particles.allSatisfy { abs($0.position.x - 5) < 1e-4 && $0.position.y >= 0 && $0.position.y <= 1 + 1e-4 })
    // Hidden nodes keep simulating but stop emitting: everything has died after a lifetime.
    node.isVisible = false
    for _ in 0..<25 {
        sceneGraph.advanceParticles(by: 0.05)
    }
    #expect(system.particleCount == 0)
}

@Test
func emissionDurationStopsEmitting() {
    let system = ParticleSystem(seed: 2)
    system.birthRate = 100
    system.lifetime = 10
    system.emissionDuration = 0.5
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    sceneGraph.root.particleSystems = [system]
    for _ in 0..<20 {
        sceneGraph.advanceParticles(by: 0.1)
    }
    #expect(system.particleCount == 50)
}

@Test
@MainActor
func particlesDrawInFrontAndAreHiddenBehindMeshes() throws {
    let device = try #require(MTLCreateSystemDefaultDevice())
    let root = SceneGraph.Node()
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 5]), content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(30)))))
    let emitter = SceneGraph.Node(parent: root)
    let system = ParticleSystem(seed: 3)
    system.birthRate = 1_000
    system.speed = 0
    system.startSize = 1
    system.endSize = 1
    system.startColor = [1, 1, 1, 1]
    system.endColor = [1, 1, 1, 1]
    system.blendMode = .additive
    emitter.particleSystems = [system]
    let sceneGraph = SceneGraph(root: root)
    sceneGraph.advanceParticles(by: 0.01)
    func center() throws -> SIMD4<UInt8> {
        let renderer = try OffscreenRenderer(size: CGSize(width: 32, height: 32))
        let texture = try renderer.render(SceneGraphElement(sceneGraph: sceneGraph, aspectRatio: 1, renderers: [ShaderMaterialRenderer()])).texture
        var value = SIMD4<UInt8>.zero
        texture.getBytes(&value, bytesPerRow: 4, from: MTLRegionMake2D(16, 16, 1, 1), mipmapLevel: 0)
        return value
    }
    #expect(try center().x > 200)
    // A black-faced box in front hides them (depth test).
    _ = SceneGraph.Node(parent: root, trs: .init(translation: [0, 0, 2]), content: .mesh(MetalMesh(mesh: .box(), device: device), material: try ShaderMaterial.rim(color: [0, 0, 0, 1])))
    #expect(try center().x < 5)
}
