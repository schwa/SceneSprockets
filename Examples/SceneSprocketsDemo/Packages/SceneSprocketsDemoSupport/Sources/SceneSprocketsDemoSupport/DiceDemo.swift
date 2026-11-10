import Foundation
import Metal
import MetalKit
import MetalSprocketsParticles
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import SceneSprocketsPhysics
import simd
import SwiftMesh
import SwiftUI

// Dice thrown into a wooden tray, with Jolt physics. Click, press Space, or wait to roll again. The dice are generated
// (DiceGeometry) and styled with PBR (DiceStyle); the tray texture is in Resources/Dice/README.md.
final class DiceDemo: DemoScene {
    // The tray's inside, in world units. The tray and dice are also used by the keynote's physics slide.
    static let trayWidth: Float = 6
    static let trayDepth: Float = 4
    private static let wallHeight: Float = 0.6
    private static let wallThickness: Float = 0.2
    private static let dieSize: Float = 0.5
    // The OBJ is 8 units across.
    static let dieScale = dieSize / 8

    private var physics: SceneGraphPhysicsWorld?
    private var dice: [SceneGraph.Node] = []
    private let diceHolder: SceneGraph.Node
    private var sinceRoll: Float = 0
    private var rolledSet = -1
    private var rolledStyle = -1
    private var isLinedUp = false
    private var sparklingDie: SceneGraph.Node?
    private var sparkler: SceneGraph.Node?

