import Foundation
import Metal
import MetalSprocketsGLTF
import MetalSprocketsParticles
import SceneSprockets
import SceneSprocketsPBR
import simd
import SwiftMesh

// The glTF sample Fox, walking, with particles born on its skinned surface. It walks for a moment, catches fire, then
// cycles between flames with embers and blue sparks that trace the mesh (like the MetalSprocketsParticles teapot).
@MainActor
final class BurningFox {
    // The fox walks unharmed for this long after restart(), then catches fire.
    static let ignitionDelay: Float = 2
    // Seconds of flames, then of sparks.
    static let cyclePhase: Float = 4
    // Emitter order in the system: flames and embers, then sparks.
    private static let fireEmitters = 0..<2

    let node: SceneGraph.Node
    private let fox: SceneGraph.Node
    private let fireLight: SceneGraph.Node
    private let particles: SceneParticleSystem
    private let player: SceneGraph.AnimationPlayer?
    private let scale: Float
    private var emitterMesh: EmitterMesh?
    private var elapsed: Float = 0
    private var isBurning = false
    // 1 while flames burn, 0 while sparks do; eases between them for the light.
    private var fireAmount: Float = 1

    // `scale` sizes the fox and its particles; 1 makes the fox about 2.2 units long.
    init(scale: Float = 1) throws {
        self.scale = scale
        node = SceneGraph.Node(label: "Burning Fox")
        guard let url = Bundle.module.url(forResource: "Fox", withExtension: "glb", subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let asset = try GLTFAsset(url: url, device: demoDevice).makeSceneGraph()
        // The fox is about 150 units long, in centimeters.
        fox = node.addChild(SceneGraph.Node(label: "Fox", trs: .init(scale: SIMD3(repeating: 0.015 * scale))))
        for child in asset.sceneGraph.root.children {
            fox.addChild(child)
        }
        // Survey, Walk, Run in the sample.
        let walk = asset.animations.first { $0.name == "Walk" } ?? asset.animations.first
        player = walk.map { SceneGraph.AnimationPlayer(clip: $0) }
        particles = SceneParticleSystem(Self.system(scale: scale, isEmitting: false), seed: 7)
        // The skinned positions the particles are born on are already in world space; the node only shows and hides
        // them.
        particles.usesNodeTransform = false
        node.particleSystems = [particles]
        var light = Light(type: .point, color: [1, 0.5, 0.15], intensity: 0)
        light.range = 4 * scale
        fireLight = node.addChild(SceneGraph.Node(label: "Fire Light", trs: .init(translation: [0, 1.6 * scale, 0]), content: .light(light)))
        fireLight.isVisible = false
    }

    // Puts the fire out and starts the walk again.
    func restart() {
        elapsed = 0
        isBurning = false
        fireAmount = 1
        player?.time = 0
        particles.restart()
        particles.system = Self.system(scale: scale, isEmitting: false)
        emitterMesh = nil
    }

    func update(sceneGraph: SceneGraph, deltaTime: Float) {
        player?.advance(by: deltaTime)
        elapsed += deltaTime
        if !isBurning, elapsed >= Self.ignitionDelay {
            // New emitter ids rebuild the emitters, so they need the mesh again; nothing had been emitted yet.
            isBurning = true
            particles.system = Self.system(scale: scale, isEmitting: true)
            emitterMesh = nil
        }
        updateEmitterMesh(sceneGraph: sceneGraph)
        let burnTime = elapsed - Self.ignitionDelay
        let flamesOn = Int(max(burnTime, 0) / Self.cyclePhase).isMultiple(of: 2)
        // Emitters turn on and off instead of swapping systems, so old particles finish their lives.
        if isBurning, let runtime = try? particles.runtime() {
            for (index, emitter) in runtime.emitters.enumerated() {
                emitter.isEmitting = Self.fireEmitters.contains(index) == flamesOn
            }
        }
        fireAmount += ((flamesOn ? 1 : 0) - fireAmount) * min(deltaTime * 3, 1)
        // The light flares up over half a second at ignition, and turns cold blue for sparks.
        let flare = isBurning ? min(burnTime / 0.5, 1) : 0
        fireLight.isVisible = flare > 0
        if case var .light(light) = fireLight.content {
            light.intensity = flare * (1.2 + 1.8 * fireAmount) * scale * scale
            light.color = simd_mix(SIMD3<Float>(0.3, 0.6, 1), [1, 0.5, 0.15], SIMD3(repeating: fireAmount))
            fireLight.content = .light(light)
        }
    }

    // Gives every emitter the fox's skinned triangles, then each frame its current positions.
    private func updateEmitterMesh(sceneGraph: SceneGraph) {
        guard let skinned = Self.descendants(of: fox).first(where: { $0.skin != nil }),
              let entry = sceneGraph.meshEntries().first(where: { $0.node === skinned }),
              let deformed = entry.deformed(revision: sceneGraph.revision),
              let position = deformed.mesh.vertexDescriptor.attributes.first(where: { $0.semantic == .position }),
              let buffer = deformed.mesh.vertexBuffers[position.bufferIndex],
              let runtime = try? particles.runtime()
        else {
            return
        }
        let stride = deformed.mesh.vertexDescriptor.layouts[position.bufferIndex]?.stride ?? 12
        let offset = (deformed.mesh.vertexBufferOffsets[position.bufferIndex] ?? 0) + position.offset
        if emitterMesh == nil {
            // Rest positions only weight triangles by area, so the first skinned pose serves.
            let pointer = buffer.contents().advanced(by: offset)
            let positions = (0..<deformed.mesh.vertexCount).map { vertex in
                let base = pointer.advanced(by: vertex * stride)
                return SIMD3<Float>(base.loadUnaligned(as: Float.self), base.loadUnaligned(fromByteOffset: 4, as: Float.self), base.loadUnaligned(fromByteOffset: 8, as: Float.self))
            }
            let indices = deformed.mesh.submeshes.filter { $0.primitiveType == .triangle }.flatMap(\.indices)
            emitterMesh = try? EmitterMesh(device: demoDevice, positions: positions, indices: indices)
            for emitter in runtime.emitters {
                emitter.mesh = emitterMesh
            }
        }
        // A fresh buffer each revision, so frames in flight keep theirs.
        emitterMesh?.setDeformedPositions(buffer, offset: offset, stride: stride)
    }

    private static func descendants(of node: SceneGraph.Node) -> [SceneGraph.Node] {
        node.children.flatMap { [$0] + descendants(of: $0) }
    }

    // Sizes, speeds and accelerations scale with the fox.
    private static func system(scale s: Float, isEmitting: Bool) -> ParticleSystem {
        ParticleSystem("Burning Fox") {
            EmitterDescription("Flames", capacity: 12_000, isEmitting: isEmitting) {
                ShapeModule(shape: .mesh)
                RateModule(birthRate: 8_000)
                LifetimeModule(range: 0.35...0.8)
                VelocityModule(velocity: [0, 0.5 * s, 0], spread: 0.25 * s)
                // Hot air rises.
                GravityModule(acceleration: [0, 1.8 * s, 0])
                DragModule(amount: 1.5)
                SizeOverLifeModule(curve: ParticleCurve([.init(0, 0.03 * s), .init(0.3, 0.09 * s), .init(1, 0.02 * s)]))
                ColorOverLifeModule(color: ParticleCurve([.init(0, [1, 0.9, 0.5, 1]), .init(0.35, [1, 0.45, 0.1, 0.8]), .init(1, [0.6, 0.05, 0.02, 0])]))
                SpriteModule(blendMode: .additive)
            }
            EmitterDescription("Embers", capacity: 1_000, isEmitting: isEmitting) {
                ShapeModule(shape: .mesh)
                RateModule(birthRate: 150)
                LifetimeModule(range: 1.2...2.5)
                VelocityModule(velocity: [0, 1.2 * s, 0], spread: 0.6 * s)
                GravityModule(acceleration: [0, 0.4 * s, 0])
                DragModule(amount: 0.6)
                SizeOverLifeModule(curve: .linear(from: 0.02 * s, to: 0.005 * s))
                ColorOverLifeModule(color: .linear(from: [1, 0.7, 0.3, 1], to: [1, 0.2, 0.05, 0]))
                SpriteModule(blendMode: .additive)
            }
            // Tiny, short-lived and dense: the surface itself seems to glow.
            EmitterDescription("Sparks", capacity: 30_000, isEmitting: isEmitting) {
                ShapeModule(shape: .mesh)
                RateModule(birthRate: 40_000)
                LifetimeModule(range: 0.4...0.8)
                VelocityModule(velocity: .zero, spread: 0.02 * s)
                GravityModule(acceleration: .zero)
                DragModule(amount: 0.1)
                SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.3, 0.012 * s), .init(1, 0)]))
                ColorOverLifeModule(color: .constant([0.3, 0.7, 1, 1]))
                SpriteModule(blendMode: .additive)
            }
            // Scale is noise frequency, so a bigger fox gets bigger swirls.
            ForceField.turbulence(strength: 1.2 * s, scale: 1.5 / s, speed: 0.6)
        }
    }
}