    // Gold stars shed in world space, so a tumbling die leaves a trail.
    private static let sparkles = ParticleSystem("Sparkles") {
        EmitterDescription("Stars", sprite: .star, capacity: 2_000) {
            ShapeModule(shape: .sphere(radius: 0.2))
            RateModule(birthRate: 250)
            LifetimeModule(range: 0.5...1.2)
            VelocityModule(velocity: [0, 0.4, 0], spread: 0.5)
            GravityModule(acceleration: [0, -0.6, 0])
            DragModule(amount: 1)
            SizeOverLifeModule(curve: ParticleCurve([.init(0, 0), .init(0.15, 0.09), .init(1, 0)]))
            ColorOverLifeModule(color: .linear(from: [1, 0.85, 0.4, 1], to: [1, 0.4, 0.8, 0]))
            SpriteModule(blendMode: .additive)
        }
        EmitterDescription("Glints", capacity: 2_000) {
            ShapeModule(shape: .sphere(radius: 0.18))
            RateModule(birthRate: 400)
            LifetimeModule(range: 0.2...0.5)
            VelocityModule(velocity: .zero, spread: 0.15)
            GravityModule(acceleration: .zero)
            DragModule(amount: 0)
            SizeOverLifeModule(curve: .linear(from: 0.03, to: 0))
            ColorOverLifeModule(color: .constant([1, 1, 0.9, 1]))
            SpriteModule(blendMode: .additive)
        }
    }
    private static let sets: [(name: String, kinds: [Kind])] = [
        ("D6", [.d6]),
        ("D&D Set", [.d4, .d6, .d8, .d10, .d12, .d20]),
        ("D20", [.d20]),
        // No dice: metal gears instead.
        ("Gears", [])
    ]
    private var generator = SystemRandomNumberGenerator()

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 6.5, 5.5]
        let target: SIMD3<Float> = [0, 0, 0.3]
        root.addChild(.camera(eye: eye, target: target))
        root.addChild(SceneGraph.Node(label: "Sun", transform: .camera(eye: [2.5, 7, 3], target: .zero), content: .light(Light(type: .directional, color: [1, 0.96, 0.9], intensity: 2.5))))
        var fill = Light(type: .point, color: [0.6, 0.7, 1], intensity: 20)
        fill.range = 20
        root.addChild(SceneGraph.Node(label: "Fill", trs: .init(translation: [-4, 4, 4]), content: .light(fill)))
        Self.buildTray(in: root)
        diceHolder = root.addChild(SceneGraph.Node(label: "Dice"))
        super.init(
            sceneGraph: SceneGraph(root: root),
            // Metal, glass and pearl dice show their environment, so it is brighter than for plastic.
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [0.08, 0.07, 0.06]), PBRMaterialRenderer(environmentIntensity: 1)],
            cameraMatrix: .camera(eye: eye, target: target),
            parameters: [
                .choice("Dice Set", Self.sets.map(\.name), default: 1),
                .choice("Style", ["Mixed"] + DiceStyle.allCases.map(\.rawValue)),
                .slider("Dice", 1...12, default: 6),
                .slider("Seconds per Roll", 2...10, default: 5),
                .slider("Throw Strength", 0.5...2, default: 1),
                // One large die per style, turning in place, to show the materials.
                .toggle("Line Up", default: false)
            ]
        )
        shadows = SceneGraphShadows(intensity: 0.65, softness: 2)
        physics = try? SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
        actions = [DemoAction("Roll", systemImage: "dice", shortcut: .space) { [weak self] in self?.roll() }]
        roll()
    }

    override func update(time _: Float, deltaTime: Float) {
        if self[flag: "Line Up"] != isLinedUp || (isLinedUp && (Int(self[value: "Dice Set"]) != rolledSet)) {
            isLinedUp = self[flag: "Line Up"]
            if isLinedUp {
                lineUp()
            } else {
                roll()
            }
        }
        if isLinedUp {
            for (index, die) in dice.enumerated() {
                die.trs.rotation = simd_quatf(angle: deltaTime * 0.6, axis: simd_normalize([0.3, 1, Float(index % 3) * 0.2])) * die.trs.rotation
            }
            return
        }
        sinceRoll += deltaTime
        if sinceRoll >= self[value: "Seconds per Roll"] || Int(self[value: "Dice"]) != dice.count || Int(self[value: "Dice Set"]) != rolledSet || Int(self[value: "Style"]) != rolledStyle {
            roll()
        }
        // Small fixed steps keep fast, small dice from passing through the walls.
        physics?.step(deltaTime: min(deltaTime, 1.0 / 30.0), collisionSteps: 2)
        if let sparkler, let sparklingDie {
            sparkler.trs.translation = sparklingDie.worldPosition
        }
    }

    override func didPick(_: SceneGraph.Hit?) {
        roll()
    }

    // Every style in a 4 × 3 grid over the tray, twice the rolling size, without physics.
    private func lineUp() {
        diceHolder.removeAllChildren()
        sparkler = nil
        sparklingDie = nil
        rolledSet = Int(self[value: "Dice Set"])
        let kinds = Self.sets[min(max(rolledSet, 0), Self.sets.count - 1)].kinds
        dice = DiceStyle.allCases.enumerated().compactMap { index, style in
            guard let die = kinds.isEmpty ? Self.makeGear(index) : Self.makeDie(kinds[index % kinds.count], style: style) else {
                return nil
            }
            die.physicsBody = nil
            let column = Float(index % 4), row = Float(index / 4)
            die.trs = .init(translation: [(column - 1.5) * 1.35, 0.6, (row - 1) * 1.25], rotation: simd_quatf(angle: Float(index) * 0.9, axis: simd_normalize([1, 1, 0.3])), scale: SIMD3(repeating: Self.dieScale * 2))
            diceHolder.addChild(die)
            return die
        }
    }

    // Replaces the dice with new ones thrown in from the front-left corner, tumbling.
    private func roll() {
        sinceRoll = 0
        diceHolder.removeAllChildren()
        let count = Int(self[value: "Dice"])
        let strength = self[value: "Throw Strength"]
        rolledSet = Int(self[value: "Dice Set"])
        rolledStyle = Int(self[value: "Style"])
        let kinds = Self.sets[min(max(rolledSet, 0), Self.sets.count - 1)].kinds
        // Mixed gives each die a different style, in a new order each roll.
        let styles = rolledStyle == 0 ? DiceStyle.allCases.shuffled(using: &generator) : [DiceStyle.allCases[min(rolledStyle - 1, DiceStyle.allCases.count - 1)]]
        dice = (0..<count).compactMap { index in
            // A set's kinds take turns, so six dice of the D&D set are one of each.
            guard let die = kinds.isEmpty ? Self.makeGear(index) : Self.makeDie(kinds[index % kinds.count], style: styles[index % styles.count]) else {
                return nil
            }
            let position = SIMD3<Float>(
                -Self.trayWidth / 2 + 0.6 + Float(index % 4) * 0.6,
                1.4 + Float(index / 4) * 0.6,
                Self.trayDepth / 2 - 0.6 - Float.random(in: 0...0.3, using: &generator)
            )
            let rotation = simd_quatf(angle: .random(in: 0...(2 * .pi), using: &generator), axis: simd_normalize(SIMD3<Float>.random(in: -1...1, using: &generator) + [0, 0.01, 0]))
            die.trs = .init(translation: position, rotation: rotation, scale: SIMD3(repeating: Self.dieScale))
            diceHolder.addChild(die)
            return die
        }
        // One die at random trails sparkles. They follow an unscaled node, not the die: its tiny scale would shrink
        // the emitter's spread and speeds too.
        sparklingDie = dice.randomElement(using: &generator)
        sparkler = sparklingDie.map { die in
            let node = diceHolder.addChild(SceneGraph.Node(label: "Sparkles", trs: .init(translation: die.worldPosition)))
            node.particleSystems = [SceneParticleSystem(Self.sparkles, seed: .random(in: 0 ... .max, using: &generator))]
            return node
        }
        guard let physics else {
            return
        }
        physics.sync()
        for die in dice {
            let velocity = SIMD3<Float>(.random(in: 4...7, using: &generator), .random(in: 0...1.5, using: &generator), .random(in: -4 ... -2, using: &generator)) * strength
            physics.setVelocity(velocity, of: die)
            physics.setAngularVelocity(SIMD3<Float>.random(in: -15...15, using: &generator), of: die)
        }
    }

    // A wooden floor and four walls, all static.
    static func buildTray(in root: SceneGraph.Node) {
        // Poly Haven's Dark Wood (CC0): color, normal, and roughness packed in green.
        let wood: any SceneSprockets.Material = {
            let loader = MTKTextureLoader(device: demoDevice)
            func texture(_ name: String, sRGB: Bool) -> MTLTexture? {
                Bundle.module.url(forResource: name, withExtension: "jpg", subdirectory: "Resources/Dice").flatMap {
                    try? loader.newTexture(URL: $0, options: [.SRGB: sRGB, .generateMipmaps: true, .origin: MTKTextureLoader.Origin.flippedVertically])
                }
            }
            guard let color = texture("DarkWood-Color", sRGB: true),
                  let normal = texture("DarkWood-Normal", sRGB: false),
                  let metallicRoughness = texture("DarkWood-MetallicRoughness", sRGB: false),
                  let placeholder = try? PBRMaterial.placeholderBinding(device: demoDevice)
            else {
                return BlinnPhongSceneMaterial.plastic([0.3, 0.1, 0.05], shininess: 24)
            }
            var bindings = Array(repeating: placeholder, count: Int(kPBRMaterialTextureCount.rawValue))
            let device = demoDevice
            func binding(_ texture: MTLTexture) -> PBRMaterial.Binding {
                // swiftlint:disable:next force_try
                try! .init(texture: texture, samplerDescriptor: placeholder.samplerDescriptor, device: device)
            }
            bindings[Int(kPBRTextureBaseColor.rawValue)] = binding(color)
            bindings[Int(kPBRTextureNormal.rawValue)] = binding(normal)
            bindings[Int(kPBRTextureMetallicRoughness.rawValue)] = binding(metallicRoughness)
            var uniforms = PBRMaterialUniforms.defaults(baseColor: [1, 1, 1, 1], metallic: 1, roughness: 1)
            uniforms.baseColor.enabled = 1
            uniforms.normal.enabled = 1
            uniforms.metallicRoughness.enabled = 1
            // A thin satin varnish.
            uniforms.clearcoatFactor = 0.3
            uniforms.clearcoatRoughnessFactor = 0.25
            guard let material = try? PBRMaterial(name: "Dark Wood", uniforms: uniforms, textureBindings: bindings, device: demoDevice) else {
                return BlinnPhongSceneMaterial.plastic([0.3, 0.1, 0.05], shininess: 24)
            }
            return PBRSceneMaterial(material)
        }()
        let tray = root.addChild(SceneGraph.Node(label: "Tray"))
        let outerWidth = trayWidth + 2 * wallThickness
        let floor = tray.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: outerWidth, height: 0.2, length: trayDepth + 2 * wallThickness), material: wood, trs: .init(translation: [0, -0.1, 0])))
        floor.physicsBody = .init(type: .static, shape: .boundingBox, friction: 0.6, restitution: 0.3)
        let walls: [(size: SIMD3<Float>, position: SIMD3<Float>)] = [
            ([outerWidth, wallHeight, wallThickness], [0, wallHeight / 2, -(trayDepth + wallThickness) / 2]),
            ([outerWidth, wallHeight, wallThickness], [0, wallHeight / 2, (trayDepth + wallThickness) / 2]),
            ([wallThickness, wallHeight, trayDepth], [-(trayWidth + wallThickness) / 2, wallHeight / 2, 0]),
            ([wallThickness, wallHeight, trayDepth], [(trayWidth + wallThickness) / 2, wallHeight / 2, 0])
        ]
        for wall in walls {
            let node = tray.addChild(SceneGraph.Node(label: "Wall", shape: .box(width: wall.size.x, height: wall.size.y, length: wall.size.z), material: wood, trs: .init(translation: wall.position)))
            node.physicsBody = .init(type: .static, shape: .boundingBox, friction: 0.4, restitution: 0.5)
        }
        // An invisible lid and invisible walls up to it, so a hard throw cannot leave the tray over the low walls.
        let lid = tray.addChild(SceneGraph.Node(label: "Lid", trs: .init(translation: [0, 3, 0])))
        lid.physicsBody = .init(type: .static, shape: .box(size: [outerWidth, 0.2, trayDepth]), friction: 0.2, restitution: 0.3)
        for wall in walls {
            let barrierHeight: Float = 3
            let barrier = tray.addChild(SceneGraph.Node(label: "Barrier", trs: .init(translation: [wall.position.x, barrierHeight / 2, wall.position.z])))
            barrier.physicsBody = .init(type: .static, shape: .box(size: [wall.size.x, barrierHeight, wall.size.z]), friction: 0.4, restitution: 0.5)
        }
    }

    // The dice in the assets, by number of faces.
    enum Kind: String, CaseIterable {
        case d4 = "D4", d6 = "D6", d8 = "D8", d10 = "D10", d12 = "D12", d20 = "D20"
    }

    // Gear mode: sizes and metals cycle with `index`. In the dice's units (a D6 is 8 across), so they share the scale.
    private static func makeGear(_ index: Int) -> SceneGraph.Node? {
        let teeth = [12, 18, 10, 24, 14][index % 5]
        let spec = GearSpec(teeth: teeth, module: 0.55, thickness: 2.4, holeRadius: 1.1)
        if gearMeshes[spec] == nil {
            gearMeshes[spec] = MetalMesh(mesh: .gear(spec), device: demoDevice, label: "Gear \(teeth)")
        }
        let metals: [(SIMD4<Float>, Float)] = [([0.85, 0.65, 0.3, 1], 0.3), ([0.75, 0.76, 0.78, 1], 0.22), ([0.9, 0.5, 0.35, 1], 0.35), ([0.35, 0.36, 0.4, 1], 0.45)]
        let metal = metals[index % metals.count]
        guard let mesh = gearMeshes[spec], let material = try? PBRSceneMaterial(baseColor: metal.0, metallic: 1, roughness: metal.1) else {
            return nil
        }
        let gear = SceneGraph.Node(label: "Gear \(teeth)", content: .mesh(mesh, material: material))
        gear.physicsBody = .init(type: .dynamic, shape: .convexHull, friction: 0.5, restitution: 0.3)
        return gear
    }

    private static var gearMeshes: [GearSpec: MetalMesh] = [:]

    // One die of `kind` in `style`, colliding as the convex hull of its mesh. Nil when the assets do not load.
    static func makeDie(_ kind: Kind, style: DiceStyle) -> SceneGraph.Node? {
        guard let parts = parts(for: kind) else {
            return nil
        }
        let key = "\(kind.rawValue) \(style.rawValue)"
        if materials[key] == nil {
            materials[key] = try? style.material(mask: parts.mask, normal: parts.normal)
        }
        guard let material = materials[key] else {
            return nil
        }
        let die = SceneGraph.Node(label: key, content: .mesh(parts.mesh, material: material))
        die.physicsBody = .init(type: .dynamic, shape: .convexHull, friction: 0.5, restitution: 0.35)
        return die
    }

    // Each kind's mesh, numbers mask and normal map, loaded on first use and shared between dice and styles.
    private struct Parts {
        var mesh: MetalMesh
        var mask: CGImage
        var normal: MTLTexture
    }

    private static var loadedParts: [Kind: Parts] = [:]
    private static var materials: [String: PBRSceneMaterial] = [:]

    private static func parts(for kind: Kind) -> Parts? {
        if let parts = loadedParts[kind] {
            return parts
        }
        let geometry = DiceGeometry(kind)
        guard let normal = try? MTKTextureLoader(device: demoDevice).newTexture(cgImage: geometry.normalMap, options: [.SRGB: false, .generateMipmaps: true]) else {
            return nil
        }
        let parts = Parts(mesh: MetalMesh(mesh: geometry.mesh, device: demoDevice, label: kind.rawValue), mask: geometry.mask, normal: normal)
        loadedParts[kind] = parts
        return parts
    }
}
