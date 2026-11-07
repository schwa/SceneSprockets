import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsGLTF
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsGizmos
import SceneSprocketsPBR
import SceneSprocketsPhysics
import SceneSprocketsShaderMaterial
import simd
import SwiftMesh
import SwiftUI

// "Introduction to SceneSprockets", presented like a keynote and built only from scene graph features (#98). Slides sit
// side by side along +X; the camera flies between them with Transaction.animate, and slides fade in and out with node
// opacity (hidden once faded so they cost nothing). Next/Previous are toolbar actions with the arrow keys; a click
// also advances, and Auto-advance moves on every few seconds.
public final class KeynoteDemo: DemoScene {
    private static let spacing: Float = 24
    // Basics first, then looks, animation and particles together, then the nerdier features, and UI, picking and
    // debugging last (#310). Slides are built by title, so reordering only means editing this list.
    public static let titles = [
        "SceneSprockets", "SceneView", "Scene Graph", "Shapes", "Materials", "Lights",
        "Shadows", "Fog", "Opacity & Fades", "Blend Modes", "Glass", "PBR Extensions", "Custom Shaders", "glTF & Model I/O",
        "Actions", "Implicit Animation", "Constraints", "Animation Blending", "Deformation",
        "Particles", "Mesh Emitters",
        "Physics", "Post-Processing", "Level of Detail", "Performance", "SwiftECS World",
        "Hit Testing", "Gizmos", "Debug Views",
        "Thank You"
    ]

    private let cameraNode: SceneGraph.Node
    private var slides: [SceneGraph.Node] = []
    private var current = 0
    private var sinceAdvance: Float = 0
    // 0 = no fog, 1 = the Fog slide's fog. Eases with the transition so the fog does not pop in (#333).
    private var fogAmount: Float = 0

    // Per-slide state: each is used only while its slide is showing.
    private let shadowRenderer = SceneGraphShadows(intensity: 0.75, softness: 2)
    private var shuffleCubes: [SceneGraph.Node] = []
    private var sinceShuffle: Float = 0
    private var blendMixer: SceneGraph.AnimationMixer?
    private var blendController: SceneGraph.AnimationController?
    private var importedPlayer: SceneGraph.AnimationPlayer?
    private var hitTargets: Set<ObjectIdentifier> = []
    private var physics: SceneGraphPhysicsWorld?
    private var physicsDice: SceneGraph.Node?
    private var sincePhysicsReset: Float = 0
    private var diceGenerator = SystemRandomNumberGenerator()
    private static let tubeJointCount = 7
    private var pbrExtensionPieces: [(node: SceneGraph.Node, axis: SIMD3<Float>, speed: Float)] = []
    private var burningFox: BurningFox?
    // The Thank You slide's fireworks, glass and lights, hidden until the title has been read (#317).
    private var finale: SceneGraph.Node?
    private var finaleTitle: SceneGraph.Node?
    private var finaleEmitters: [(node: SceneGraph.Node, system: ParticleSystem)] = []
    private var campfireLight: SceneGraph.Node?
    private var gradeLabels: [SceneGraph.Node] = []
    // The title slide's text: flat on that slide, extruded once the keynote moves on.
    private var introTitles: [SceneGraph.Node] = []
    private static let flatDepth: Float = 0.01
    // The title slide's text; leaving the slide, it breaks into one 3D block per letter that tumbles away (#311).
    private static let introTitleSpecs: [(text: String, size: Float, y: Float, color: SIMD3<Float>)] = [
        ("SceneSprockets", 1.2, 1.7, [0.95, 0.95, 0.97]),
        ("for MetalSprockets", 0.6, 0.5, [0.6, 0.65, 0.75])
    ]
    private struct TumblingLetter {
        var node: SceneGraph.Node
        var velocity: SIMD3<Float>
        var spinAxis: SIMD3<Float>
        var spinRate: Float
    }
    private var tumblingLetters: [TumblingLetter] = []
    // SwiftECS World slide.
    private var boids: KeynoteBoids?
    // Gizmos slide: the node it selects.
    private var gizmoTarget: SceneGraph.Node?
    // Debug Views slide: one label per mode, and the time on the current one.
    private var debugLabels: [SceneGraph.Node] = []
    private var debugIndex = 0
    private var sinceDebugMode: Float = 0
    private var gradeIndex = 0
    private var sinceGrade: Float = 0
    private var morphed: [SceneGraph.Node] = []
    private var bendingJoints: [SceneGraph.Node] = []
    // Level of Detail slide: spheres that move away from and toward the camera.
    private var detailed: [SceneGraph.Node] = []
    private var crates: [SceneGraph.Node] = []
    private static let crateGridSize = 22

    init() {
        let root = SceneGraph.Node(label: "Root")
        cameraNode = .camera(fieldOfView: 40, eye: Self.eye(for: 0), target: Self.target(for: 0))
        root.addChild(cameraNode)
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [0.05, 0.05, 0.07]), PBRMaterialRenderer(device: demoDevice), ShaderMaterialRenderer()],
            cameraMatrix: .camera(eye: Self.eye(for: 0), target: Self.target(for: 0)),
            parameters: [.choice("Slide", Self.titles), .toggle("Auto-advance", default: false), .slider("Seconds per Slide", 2...15, default: 6)]
        )
        usesSceneCamera = true
        for (index, title) in Self.titles.enumerated() {
            let slide = SceneGraph.Node(parent: root, label: "Slide \(index + 1): \(title)", trs: .init(translation: [Float(index) * Self.spacing, 0, 0]))
            build(slide: slide, title: title)
            Self.isolateLights(of: slide, index: index)
            slide.opacity = index == 0 ? 1 : 0
            slide.isVisible = index == 0
            slides.append(slide)
        }
        // Only the physics slide steps it. Gravity points down the tilted tray, so the dice fall as in a flat tray seen
        // at an angle.
        physics = try? SceneGraphPhysicsWorld(sceneGraph: sceneGraph, gravity: Self.trayTilt.act([0, -9.81, 0]))
        actions = [
            DemoAction("Previous", systemImage: "chevron.left", shortcut: .leftArrow) { [weak self] in self?.go(by: -1) },
            DemoAction("Next", systemImage: "chevron.right", shortcut: .rightArrow) { [weak self] in self?.go(by: 1) }
        ]
        publishNotes()
    }

    private static func eye(for index: Int) -> SIMD3<Float> {
        // Every slide uses the same camera height and angle, so transitions only fly sideways (#334). Slides that need
        // another view (Shadows, Physics) tilt their models instead.
        [Float(index) * spacing, 1.6, 13]
    }

    private static func target(for index: Int) -> SIMD3<Float> {
        [Float(index) * spacing, 1.1, 0]
    }

    override public func update(time: Float, deltaTime: Float) {
        // The settings' Slide picker (#309) jumps straight to the slide: flying across the deck shows only empty space
        // (#329).
        let picked = Int(self[value: "Slide"])
        if picked != current, slides.indices.contains(picked) {
            show(slide: picked)
        }
        updateSlide(time: time, deltaTime: deltaTime)
        guard self[flag: "Auto-advance"] else {
            sinceAdvance = 0
            return
        }
        sinceAdvance += deltaTime
        if sinceAdvance >= self[value: "Seconds per Slide"] {
            go(by: current == slides.count - 1 ? -current : 1)
        }
    }

    // Clicking a hit-test target makes it jump; any other click advances.
    override public func didPick(_ hit: SceneGraph.Hit?) {
        // Taps do not select: only the Gizmos slide shows a selection, always its own box (#328).
        selectedNodeID = currentTitle == "Gizmos" ? gizmoTarget?.id : nil
        if let hit, let target = hitTarget(containing: hit.node) {
            target.run(.group([
                .sequence([.move(by: [0, 1, 0], duration: 0.25), .move(by: [0, -1, 0], duration: 0.25)]),
                .rotate(by: .pi * 2, around: [0, 1, 0], duration: 0.5)
            ]), forKey: "hop")
            return
        }
        go(by: 1)
    }

    private func hitTarget(containing node: SceneGraph.Node) -> SceneGraph.Node? {
        var candidate: SceneGraph.Node? = node
        while let node = candidate {
            if hitTargets.contains(ObjectIdentifier(node)) {
                return node
            }
            candidate = node.parent
        }
        return nil
    }

    private var currentTitle: String {
        Self.titles[current]
    }

    // Presenter notes by slide title (#331, #332).
    static let notes: [String: String] = [
        "SceneSprockets": """
        • SceneSprockets is a scene graph for Swift, built on MetalSprockets.
        • Every slide in this talk is a live scene, rendered with the library.
        • Watch the title: it breaks into 3D letters when we move on.
        """,
        "SceneView": """
        • SceneView is the SwiftUI view: give it a scene graph and some renderers.
        • Options such as allowsCameraControl give you orbit and zoom for free.
        • Shadows are one more argument.
        """,
        "Scene Graph": """
        • A tree of nodes. Each node has a transform, and children move with their parent.
        • The planet orbits because its parent spins; the moon rides along on the planet.
        • Nodes are stored in a SwiftECS world, so large scenes stay fast.
        """,
        "Shapes": """
        • Built-in shapes: box, sphere, cylinder, teapot, cone, capsule, torus, plus 3D text and extruded paths.
        • One line each: Node(shape:material:device:).
        • The Utah teapot is a built-in shape now.
        """,
        "Materials": """
        • Top row: Blinn-Phong, getting shinier from left to right.
        • Middle row: PBR metals, from rough to polished.
        • Bottom row: PBR plastics; the last two have a clear coat, like car paint.
        • Both material types render in the same scene.
        """,
        "Lights": """
        • Point, spot and directional lights are nodes like everything else.
        • These three colored point lights orbit because their parent node spins.
        • Range limits how far each light reaches.
        """,
        "Shadows": """
        • Shadow maps from a directional sun light.
        • Turn them on in SceneView with SceneGraphShadows; softness and intensity are settings.
        """,
        "Fog": """
        • Distance fog: one property on the scene graph.
        • The pillars fade into the fog between the start and end distances.
        """,
        "Opacity & Fades": """
        • Node opacity is inherited: fade a parent and its children fade too.
        • fadeIn and fadeOut are actions. These slide transitions use them.
        """,
        "Blend Modes": """
        • Each material has a render state: blend mode, fill mode, culling, depth.
        • Additive blending mixes the colored lights; the wireframe uses the lines fill mode.
        """,
        "Glass": """
        • PBR transmission: the glass refracts what is behind it.
        • Blinn-Phong and PBR objects behind the glass are refracted the same way.
        """,
        "PBR Extensions": """
        • glTF PBR extensions: sheen, clear coat, iridescence, diffuse transmission and more.
        • Each one is a few uniforms on the material.
        """,
        "Custom Shaders": """
        • ShaderMaterial runs your own Metal vertex and fragment functions.
        • Built-in samples: normals and rim lighting. Parameters such as time pass straight to the shader.
        """,
        "glTF & Model I/O": """
        • Load glTF files and anything Model I/O reads (OBJ, USD) into a scene graph.
        • The plant is glTF with its animation; the fireflies carry point lights.
        """,
        "Actions": """
        • Actions are like SpriteKit and SceneKit actions: move, rotate, scale, fade, wait.
        • Combine them with sequence, group and repeatForever. Timing modes ease them in and out.
        """,
        "Implicit Animation": """
        • Change properties inside a transaction and they animate, like SwiftUI's withAnimation.
        • The cubes shuffle to new random positions every few seconds.
        """,
        "Constraints": """
        • Constraints run after actions: look at, distance, follow and more.
        • Each cone points its tip at the moving ball.
        """,
        "Animation Blending": """
        • Animation clips mix with weights, for example walk into run.
        • The controller blends a bounce and a sway; the mixer applies the result.
        """,
        "Deformation": """
        • Morph targets blend shapes with weights: the blob bumps and squashes.
        • Skins bend meshes with joints: the tube follows its skeleton.
        """,
        "Particles": """
        • GPU particle systems from MetalSprocketsParticles, attached to nodes.
        • Campfire, geyser and fireworks are built-in presets.
        """,
        "Mesh Emitters": """
        • Particles can be born on a mesh surface.
        • The fire follows the fox's skinned, walking mesh, frame by frame.
        """,
        "Physics": """
        • Rigid body physics: give a node a physics body and step the world.
        • Each die uses a convex hull collision shape. They land on real faces.
        """,
        "Post-Processing": """
        • Post-processing on the whole frame: color grading, contrast, saturation, vignette and more.
        • The slide cycles through a few looks, such as noir.
        """,
        "Level of Detail": """
        • Each node can switch to simpler meshes as it moves away from the camera.
        • The far shapes switch to meshes with fewer triangles.
        """,
        "Performance": """
        • The same mesh and material draw as one instanced call.
        • Nodes outside the view are culled, so thousands of nodes stay fast.
        """,
        "SwiftECS World": """
        • The scene graph's nodes live in a SwiftECS world, which you can use directly.
        • These boids are a SwiftECS system that writes node transforms in bulk.
        """,
        "Hit Testing": """
        • Click a shape: SceneView returns the hit node, and the shape hops.
        • hitTest(ray) gives every hit, nearest first, with position and normal.
        """,
        "Gizmos": """
        • Transform gizmos move, rotate and scale nodes; a selection outline shows what is selected.
        • Both come from SceneSprocketsGizmos and plug into SceneView.
        """,
        "Debug Views": """
        • One switch replaces every material with a debug view: normals, texture coordinates, UV checker, world position and more.
        • Useful when a model looks wrong.
        """,
        "Thank You": """
        • Thank you!
        • Everything in the finale is the same library: particles, lights, glass, metal and actions.
        • Questions?
        """
    ]

    // Sends the current slide to the presenter notes window.
    private func publishNotes() {
        let model = PresenterNotes.shared
        model.slideIndex = current
        model.slideCount = Self.titles.count
        model.title = currentTitle
        model.notes = Self.notes[currentTitle] ?? ""
        model.nextTitle = current + 1 < Self.titles.count ? Self.titles[current + 1] : nil
    }

    private func updateFog(deltaTime: Float) {
        let target: Float = currentTitle == "Fog" ? 1 : 0
        fogAmount += min(max(target - fogAmount, -deltaTime), deltaTime)
        guard fogAmount > 0 else {
            sceneGraph.fog = nil
            return
        }
        // Pushes the fog out of sight as the amount drops.
        let distance = (1 - fogAmount) * 300
        sceneGraph.fog = SceneGraph.Fog(color: [0.05, 0.06, 0.1, 1], startDistance: 12 + distance, endDistance: 34 + distance)
    }

    private func updateSlide(time: Float, deltaTime: Float) {
        updateFog(deltaTime: deltaTime)
        updateTumblingLetters(deltaTime: deltaTime)
        switch currentTitle {
        case "Implicit Animation":
            sinceShuffle += deltaTime
            if sinceShuffle >= 1.6 {
                sinceShuffle = 0
                shuffle()
            }
        case "Animation Blending":
            guard var controller = blendController, let blendMixer else {
                return
            }
            // The blend weight sweeps from bounce to sway and back.
            controller.blend([0, 1], parameter: (sin(time * 0.8) + 1) / 2)
            controller.advance(by: deltaTime)
            blendMixer.apply(controller.layers)
            blendController = controller
        case "PBR Extensions":
            for piece in pbrExtensionPieces {
                piece.node.trs.rotation = simd_normalize(simd_quatf(angle: deltaTime * piece.speed, axis: piece.axis) * piece.node.trs.rotation)
            }
        case "Deformation":
            let weights = [(sin(time * 1.3) + 1) / 2, max(0, sin(time * 0.7))]
            for node in morphed {
                node.morphWeights = weights
            }
            // The same total bend as before (1.4 radians at the tip), shared by every bending joint.
            let rotation = simd_quatf(angle: sin(time * 1.5) * 1.4 / Float(Self.tubeJointCount - 1), axis: [0, 0, 1])
            for joint in bendingJoints {
                joint.trs.rotation = rotation
            }
        case "Level of Detail":
            // Out of phase, 11 to 27 units from the camera, so each crosses both switch distances.
            for (index, node) in detailed.enumerated() {
                node.trs.translation.z = -6 + sin(time * 0.8 + Float(index) * 2.1) * 8
            }
        case "Performance":
            waveCrates(time: time)
        case "Post-Processing":
            updateGrade(deltaTime: deltaTime)
        case "Debug Views":
            updateDebugView(deltaTime: deltaTime)
        case "SwiftECS World":
            boids?.step(deltaTime: deltaTime)
        case "Gizmos":
            let modes: [TransformGizmo.Mode] = [.translate, .rotate, .scale]
            gizmoMode = modes[Int(time / 2.5) % modes.count]
        case "glTF & Model I/O":
            importedPlayer?.advance(by: deltaTime)
        case "Particles":
            flickerCampfire(time: time)
        case "Mesh Emitters":
            burningFox?.update(sceneGraph: sceneGraph, deltaTime: deltaTime)
        case "Physics":
            sincePhysicsReset += deltaTime
            if sincePhysicsReset > 5 {
                resetPhysics()
            }
            // As in DiceDemo: small fixed steps keep fast, small dice from passing through the walls.
            physics?.step(deltaTime: min(deltaTime, 1.0 / 30.0), collisionSteps: 2)
        default:
            break
        }
    }

    // Shadows and fog apply to the whole scene, so they are switched on only for their slides.
    private func applySceneSettings() {
        shadows = currentTitle == "Shadows" ? shadowRenderer : nil
        // The Gizmos slide selects its box; other slides show no selection.
        let showsGizmo = currentTitle == "Gizmos"
        showsSelectionOutline = showsGizmo
        selectedNodeID = showsGizmo ? gizmoTarget?.id : nil
        gizmoMode = showsGizmo ? .translate : nil
        // A debug view replaces every material in the view, so it is on only for its slide.
        debugIndex = 0
        sinceDebugMode = 0
        debugMode = nil
        if currentTitle == "Post-Processing" {
            gradeIndex = 0
            sinceGrade = 0
        } else {
            sceneGraph.postProcessing = nil
        }
    }

    // `visibleAfter` is how long until the slide has faded in.
    private func resetCurrentSlide(visibleAfter: Float) {
        if currentTitle == "Thank You" {
            startFinale(after: visibleAfter + 0.5)
        }
        if currentTitle == "Physics" {
            resetPhysics()
        }
        // The fox walks in unharmed each time its slide comes up, then catches fire.
        if currentTitle == "Mesh Emitters" {
            burningFox?.restart()
        }
        Self.isolateLights(of: slides[current], index: current)
    }

    // Both slides show during a transition, so each slide's lights light only that slide (#308). Runs again on
    // transitions because some slides add nodes later.
    private static func isolateLights(of slide: SceneGraph.Node, index: Int) {
        let bit: UInt = 1 << UInt(index % UInt.bitWidth)
        func tag(_ node: SceneGraph.Node) {
            node.categoryBitMask = bit
            if case .light = node.content {
                node.lightCategoryBitMask = bit
            }
            node.children.forEach(tag)
        }
        tag(slide)
    }

    // Flies the camera to the slide and cross-fades the slides.
    private func go(by step: Int) {
        let next = min(max(current + step, 0), slides.count - 1)
        guard next != current else {
            return
        }
        sinceAdvance = 0
        let previous = slides[current]
        // Shadows stay on while the Shadows slide is on screen, so they do not pop in or out (#326). Light masks keep the
        // sun's shadows off the other slide.
        if Self.titles[current] == "Shadows" || Self.titles[next] == "Shadows" {
            shadows = shadowRenderer
        }
        // Leaving the title slide, its flat titles break into 3D letters that fall and tumble out of frame, then the
        // deck cross-fades. Coming back, the flat titles return.
        let breaksTitles = current == 0
        let delay: Float = breaksTitles ? 0.9 : 0
        if breaksTitles {
            breakIntroTitles()
        } else if next == 0 {
            restoreIntroTitles()
        }
        previous.run(.sequence([.wait(duration: delay + 0.2), .fadeOut(duration: 0.6), .run { $0.isVisible = false }]), forKey: "fade")
        let incoming = slides[next]
        incoming.isVisible = true
        incoming.run(.sequence([.wait(duration: delay + 0.4), .fadeIn(duration: 0.8)]), forKey: "fade")
        let cameraNode = cameraNode
        let fly = SceneGraph.Action.run { _ in
            SceneGraph.Transaction.animate(duration: 1.2, timingMode: .easeInEaseOut) {
                cameraNode.transform = .camera(eye: Self.eye(for: next), target: Self.target(for: next))
            }
        }
        cameraNode.run(.sequence([.wait(duration: delay), fly]), forKey: "fly")
        current = next
        // Keeps the Slide picker in step with arrow keys, clicks and auto-advance.
        values["Slide"] = Float(current)
        // The incoming slide finishes fading in 1.2 s after the delay.
        resetCurrentSlide(visibleAfter: delay + 1.2)
        // Scene-wide settings (shadows, fog, post-processing) change once the old slide has faded out (#308).
        let settings = SceneGraph.Action.run { [weak self] _ in self?.applySceneSettings() }
        sceneGraph.root.run(.sequence([.wait(duration: delay + 0.8), settings]), forKey: "settings")
        publishNotes()
        hierarchyDidChange()
    }

    // Jumps to a slide with no transition.
    public func show(slide index: Int) {
        for (slideIndex, slide) in slides.enumerated() {
            slide.removeAction(forKey: "fade")
            slide.opacity = slideIndex == index ? 1 : 0
            slide.isVisible = slideIndex == index
        }
        cameraNode.transform = .camera(eye: Self.eye(for: index), target: Self.target(for: index))
        cameraNode.removeAction(forKey: "fly")
        restoreIntroTitles()
        current = index
        values["Slide"] = Float(index)
        sinceAdvance = 0
        sceneGraph.root.removeAction(forKey: "settings")
        fogAmount = currentTitle == "Fog" ? 1 : 0
        updateFog(deltaTime: 0)
        resetCurrentSlide(visibleAfter: 0)
        applySceneSettings()
        publishNotes()
    }

    public var slideCount: Int {
        slides.count
    }

    // MARK: - Slides

    // By title, so the deck can be reordered by editing `titles` (#310).
    private func build(slide: SceneGraph.Node, title: String) {
        switch title {
        case "SceneSprockets":
            // Flat (2D) until the keynote moves on; go(by:) breaks them into tumbling 3D letters.
            introTitles = Self.introTitleSpecs.map { spec in
                let title = addTitle(spec.text, size: spec.size, y: spec.y, color: spec.color, to: slide)
                title.trs.scale.z = Self.flatDepth
                return title
            }
            addLight(to: slide, at: [3, 5, 5], color: [1, 0.95, 0.9], intensity: 60)
        case "Scene Graph":
            addTitle(title, y: 4, to: slide)
            sceneGraphSlide(slide)
            addCode("""
            let orbit = Node(parent: sun, label: "Planet Orbit")
            orbit.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 8)))
            let planet = Node(parent: orbit, shape: .sphere(radius: 0.4), material: blue, device: device)
            planet.trs.translation = [3.2, 0, 0]
            """, to: slide)
        case "Shapes":
            addTitle(title, y: 4, to: slide)
            shapesSlide(slide)
            addCode("""
            Node(shape: .box(width: 1, height: 1, length: 1), material: red, device: device)
            Node(shape: .torus(ringRadius: 0.5, pipeRadius: 0.18), material: pink, device: device)
            Node(shape: .teapot(diameter: 2.2), material: porcelain, device: device)
            Node(shape: .text("Hello", fontName: "Helvetica-Bold", fontSize: 1), material: white, device: device)
            """, to: slide)
        case "Materials":
            addTitle(title, y: 4, to: slide)
            materialsSlide(slide)
            addCode("""
            BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.9, 0.35, 0.25]),
                                    specular: .color(0.5), shininess: 44)
            try PBRSceneMaterial(device: device, baseColor: [0.95, 0.75, 0.3, 1],
                                 metallic: 1, roughness: 0.3)
            """, to: slide)
        case "Lights":
            addTitle(title, y: 4, to: slide)
            lightsSlide(slide)
            addCode("""
            var light = Light(type: .point, color: [1, 0.2, 0.2], intensity: 25)
            light.range = 14
            Node(parent: pivot, content: .light(light))
            """, to: slide)
        case "Actions":
            addTitle(title, y: 4, to: slide)
            actionsSlide(slide)
            addCode("""
            var up = Action.move(by: [0, 2, 0], duration: 0.6)
            up.timingMode = .easeInEaseOut
            let down = up.reversed()
            let spin = Action.rotate(by: .pi, around: [0, 1, 0], duration: 0.6)
            cube.run(.repeatForever(.sequence([.group([up, spin]), down, .wait(duration: 0.8)])))
            """, to: slide)
        case "Constraints":
            addTitle(title, y: 4, to: slide)
            constraintsSlide(slide)
            addCode("""
            // Point each cone's tip (+Y) at the ball.
            cone.constraints = [.lookAt(target: ball, localFront: [0, 1, 0])]
            """, to: slide)
        case "Opacity & Fades":
            addTitle(title, y: 4, to: slide)
            fadesSlide(slide)
            addCode("""
            sphere.run(.repeatForever(.sequence([.fadeOut(duration: 1), .fadeIn(duration: 1)])))
            slide.opacity = 0.5 // children inherit it
            """, to: slide)
        case "Blend Modes":
            addTitle(title, y: 4, to: slide)
            blendModesSlide(slide)
            addCode("""
            BlinnPhongSceneMaterial(..., emission: .color(orange),
                renderState: MaterialRenderState(blendMode: .multiply))
            // .alpha, .add, .subtract, .multiply, .screen, .replace
            """, to: slide)
        default:
            buildLaterSlide(slide, title: title)
        }
    }

    private func buildLaterSlide(_ slide: SceneGraph.Node, title: String) {
        if title == "Thank You" {
            finaleTitle = addTitle(title, size: 1.6, y: 1.5, to: slide)
            addLight(to: slide, at: [0, 4, 6], intensity: 60)
            finaleSlide(slide)
            return
        }
        addTitle(title, y: 4, to: slide)
        switch title {
        case "Glass":
            glassSlide(slide)
            addCode("""
            let glass = try PBRSceneMaterial(device: device, roughness: 0)
            glass.pbrMaterial.uniforms.transmissionFactor = 1
            // Blinn-Phong and PBR objects behind it are refracted alike.
            """, to: slide)
        case "Shadows":
            shadowsSlide(slide)
            addCode("""
            let sun = Node(content: .light(Light(type: .directional, intensity: 1.5)))
            sun.trs.translation = [3, 6, 4]
            sun.look(at: .zero)
            SceneView(sceneGraph: scene, renderers: renderers,
                      shadows: SceneGraphShadows(intensity: 0.75, softness: 2))
            """, to: slide)
        case "Custom Shaders":
            customShadersSlide(slide)
            addCode("""
            let normals = try ShaderMaterial.normals()
            let rim = try ShaderMaterial.rim(color: [0.3, 0.8, 1, 1])
            ShaderMaterial(vertexShader: vertex, fragmentShader: fragment,
                           parameters: ["time": .float(t)])
            """, to: slide)
        case "PBR Extensions":
            pbrExtensionsSlide(slide)
            addCode("""
            uniforms.sheenColorFactor = [1, 0.95, 0.9] * 0.25
            uniforms.diffuseTransmissionFactor = 0.9
            uniforms.clearcoatFactor = 0.25
            uniforms.iridescenceFactor = 1 // pearls
            """, to: slide)
        case "Particles":
            particlesSlide(slide)
            addCode("""
            import MetalSprocketsParticlesSamples

            campfire.particleSystems = [SceneParticleSystem(.campfire)]
            geyser.particleSystems = [SceneParticleSystem(.geyser)]
            sky.particleSystems = [SceneParticleSystem(.fireworks)]
            """, to: slide)
        case "Mesh Emitters":
            meshEmittersSlide(slide)
            addCode("""
            ShapeModule(shape: .mesh) // born on the fox's surface
            emitter.mesh = try EmitterMesh(device: device, positions: rest, indices: indices)
            let skinned = entry.deformed(revision: sceneGraph.revision)
            emitter.mesh?.setDeformedPositions(skinned.positions, stride: stride)
            """, to: slide)
        case "Deformation":
            deformationSlide(slide)
            addCode("""
            blob.morphTargets = [bumps, squash]
            blob.morphWeights = [0.5, 0.2]
            tube.skin = Skin(joints: joints, inverseBindMatrices: inverseBind)
            """, to: slide)
        case "Level of Detail":
            levelOfDetailSlide(slide)
            addCode("""
            node.levelsOfDetail = [
                LevelOfDetail(mesh: medium, distance: 15),
                LevelOfDetail(mesh: low, distance: 22),
            ]
            """, to: slide)
        case "Performance":
            performanceSlide(slide)
            addCode("""
            // Same mesh + material: one instanced draw per color.
            // Nodes outside the view are culled.
            Node(parent: grid, content: .mesh(box, material: crate))
            """, to: slide)
        case "SwiftECS World":
            addLight(to: slide, at: [2, 6, 5], intensity: 70)
            addLight(to: slide, at: [-4, 3, -2], color: [0.6, 0.7, 1], intensity: 30)
            boids = KeynoteBoids(sceneGraph: sceneGraph, parent: slide)
            addCode("""
            sceneGraph.world[boid.id]?.set(Velocity(value: v))
            let flock = System("flock")
                .query(Write<NodeTransformComponent>(), Write<Velocity>())
                .each { context, transform, velocity in /* steer, move */ }
            try sceneGraph.world.run(flock, deltaTime: deltaTime)
            """, to: slide)
        case "Gizmos":
            gizmosSlide(slide)
            addCode("""
            SceneView(sceneGraph: scene, renderers: renderers,
                      manipulator: TransformGizmo(target: box, mode: .rotate),
                      overlay: { viewport in
                          try outline.element(nodes: [box], sceneGraph: scene, viewport: viewport)
                      })
            """, to: slide)
        case "Debug Views":
            debugViewsSlide(slide)
            addCode("""
            SceneView(sceneGraph: scene, renderers: renderers,
                      debugMode: .normals)  // .uvChecker, .wireframe, ...
            """, to: slide)
        case "Post-Processing":
            postProcessingSlide(slide)
            addCode("""
            // Noir
            sceneGraph.postProcessing = PostProcessing(contrast: 1.8, saturation: 0,
                                                       vignetteIntensity: 0.9, vignetteRadius: 0.35)
            """, to: slide)
        case "Fog":
            fogSlide(slide)
            addCode("""
            sceneGraph.fog = SceneGraph.Fog(color: [0.05, 0.06, 0.1, 1],
                                            startDistance: 12, endDistance: 34)
            """, to: slide)
        case "Implicit Animation":
            implicitAnimationSlide(slide)
            addCode("""
            SceneGraph.Transaction.animate(duration: 0.8, timingMode: .easeInEaseOut) {
                for cube in cubes {
                    cube.trs.translation = randomPosition()
                }
            }
            """, to: slide)
        case "Animation Blending":
            animationBlendingSlide(slide)
            addCode("""
            let mixer = AnimationMixer(clips: [bounce, sway])
            var controller = AnimationController(clips: [bounce, sway])
            controller.blend([0, 1], parameter: weight)
            controller.advance(by: deltaTime)
            mixer.apply(controller.layers)
            """, to: slide)
        case "glTF & Model I/O":
            importSlide(slide)
            addCode("""
            let plant = try GLTFAsset(url: plantURL, device: device).makeSceneGraph(device: device)
            let pedestal = try ModelIOSceneGraph(url: objURL, device: device)
            player = AnimationPlayer(clip: plant.animations[0]) // fireflies with point lights
            """, to: slide)
        case "Hit Testing":
            hitTestingSlide(slide)
            addCode("""
            // Click a shape.
            SceneView(sceneGraph: sceneGraph, renderers: [BlinnPhongMaterialRenderer()]) { hit in
                hit?.node.run(.move(by: [0, 1, 0], duration: 0.25))
            }
            let hits = sceneGraph.hitTest(ray) // nearest first
            """, to: slide)
        case "Physics":
            physicsSlide(slide)
            addCode("""
            die.physicsBody = .init(type: .dynamic, shape: .convexHull)
            let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
            physics.setAngularVelocity(spin, of: die)
            physics.step(deltaTime: deltaTime)
            """, to: slide)
        case "SceneView":
            sceneViewSlide(slide)
            addCode("""
            struct ContentView: View {
                let sceneGraph = SceneGraph(root: root)
                var body: some View {
                    SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl],
                              renderers: [BlinnPhongMaterialRenderer()],
                              shadows: SceneGraphShadows())
                }
            }
            """, to: slide)
        default:
            break
        }
    }

    // White extruded text, centered on x = 0 of `parent`, baseline at `y`, lit by its own light.
    @discardableResult
    private func addTitle(_ text: String, size: Float = 0.9, y: Float, color: SIMD3<Float> = [0.95, 0.95, 0.97], to parent: SceneGraph.Node) -> SceneGraph.Node {
        let holder = SceneGraph.Node(parent: parent, label: "Title \"\(text)\"", trs: .init(translation: [0, y, 0]))
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(color * 0.4), specular: .color(0.3), shininess: 32, emission: .color(color * 0.6))
        let label = SceneGraph.Node(parent: holder, shape: .text(text, fontName: "Helvetica-Bold", fontSize: size, extrusionDepth: size * 0.15), material: material, device: demoDevice)
        if let bounds = label.meshBounds {
            label.trs.translation.x = -(bounds.min.x + bounds.max.x) / 2
        }
        // Titles are not part of the scene: no shadows on the Shadows slide's floor.
        if case let .mesh(mesh, materials, _, receivesShadow) = label.content {
            label.content = .mesh(mesh, materials: materials, castsShadow: false, receivesShadow: receivesShadow)
        }
        return holder
    }

    // A code panel below the slide's live content, tilted a little toward the camera.
    private func addCode(_ code: String, to slide: SceneGraph.Node) {
        guard let panel = CodePanel.node(code: code, device: demoDevice) else {
            return
        }
        panel.trs = .init(translation: [0, -1.6, 1.5], rotation: simd_quatf(angle: -0.15, axis: [1, 0, 0]))
        slide.addChild(panel)
    }

    // Lights reach only their own slide.
    @discardableResult
    private func addLight(to parent: SceneGraph.Node, at position: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float) -> SceneGraph.Node {
        var light = Light(type: .point, color: color, intensity: intensity)
        light.range = 14
        return SceneGraph.Node(parent: parent, label: "Light", trs: .init(translation: position), content: .light(light))
    }

    private func sceneGraphSlide(_ slide: SceneGraph.Node) {
        // A sun with planets, a moon and a ring: each orbit is a parent node that turns, and children ride along. The
        // system is tilted toward the camera so the orbits read as ellipses (#343).
        let system = SceneGraph.Node(parent: slide, label: "Solar System", trs: .init(translation: [0, 1.9, 0], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0])))
        var sunlight = Light(type: .point, color: [1, 0.9, 0.75], intensity: 45)
        sunlight.range = 30
        _ = SceneGraph.Node(parent: system, label: "Sunlight", content: .light(sunlight))
        // A dim fill from the camera side, so the planets' night sides are not pure black.
        addLight(to: slide, at: [0, 4, 10], color: [0.4, 0.5, 0.8], intensity: 6)
        let sun = SceneGraph.Node(parent: system, label: "Sun", shape: .sphere(radius: 0.75), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 0.7, 0.25])), device: demoDevice)
        func pbr(_ color: SIMD3<Float>, metallic: Float = 0, roughness: Float) -> any SceneSprockets.Material {
            (try? PBRSceneMaterial(device: demoDevice, baseColor: SIMD4(color, 1), metallic: metallic, roughness: roughness)) ?? BlinnPhongSceneMaterial.plastic(color)
        }
        let pathMaterial = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.25, 0.27, 0.35]), renderState: MaterialRenderState(fillMode: .lines))
        // (radius, size, period, color, roughness)
        let planets: [(Float, Float, Float, SIMD3<Float>, Float)] = [(1.6, 0.18, 5, [0.75, 0.45, 0.3], 0.9), (3.2, 0.4, 8, [0.3, 0.55, 1], 0.35), (4.3, 0.3, 13, [0.9, 0.78, 0.55], 0.6)]
        for (index, (radius, size, period, color, roughness)) in planets.enumerated() {
            _ = SceneGraph.Node(parent: sun, label: "Orbit Path", shape: .torus(ringRadius: radius, pipeRadius: 0.004), material: pathMaterial, device: demoDevice)
            // Parented to the sun, as the code panel shows; the sun does not turn, so only the orbit spins the planet.
            let orbit = SceneGraph.Node(parent: sun, label: "Planet Orbit", trs: .init(rotation: simd_quatf(angle: Float(index) * 2.1, axis: [0, 1, 0])))
            orbit.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: period)))
            let planet = SceneGraph.Node(parent: orbit, label: "Planet", shape: .sphere(radius: size), material: pbr(color, roughness: roughness), device: demoDevice, trs: .init(translation: [radius, 0, 0]))
            planet.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 3)))
            switch index {
            case 1:
                let moonOrbit = SceneGraph.Node(parent: planet, label: "Moon Orbit")
                moonOrbit.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 2)))
                _ = SceneGraph.Node(parent: moonOrbit, label: "Moon", shape: .sphere(radius: 0.1), material: pbr([0.8, 0.8, 0.82], roughness: 0.8), device: demoDevice, trs: .init(translation: [0.7, 0, 0]))
            case 2:
                // The ring is a child of the planet: it tilts and spins with it.
                let ring = SceneGraph.Node(parent: planet, label: "Ring", shape: .torus(ringRadius: 0.58, pipeRadius: 0.06), material: pbr([0.85, 0.75, 0.6], metallic: 0.3, roughness: 0.4), device: demoDevice, trs: .init(rotation: simd_quatf(angle: 0.35, axis: [0, 0, 1])))
                ring.trs.scale = [1, 0.15, 1]
            default:
                break
            }
        }
    }

    private func shapesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 70)
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.box(width: 1, height: 1, length: 1), [1, 0.4, 0.3]),
            (.sphere(radius: 0.6), [1, 0.8, 0.3]),
            (.cylinder(radius: 0.5, height: 1.2), [0.4, 0.9, 0.4]),
            // The diameter spans spout to handle, so the body is about half of it.
            (.teapot(diameter: 2.2), [0.95, 0.93, 0.88]),
            (.cone(bottomRadius: 0.6, height: 1.2), [0.3, 0.8, 1]),
            (.capsule(capRadius: 0.4, height: 1.4), [0.6, 0.5, 1]),
            (.torus(ringRadius: 0.5, pipeRadius: 0.18), [1, 0.5, 0.8])
        ]
        for (index, (shape, color)) in shapes.enumerated() {
            let node = SceneGraph.Node(parent: slide, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), device: demoDevice, trs: .init(translation: [Float(index) * 1.6 - 4.8, 1.2, 0]))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 5 + Float(index))))
        }
    }

    private func materialsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 5, 6], intensity: 80)
        addLight(to: slide, at: [-6, 2, 4], color: [0.6, 0.7, 1], intensity: 30)
        // Top row Blinn-Phong, getting shinier; middle row PBR metals, then PBR plastics, both from rough to smooth.
        let shapes: [SceneGraph.Shape] = [
            .sphere(radius: 0.55), .torus(ringRadius: 0.42, pipeRadius: 0.17), .box(width: 0.8, height: 0.8, length: 0.8),
            .capsule(capRadius: 0.3, height: 1.1), .cone(topRadius: 0, bottomRadius: 0.5, height: 1), .cylinder(radius: 0.4, height: 0.9)
        ]
        let paints: [SIMD3<Float>] = [[0.9, 0.3, 0.25], [0.95, 0.6, 0.2], [0.9, 0.85, 0.3], [0.35, 0.8, 0.45], [0.3, 0.55, 0.95], [0.7, 0.4, 0.9]]
        let metals: [SIMD3<Float>] = [[1, 0.77, 0.34], [0.95, 0.64, 0.54], [0.97, 0.96, 0.91], [0.56, 0.57, 0.58], [0.62, 0.6, 0.66], [1, 0.86, 0.57]]
        let plastics: [SIMD3<Float>] = [[0.8, 0.1, 0.1], [0.1, 0.1, 0.12], [0.95, 0.95, 0.95], [0.1, 0.5, 0.8], [0.2, 0.7, 0.3], [0.9, 0.5, 0.1]]
        for column in 0..<6 {
            let x = Float(column) * 1.6 - 4
            let smoothness = Float(column) / 5
            var materials: [any SceneSprockets.Material] = [BlinnPhongSceneMaterial.plastic(paints[column], shininess: 4 + smoothness * 120)]
            if let metal = try? PBRSceneMaterial(device: demoDevice, baseColor: SIMD4(metals[column], 1), metallic: 1, roughness: 0.75 - smoothness * 0.7) {
                materials.append(metal)
            }
            if let plastic = try? PBRSceneMaterial(device: demoDevice, baseColor: SIMD4(plastics[column], 1), metallic: 0, roughness: 0.8 - smoothness * 0.7) {
                // The glossiest plastics get a clear coat, like car paint.
                if column >= 4 {
                    plastic.pbrMaterial.uniforms.clearcoatFactor = 1
                    plastic.pbrMaterial.uniforms.clearcoatRoughnessFactor = 0.05
                }
                materials.append(plastic)
            }
            for (row, material) in materials.enumerated() {
                let node = SceneGraph.Node(parent: slide, shape: shapes[(column + row * 2) % shapes.count], material: material, device: demoDevice, trs: .init(translation: [x, 2.7 - Float(row) * 1.3, 0]))
                node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 8 + Float(column + row))))
            }
        }
    }

    private func lightsSlide(_ slide: SceneGraph.Node) {
        _ = SceneGraph.Node(parent: slide, shape: .box(width: 10, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.8, 0.8, 0.85], shininess: 16), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        for index in 0..<5 {
            _ = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.45), material: BlinnPhongSceneMaterial.plastic([0.9, 0.9, 0.9], shininess: 64), device: demoDevice, trs: .init(translation: [Float(index) * 1.8 - 3.6, 0.45, 0]))
        }
        let colors: [SIMD3<Float>] = [[1, 0.2, 0.2], [0.2, 1, 0.3], [0.3, 0.4, 1]]
        for (index, color) in colors.enumerated() {
            let pivot = SceneGraph.Node(parent: slide, label: "Light Orbit", trs: .init(rotation: simd_quatf(angle: Float(index) * 2 * .pi / 3, axis: [0, 1, 0])))
            pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6)))
            addLight(to: pivot, at: [3, 1.5, 0], color: color, intensity: 25)
            _ = SceneGraph.Node(parent: pivot, shape: .sphere(radius: 0.1), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color)), device: demoDevice, trs: .init(translation: [3, 1.5, 0]))
        }
    }

    private func actionsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        // The same hop with each timing mode, started one after another.
        let modes: [SceneGraph.Action.TimingMode] = [.linear, .easeIn, .easeOut, .easeInEaseOut]
        for (index, mode) in modes.enumerated() {
            let cube = SceneGraph.Node(parent: slide, shape: .box(width: 0.8, height: 0.8, length: 0.8), material: BlinnPhongSceneMaterial.plastic([0.4, 0.7, 1], shininess: 32), device: demoDevice, trs: .init(translation: [Float(index) * 2 - 3, 0.4, 0]))
            var up = SceneGraph.Action.move(by: [0, 2, 0], duration: 0.6)
            up.timingMode = mode
            var down = SceneGraph.Action.move(by: [0, -2, 0], duration: 0.6)
            down.timingMode = mode
            cube.run(.sequence([.wait(duration: Float(index) * 0.25), .repeatForever(.sequence([.group([up, .rotate(by: .pi, around: [0, 1, 0], duration: 0.6)]), down, .wait(duration: 0.8)]))]))
        }
    }

    private func constraintsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let pivot = SceneGraph.Node(parent: slide, label: "Ball Orbit", trs: .init(translation: [0, 1.5, 0]))
        pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6)))
        let ball = SceneGraph.Node(parent: pivot, shape: .sphere(radius: 0.35), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 0.85, 0.2])), device: demoDevice, trs: .init(translation: [3, 0, 0]))
        // Cones that always point their tips (+Y) at the ball.
        for index in 0..<5 {
            let cone = SceneGraph.Node(parent: slide, shape: .cone(bottomRadius: 0.3, height: 0.9), material: BlinnPhongSceneMaterial.plastic([0.5, 0.9, 0.9], shininess: 32), device: demoDevice, trs: .init(translation: [Float(index) * 2 - 4, 0, 2]))
            cone.constraints = [.lookAt(target: ball, localFront: [0, 1, 0])]
        }
    }

    private func fadesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        // Each sphere fades out and back in, a little after the one before it. Blinn-Phong and PBR both fade.
        for index in 0..<6 {
            let material: any SceneSprockets.Material = index.isMultiple(of: 2)
                ? BlinnPhongSceneMaterial.plastic([0.95, 0.4, 0.6], shininess: 48)
                : (try? PBRSceneMaterial(device: demoDevice, baseColor: [0.4, 0.6, 1, 1], metallic: 0, roughness: 0.3)) ?? BlinnPhongSceneMaterial.plastic([0.4, 0.6, 1])
            let sphere = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.6), material: material, device: demoDevice, trs: .init(translation: [Float(index) * 1.6 - 4, 1.2, 0]))
            // Eased, with a pause while invisible: linear fades that turn around at once look abrupt (#340).
            let fadeOut = SceneGraph.Action.fadeOut(duration: 1.2).timingMode(.easeInEaseOut)
            let fadeIn = SceneGraph.Action.fadeIn(duration: 1.2).timingMode(.easeInEaseOut)
            sphere.run(.sequence([.wait(duration: Float(index) * 0.3), .repeatForever(.sequence([fadeOut, .wait(duration: 0.3), fadeIn, .wait(duration: 0.6)]))]))
        }
    }

    private func blendModesSlide(_ slide: SceneGraph.Node) {
        // One orange disc per blend mode over the same striped wall, so each mode's mix shows side by side (#339).
        func glow(_ color: SIMD3<Float>, opacity: Float = 1, blendMode: MaterialRenderState.BlendMode = .alpha) -> BlinnPhongSceneMaterial {
            BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, opacity: opacity, emission: .color(color), renderState: MaterialRenderState(blendMode: blendMode))
        }
        let stripes: [SIMD3<Float>] = [[0.9, 0.15, 0.15], [0.95, 0.85, 0.2], [0.2, 0.8, 0.3], [0.2, 0.75, 0.95], [0.3, 0.3, 0.95], [0.85, 0.3, 0.85], [0.95, 0.95, 0.95], [0.25, 0.25, 0.28]]
        let wall = SceneGraph.Node(parent: slide, label: "Stripes", trs: .init(translation: [0, 1.6, -0.6]))
        for (index, color) in stripes.enumerated() {
            _ = SceneGraph.Node(parent: wall, shape: .plane(width: 1.35, height: 2.8), material: glow(color), device: demoDevice, trs: .init(translation: [Float(index) * 1.35 - 4.725, 0, 0]))
        }
        // Slowly sliding back and forth, so each disc crosses several stripes.
        wall.run(.repeatForever(.sequence([
            .move(by: [1.35, 0, 0], duration: 3).timingMode(.easeInEaseOut),
            .move(by: [-1.35, 0, 0], duration: 3).timingMode(.easeInEaseOut)
        ])))
        let modes: [(String, MaterialRenderState.BlendMode)] = [("alpha", .alpha), ("add", .add), ("subtract", .subtract), ("multiply", .multiply), ("screen", .screen), ("replace", .replace)]
        for (index, (name, mode)) in modes.enumerated() {
            let x = Float(index) * 1.6 - 4
            // Alpha blends only when the material is see-through.
            let material = glow([1, 0.55, 0.15], opacity: mode == .alpha ? 0.5 : 1, blendMode: mode)
            _ = SceneGraph.Node(parent: slide, label: "Blend \(name)", shape: .cylinder(radius: 0.6, height: 0.02), material: material, device: demoDevice, trs: .init(translation: [x, 1.6, 0], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
            let label = addTitle(".\(name)", size: 0.3, y: 0, color: [0.85, 0.85, 0.9], to: slide)
            label.trs.translation.x = x
        }
    }

    // PBR glass in front of turning Blinn-Phong and PBR shapes, which show through it refracted (#123, #129).
    private func glassSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 5, 6], intensity: 80)
        // A checkered Blinn-Phong wall, so the glass always has something to bend.
        let light = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.55, 0.57, 0.62]))
        let dark = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.12, 0.13, 0.16]))
        // One mesh for every tile, so Blinn-Phong draws them as two instanced batches.
        let tile = SceneGraph.Shape.box(width: 0.6, height: 0.6, length: 0.05).metalMesh(device: demoDevice)
        for row in 0..<6 {
            for column in 0..<14 {
                let material = (row + column).isMultiple(of: 2) ? light : dark
                _ = SceneGraph.Node(parent: slide, trs: .init(translation: [Float(column) * 0.6 - 3.9, Float(row) * 0.6 + 0.1, -4.5]), content: .mesh(tile, material: material))
            }
        }
        let colors: [SIMD3<Float>] = [[0.95, 0.3, 0.25], [0.95, 0.8, 0.2], [0.3, 0.8, 0.4], [0.25, 0.5, 1], [0.8, 0.35, 0.9]]
        for (index, color) in colors.enumerated() {
            let x = Float(index) * 1.6 - 3.2
            let material: any SceneSprockets.Material = index.isMultiple(of: 2)
                ? BlinnPhongSceneMaterial.plastic(color, shininess: 32)
                : (try? PBRSceneMaterial(device: demoDevice, baseColor: SIMD4(color, 1), metallic: 0, roughness: 0.4)) ?? BlinnPhongSceneMaterial.plastic(color)
            let bar = SceneGraph.Node(parent: slide, shape: .box(width: 0.5, height: 3, length: 0.5), material: material, device: demoDevice, trs: .init(translation: [x, 1.6, -2.5]))
            bar.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6 + Float(index))))
        }
        let shapes: [(SceneGraph.Shape, Float, Float)] = [
            (.sphere(radius: 0.9), -2.6, 0),
            (.box(width: 1.6, height: 1.6, length: 0.4), 0, 0.15),
            (.torus(ringRadius: 0.75, pipeRadius: 0.3), 2.6, 0.05)
        ]
        for (shape, x, roughness) in shapes {
            guard let glass = try? PBRSceneMaterial(device: demoDevice, baseColor: [1, 1, 1, 1], metallic: 0, roughness: roughness) else {
                continue
            }
            glass.pbrMaterial.uniforms.transmissionFactor = 1
            glass.pbrMaterial.uniforms.thicknessFactor = 0.6
            let node = SceneGraph.Node(parent: slide, shape: shape, material: glass, device: demoDevice, trs: .init(translation: [x, 1.6, 1]))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0]), duration: 10)))
        }
    }

    private func shadowsSlide(_ slide: SceneGraph.Node) {
        // Tilted toward the camera so the shadows on the floor show.
        let stage = SceneGraph.Node(parent: slide, label: "Stage", trs: .init(translation: [0, 0.8, -2.5], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0])))
        let slide = stage
        _ = SceneGraph.Node(parent: slide, label: "Sun", transform: .camera(eye: [3, 6, 4], target: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 1.5)))
        _ = SceneGraph.Node(parent: slide, label: "Floor", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.7, 0.7, 0.75], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        let torus = SceneGraph.Node(parent: slide, shape: .torus(ringRadius: 0.8, pipeRadius: 0.25), material: BlinnPhongSceneMaterial.plastic([0.95, 0.75, 0.3], shininess: 48), device: demoDevice, trs: .init(translation: [0, 1.8, 0]))
        torus.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.5, 0]), duration: 6)))
        _ = SceneGraph.Node(parent: slide, shape: .box(width: 1, height: 1, length: 1), material: BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.3]), device: demoDevice, trs: .init(translation: [-3, 0.5, 0]))
        _ = SceneGraph.Node(parent: slide, shape: .cylinder(radius: 0.35, height: 2), material: BlinnPhongSceneMaterial.plastic([0.4, 0.8, 0.5]), device: demoDevice, trs: .init(translation: [3, 1, 0]))
    }

    // Hides the flat titles and puts one extruded letter in place of each character, with a random kick and spin.
    private func breakIntroTitles() {
        removeTumblingLetters()
        let slide = slides[0]
        for (title, spec) in zip(introTitles, Self.introTitleSpecs) {
            title.isVisible = false
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, CGFloat(spec.size), nil)
            func advance(_ text: String) -> Float {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
                return Float(CTLineGetTypographicBounds(line, nil, nil, nil))
            }
            let width = advance(spec.text)
            let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(spec.color * 0.4), specular: .color(0.3), shininess: 32, emission: .color(spec.color * 0.6))
            for (offset, character) in spec.text.enumerated() where character != " " {
                let prefix = String(spec.text.prefix(offset))
                let holder = SceneGraph.Node(parent: slide, label: "Letter \(character)")
                let letter = SceneGraph.Node(parent: holder, shape: .text(String(character), fontName: "Helvetica-Bold", fontSize: spec.size, extrusionDepth: spec.size * 0.15), material: material, device: demoDevice)
                guard let bounds = letter.meshBounds else {
                    continue
                }
                let center = (bounds.min + bounds.max) / 2
                // The holder sits at the letter's center, so the letter spins about its middle.
                letter.trs.translation = -center
                holder.trs.translation = [advance(prefix) - width / 2 + center.x, spec.y + center.y, center.z]
                tumblingLetters.append(TumblingLetter(
                    node: holder,
                    velocity: [Float.random(in: -1.5...1.5), Float.random(in: 1.5...4), Float.random(in: 0.5...3)],
                    spinAxis: simd_normalize(SIMD3<Float>.random(in: -1...1) + [0, 0, 0.01]),
                    spinRate: Float.random(in: 2...7)
                ))
            }
        }
        Self.isolateLights(of: slide, index: 0)
        hierarchyDidChange()
    }

    private func updateTumblingLetters(deltaTime: Float) {
        guard !tumblingLetters.isEmpty, deltaTime > 0 else {
            return
        }
        for index in tumblingLetters.indices {
            tumblingLetters[index].velocity.y -= 9.81 * deltaTime
            let letter = tumblingLetters[index]
            letter.node.trs.translation += letter.velocity * deltaTime
            letter.node.trs.rotation = simd_quatf(angle: letter.spinRate * deltaTime, axis: letter.spinAxis) * letter.node.trs.rotation
        }
        // Out of frame: no need to keep them.
        let fallen = tumblingLetters.filter { $0.node.trs.translation.y < -10 }
        if !fallen.isEmpty {
            fallen.forEach { $0.node.removeFromParent() }
            tumblingLetters.removeAll { $0.node.trs.translation.y < -10 }
            hierarchyDidChange()
        }
    }

    private func removeTumblingLetters() {
        tumblingLetters.forEach { $0.node.removeFromParent() }
        tumblingLetters = []
    }

    private func restoreIntroTitles() {
        removeTumblingLetters()
        introTitles.forEach { $0.isVisible = true }
    }

    // Glass orbiting the title, colored lights, fireworks and confetti. Hidden until `startFinale`.
    private func finaleSlide(_ slide: SceneGraph.Node) {
        let finale = SceneGraph.Node(parent: slide, label: "Finale")
        finale.isVisible = false
        self.finale = finale
        let colors: [SIMD3<Float>] = [[1, 0.3, 0.4], [0.3, 1, 0.5], [0.4, 0.5, 1]]
        for (index, color) in colors.enumerated() {
            let pivot = SceneGraph.Node(parent: finale, label: "Light Orbit", trs: .init(translation: [0, 1.5, 0], rotation: simd_quatf(angle: Float(index) * 2 * .pi / 3, axis: [0, 1, 0])))
            pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 3 + Float(index))))
            addLight(to: pivot, at: [4, 1, 2], color: color, intensity: 60)
        }
        // A tilted ring of candy-colored spheres around the title. Glass over a black background reads as black.
        let ring = SceneGraph.Node(parent: finale, label: "Candy Ring", trs: .init(translation: [0, 1.5, 0], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0])))
        ring.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)))
        for index in 0..<6 {
            guard let candy = try? PBRSceneMaterial(device: demoDevice, baseColor: SIMD4(colors[index % 3], 1), metallic: 0.8, roughness: 0.2) else {
                continue
            }
            candy.pbrMaterial.uniforms.clearcoatFactor = 1
            candy.pbrMaterial.uniforms.clearcoatRoughnessFactor = 0.03
            let angle = Float(index) * 2 * .pi / 6
            _ = SceneGraph.Node(parent: ring, shape: .sphere(radius: 0.45), material: candy, device: demoDevice, trs: .init(translation: [cos(angle) * 4.6, 0, sin(angle) * 2]))
        }
        // Big glass shapes and polished metal spinning on either side.
        let props: [(SceneGraph.Shape, SIMD3<Float>, Bool)] = [
            (.torus(ringRadius: 0.7, pipeRadius: 0.28), [-5.2, 3.2, -1.5], true),
            (.teapot(diameter: 1.8), [5.2, 3.2, -1.5], true),
            (.box(width: 0.9, height: 0.9, length: 0.9), [-5.4, -0.4, -1], false),
            (.capsule(capRadius: 0.35, height: 1.2), [5.4, -0.4, -1], false)
        ]
        for (index, (shape, position, isGlass)) in props.enumerated() {
            guard let material = try? PBRSceneMaterial(device: demoDevice, baseColor: isGlass ? [1, 1, 1, 1] : [1, 0.8, 0.4, 1], metallic: isGlass ? 0 : 1, roughness: isGlass ? 0 : 0.15) else {
                continue
            }
            if isGlass {
                material.pbrMaterial.uniforms.transmissionFactor = 1
                material.pbrMaterial.uniforms.thicknessFactor = 0.6
            }
            let node = SceneGraph.Node(parent: finale, shape: shape, material: material, device: demoDevice, trs: .init(translation: position))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.4, 1, 0.3]), duration: 3 + Float(index))))
        }
        let emitters: [(SIMD3<Float>, ParticleSystem)] = [
            ([-3.5, 0, -4], .fireworks), ([3.5, 0, -4], .fireworks), ([0, 5, 0], .confetti),
            ([0, -0.4, -1.5], .ringOfFire), ([0, 1.5, -8], .galaxy)
        ]
        finaleEmitters = emitters.map { position, system in
            (SceneGraph.Node(parent: finale, label: "Finale Emitter", trs: .init(translation: position)), system)
        }
    }

    // Shows the title alone for a moment, then everything at once. Particles start fresh each time.
    private func startFinale(after delay: Float) {
        guard let finale else {
            return
        }
        finale.removeAction(forKey: "finale")
        finale.isVisible = false
        finaleTitle?.removeAction(forKey: "pulse")
        finaleTitle?.trs.scale = [1, 1, 1]
        for emitter in finaleEmitters {
            emitter.node.particleSystems = []
        }
        let emitters = finaleEmitters
        let title = finaleTitle
        let reveal = SceneGraph.Action.run { node in
            node.isVisible = true
            for (seed, emitter) in emitters.enumerated() {
                emitter.node.particleSystems = [SceneParticleSystem(emitter.system, seed: UInt32(seed + 1))]
            }
            let pulse = SceneGraph.Action.sequence([.scale(to: [1.08, 1.08, 1.08], duration: 0.35), .scale(to: [1, 1, 1], duration: 0.35)])
            title?.run(.repeatForever(pulse.timingMode(.easeInEaseOut)), forKey: "pulse")
        }
        finale.run(.sequence([.wait(duration: delay), reveal]), forKey: "finale")
    }

    private func fogSlide(_ slide: SceneGraph.Node) {
        _ = SceneGraph.Node(parent: slide, label: "Moon", transform: .camera(eye: [2, 5, 6], target: .zero), content: .light(Light(type: .directional, color: [0.8, 0.85, 1], intensity: 1.2)))
        // Two rows of pillars running away from the camera, fading into the fog.
        for row in 0..<8 {
            for side in [-1, 1] as [Float] {
                let pillar = SceneGraph.Node(parent: slide, shape: .cylinder(radius: 0.3, height: 3), material: BlinnPhongSceneMaterial.plastic([0.85, 0.8, 0.7], shininess: 16), device: demoDevice, trs: .init(translation: [side * 2.5, 1.5, -Float(row) * 4]))
                pillar.label = "Pillar"
            }
        }
        _ = SceneGraph.Node(parent: slide, label: "Ground", shape: .box(width: 8, height: 0.1, length: 36), material: BlinnPhongSceneMaterial.plastic([0.4, 0.4, 0.45], shininess: 4), device: demoDevice, trs: .init(translation: [0, -0.05, -14]))
    }

    private func implicitAnimationSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let colors: [SIMD3<Float>] = [[1, 0.4, 0.3], [1, 0.8, 0.3], [0.4, 0.9, 0.4], [0.3, 0.8, 1], [0.6, 0.5, 1], [1, 0.5, 0.8]]
        shuffleCubes = colors.enumerated().map { index, color in
            SceneGraph.Node(parent: slide, shape: .box(width: 0.8, height: 0.8, length: 0.8), material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), device: demoDevice, trs: .init(translation: [Float(index) * 1.4 - 3.5, 1.2, 0]))
        }
    }

    // Plain property changes inside a transaction animate instead of jumping.
    private func shuffle() {
        SceneGraph.Transaction.animate(duration: 0.8, timingMode: .easeInEaseOut) {
            for cube in shuffleCubes {
                cube.trs.translation = [Float.random(in: -4...4), Float.random(in: 0.4...3), Float.random(in: -1...1)]
                cube.trs.rotation = simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: simd_normalize(SIMD3<Float>.random(in: -1...1) + [0, 0.01, 0]))
            }
        }
    }

    private func animationBlendingSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 70)
        _ = SceneGraph.Node(parent: slide, label: "Floor", shape: .box(width: 8, height: 0.1, length: 4), material: BlinnPhongSceneMaterial.plastic([0.6, 0.6, 0.65], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        let body = SceneGraph.Node(parent: slide, label: "Body", shape: .box(width: 1, height: 1, length: 1), material: BlinnPhongSceneMaterial.plastic([0.9, 0.5, 0.2]), device: demoDevice, trs: .init(translation: [0, 0.5, 0]))
        let head = SceneGraph.Node(parent: body, label: "Head", shape: .sphere(radius: 0.35), material: BlinnPhongSceneMaterial.plastic([0.95, 0.85, 0.7]), device: demoDevice, trs: .init(translation: [0, 0.9, 0]))
        func vector(_ values: [SIMD3<Float>]) -> [Float] { values.flatMap { [$0.x, $0.y, $0.z] } }
        func quaternions(_ angles: [Float], axis: SIMD3<Float>) -> [Float] {
            angles.flatMap { angle -> [Float] in
                let vector = simd_quatf(angle: angle, axis: axis).vector
                return [vector.x, vector.y, vector.z, vector.w]
            }
        }
        let bounce = SceneGraph.AnimationClip(name: "Bounce", channels: [
            .init(target: body, path: .translation, sampler: .init(times: [0, 0.5, 1], values: vector([[0, 0.5, 0], [0, 2, 0], [0, 0.5, 0]]), interpolation: .linear))
        ])
        let sway = SceneGraph.AnimationClip(name: "Sway", channels: [
            .init(target: body, path: .rotation, sampler: .init(times: [0, 1, 2], values: quaternions([-0.4, 0.4, -0.4], axis: [0, 0, 1]), interpolation: .linear)),
            .init(target: head, path: .rotation, sampler: .init(times: [0, 1, 2], values: quaternions([0.6, -0.6, 0.6], axis: [0, 1, 0]), interpolation: .linear))
        ])
        blendMixer = SceneGraph.AnimationMixer(clips: [bounce, sway])
        blendController = SceneGraph.AnimationController(clips: [bounce, sway])
    }

    private func importSlide(_ slide: SceneGraph.Node) {
        _ = SceneGraph.Node(parent: slide, label: "Sun", transform: .camera(eye: [2, 4, 3], target: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 2)))
        addLight(to: slide, at: [-3, 3, 5], color: [0.6, 0.7, 1], intensity: 30)
        // The plant is about 0.6 units tall and the pedestal 1 wide (its top at y = 0); the holder scales both up.
        let holder = SceneGraph.Node(parent: slide, label: "Imported", trs: .init(translation: [0, 0.3, -1], scale: [1.4, 1.4, 1.4]))
        do {
            if let url = Bundle.module.url(forResource: "DiffuseTransmissionPlant", withExtension: "glb", subdirectory: "Resources") {
                let plant = try GLTFAsset(url: url, device: demoDevice).makeSceneGraph(device: demoDevice)
                let plantHolder = SceneGraph.Node(parent: holder, label: "Plant", trs: .init(scale: [3, 3, 3]))
                for child in plant.sceneGraph.root.children {
                    plantHolder.addChild(child)
                }
                // The asset has chase cameras behind its fireflies; the keynote flies its own camera.
                removeCameras(under: plantHolder)
                // The fireflies are tiny with very dim lights; give them a glow, a light and a trail so they read on stage.
                for firefly in descendants(of: plantHolder).filter({ ["firefly1", "firefly2"].contains($0.label) }) {
                    let glow = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.8, 1, 0.45]))
                    _ = SceneGraph.Node(parent: firefly, label: "Glow", shape: .sphere(radius: 0.025), material: glow, device: demoDevice)
                    var light = Light(type: .point, color: [0.8, 1, 0.5], intensity: 6)
                    light.range = 3
                    _ = SceneGraph.Node(parent: firefly, label: "Glow Light", content: .light(light))
                    // Particle sizes are in world units.
                    let trail = ParticleSystem("Firefly Trail") {
                        EmitterDescription("Trail", capacity: 256) {
                            ShapeModule(shape: .point)
                            RateModule(birthRate: 90)
                            LifetimeModule(range: 1.2...1.2)
                            VelocityModule(velocity: .zero, spread: 0.05)
                            GravityModule(acceleration: .zero)
                            DragModule(amount: 0)
                            SizeOverLifeModule(curve: .linear(from: 0.3, to: 0.04))
                            ColorOverLifeModule(color: .linear(from: [0.8, 1, 0.45, 0.8], to: [0.5, 1, 0.3, 0]))
                            SpriteModule(blendMode: .additive)
                        }
                    }
                    firefly.particleSystems = [SceneParticleSystem(trail, seed: 3)]
                }
                importedPlayer = plant.animations.first.map { SceneGraph.AnimationPlayer(clip: $0) }
            }
            if let url = Bundle.module.url(forResource: "Pedestal", withExtension: "obj", subdirectory: "Resources") {
                let pedestal = try ModelIOSceneGraph(url: url, device: demoDevice)
                pedestal.sceneGraph.root.label = "Pedestal"
                holder.addChild(pedestal.sceneGraph.root)
            }
        } catch {
            // The slide shows whatever loaded.
        }
    }

    private func descendants(of node: SceneGraph.Node) -> [SceneGraph.Node] {
        node.children.flatMap { [$0] + descendants(of: $0) }
    }

    private func removeCameras(under node: SceneGraph.Node) {
        for child in node.children {
            if case .camera = child.content {
                child.content = .empty
            }
            removeCameras(under: child)
        }
    }

    private func hitTestingSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.box(width: 1, height: 1, length: 1), [1, 0.4, 0.3]),
            (.sphere(radius: 0.6), [1, 0.8, 0.3]),
            (.cone(bottomRadius: 0.6, height: 1.2), [0.3, 0.8, 1]),
            (.torus(ringRadius: 0.5, pipeRadius: 0.18), [1, 0.5, 0.8])
        ]
        for (index, (shape, color)) in shapes.enumerated() {
            let node = SceneGraph.Node(parent: slide, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), device: demoDevice, trs: .init(translation: [Float(index) * 2.2 - 3.3, 1.2, 0]))
            hitTargets.insert(ObjectIdentifier(node))
        }
        addTitle("Click a shape", size: 0.35, y: 2.8, color: [0.6, 0.65, 0.75], to: slide)
    }

    // DiceDemo's wooden tray and dice, tilted toward the camera so the dice show from the slides' usual eye height.
    private static let trayTilt = simd_quatf(angle: 0.5, axis: [1, 0, 0])

    private func physicsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 80)
        let tray = SceneGraph.Node(
            parent: slide, label: "Dice Tray", trs: .init(translation: [0, 0.8, 0], rotation: Self.trayTilt)
        )
        DiceDemo.buildTray(in: tray)
        physicsDice = SceneGraph.Node(parent: tray, label: "Dice")
    }

    // Throws six new dice, one of each D&D kind in mixed styles, from the tray's front-left corner, as DiceDemo.roll
    // does. Hidden slides drop out of the physics world, so this runs on arrival.
    private func resetPhysics() {
        guard let physicsDice else {
            return
        }
        sincePhysicsReset = 0
        physicsDice.removeAllChildren()
        let styles = DiceStyle.allCases.shuffled(using: &diceGenerator)
        let dice = DiceDemo.Kind.allCases.enumerated().compactMap { index, kind -> SceneGraph.Node? in
            guard let die = DiceDemo.makeDie(kind, style: styles[index % styles.count]) else {
                return nil
            }
            let position = SIMD3<Float>(
                -DiceDemo.trayWidth / 2 + 0.6 + Float(index % 4) * 0.6,
                1.4 + Float(index / 4) * 0.6,
                DiceDemo.trayDepth / 2 - 0.6 - Float.random(in: 0...0.3, using: &diceGenerator)
            )
            let axis = simd_normalize(SIMD3<Float>.random(in: -1...1, using: &diceGenerator) + [0, 0.01, 0])
            let rotation = simd_quatf(angle: .random(in: 0...(2 * .pi), using: &diceGenerator), axis: axis)
            die.trs = .init(translation: position, rotation: rotation, scale: SIMD3(repeating: DiceDemo.dieScale))
            physicsDice.addChild(die)
            return die
        }
        guard let physics else {
            return
        }
        physics.sync()
        for die in dice {
            let velocity = SIMD3<Float>(
                .random(in: 4...7, using: &diceGenerator),
                .random(in: 0...1.5, using: &diceGenerator),
                .random(in: -4 ... -2, using: &diceGenerator)
            )
            // Velocities are in world space; the throw is in the tilted tray's.
            physics.setVelocity(Self.trayTilt.act(velocity), of: die)
            physics.setAngularVelocity(SIMD3<Float>.random(in: -15...15, using: &diceGenerator), of: die)
        }
    }

    private func customShadersSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let materials: [any SceneSprockets.Material] = [
            try? ShaderMaterial.normals(),
            try? ShaderMaterial.rim(color: [0.3, 0.8, 1, 1]),
            try? ShaderMaterial.rim(color: [1, 0.4, 0.7, 1])
        ].compactMap { $0 }
        let shapes: [SceneGraph.Shape] = [.torus(ringRadius: 0.7, pipeRadius: 0.28), .sphere(radius: 0.9), .capsule(capRadius: 0.5, height: 1.8)]
        for (index, (shape, material)) in zip(shapes, materials).enumerated() {
            let node = SceneGraph.Node(parent: slide, shape: shape, material: material, device: demoDevice, trs: .init(translation: [Float(index) * 3 - 3, 1.4, 0]))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.4, 1, 0.2]), duration: 7 + Float(index))))
        }
    }

    // Sheen, diffuse transmission and clearcoat on speckled pieces; iridescence on pearls. Slowly turning.
    private func pbrExtensionsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [-4, 6, 8], intensity: 60)
        addLight(to: slide, at: [6, -2, 6], color: [0.9, 0.95, 1], intensity: 15)
        addLight(to: slide, at: [1, 3, -8], color: [1, 0.9, 0.8], intensity: 400)
        let speckles = PBRExtensionMaterials.makeSpeckleBinding()
        let roundedBox = MetalMesh(mesh: .roundedBox(extents: [1.6, 2.2, 1.1], radius: 0.35), device: demoDevice)
        let cube = MetalMesh(mesh: .roundedBox(extents: [1.6, 1.6, 1.6], radius: 0.3), device: demoDevice)
        let smooth: MeshAttributes = [.smoothNormals, .textureCoordinates]
        let egg = MetalMesh(mesh: .sphere(extents: [1.4, 1.8, 1.4], latitudeSegments: 48, longitudeSegments: 96, attributes: smooth), device: demoDevice)
        let bean = MetalMesh(mesh: .capsule(segments: 64, height: 2.2, radius: 0.5, latitudeSegments: 24, attributes: smooth), device: demoDevice)
        let pearl = PBRExtensionMaterials.pearl()
        let pieces: [(MetalMesh, PBRSceneMaterial, SIMD3<Float>)] = [
            (roundedBox, PBRExtensionMaterials.gummy(color: [1, 0.3, 0.1], speckles: speckles), [-3.6, 1.4, 0]),
            (cube, pearl, [-1.2, 1.6, 0]),
            (egg, PBRExtensionMaterials.gummy(color: [0.5, 0.75, 0.15], speckles: speckles), [1.2, 1.4, 0]),
            (bean, pearl, [3.6, 1.4, 0])
        ]
        var generator = SystemRandomNumberGenerator()
        for (mesh, material, position) in pieces {
            let node = SceneGraph.Node(parent: slide, label: material.pbrMaterial.name, trs: .init(translation: position), content: .mesh(mesh, material: material))
            let axis = simd_normalize(SIMD3<Float>(.random(in: -1...1, using: &generator), .random(in: -1...1, using: &generator), .random(in: -1...1, using: &generator)))
            pbrExtensionPieces.append((node, axis, .random(in: 0.2...0.5, using: &generator)))
        }
    }

    // The animated glTF Fox with particles born on its skinned surface: flames, then sparks, in turn.
    private func meshEmittersSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [-3, 5, 4], color: [0.5, 0.6, 1], intensity: 12)
        _ = SceneGraph.Node(parent: slide, label: "Floor", shape: .box(width: 10, height: 0.1, length: 4), material: BlinnPhongSceneMaterial.plastic([0.12, 0.12, 0.14], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        guard let fox = try? BurningFox(scale: 2) else {
            return
        }
        // Side on to the camera.
        fox.node.trs = .init(rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
        slide.addChild(fox.node)
        burningFox = fox
    }

    // MetalSprocketsParticles sample presets: a campfire on real logs, a geyser, and fireworks over the slide. Presets
    // bring their own colliders (the ground plane, the logs), which follow the node they are on.
    private func particlesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [-4, 6, 6], color: [0.45, 0.55, 0.9], intensity: 25)
        _ = SceneGraph.Node(parent: slide, label: "Ground", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.16, 0.15, 0.15], shininess: 6), device: demoDevice, trs: .init(translation: [0, -0.05, -1]))

        let campfire = SceneGraph.Node(parent: slide, label: "Campfire", trs: .init(translation: [-2.6, 0, 0.8]))
        campfire.particleSystems = [SceneParticleSystem(.campfire, seed: 1)]
        // Logs where the preset's capsule colliders are, so embers land on wood.
        let bark = BlinnPhongSceneMaterial.plastic([0.3, 0.18, 0.1], shininess: 4)
        for (start, end) in [(SIMD3<Float>(-0.5, 0.08, -0.2), SIMD3<Float>(0.5, 0.08, 0.2)), ([-0.4, 0.08, 0.35], [0.4, 0.08, -0.35])] {
            let axis = end - start
            _ = SceneGraph.Node(parent: campfire, label: "Log", shape: .capsule(capRadius: 0.08, height: simd_length(axis) + 0.16), material: bark, device: demoDevice, trs: .init(translation: (start + end) / 2, rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize(axis))))
        }
        var firelight = Light(type: .point, color: [1, 0.55, 0.2], intensity: 6)
        firelight.range = 6
        campfireLight = SceneGraph.Node(parent: campfire, label: "Firelight", trs: .init(translation: [0, 0.6, 0]), content: .light(firelight))

        _ = SceneGraph.Node(parent: slide, label: "Geyser", trs: .init(translation: [2.8, 0, -0.5])).particleSystems = [SceneParticleSystem(.geyser, seed: 2)]
        // Far back, so the bursts open above the title.
        _ = SceneGraph.Node(parent: slide, label: "Fireworks", trs: .init(translation: [0, 0, -9])).particleSystems = [SceneParticleSystem(.fireworks, seed: 3)]
    }

    // The campfire light flickers with layered sines.
    private func flickerCampfire(time: Float) {
        guard let campfireLight, case var .light(light) = campfireLight.content else {
            return
        }
        light.intensity = 6 + 1.5 * sin(time * 11) + sin(time * 17.3) + 0.7 * sin(time * 29.1)
        campfireLight.content = .light(light)
    }

    // A morphing blob and a skinned tube. The bumps move vertices along the direction from the center, not the vertex
    // normal: each face has its own vertices, so moving along normals would tear the faces apart (#70).
    // Faceted spheres switch to coarser meshes 15 and 22 units from the camera.
    private func levelOfDetailSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 60)
        addLight(to: slide, at: [-4, 2, 2], color: [0.6, 0.7, 1], intensity: 20)
        // The spheres travel back to z = -14; light their camera-facing sides there too.
        addLight(to: slide, at: [0, 3, -3], intensity: 120)
        func sphere(_ subdivisions: Int) -> MetalMesh {
            MetalMesh(mesh: Mesh.icoSphere(subdivisions: subdivisions).withFlatNormals(), device: demoDevice)
        }
        let high = sphere(3), medium = sphere(1), low = sphere(0)
        let colors: [SIMD3<Float>] = [[0.95, 0.45, 0.3], [0.35, 0.75, 0.45], [0.35, 0.55, 0.95]]
        detailed = colors.enumerated().map { index, color in
            let node = SceneGraph.Node(parent: slide, label: "Detail \(index + 1)", trs: .init(translation: [Float(index - 1) * 3.2, 0.9, -6], scale: SIMD3(repeating: 1.3)), content: .mesh(high, material: BlinnPhongSceneMaterial.plastic(color, shininess: 24)))
            node.levelsOfDetail = [SceneGraph.LevelOfDetail(mesh: medium, distance: 15), SceneGraph.LevelOfDetail(mesh: low, distance: 22)]
            return node
        }
    }

    private func deformationSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 50)
        addLight(to: slide, at: [-3, 1, 3], color: [0.5, 0.6, 1], intensity: 15)
        let mesh = MetalMesh(mesh: .icoSphere(subdivisions: 4), device: demoDevice)
        let positions = mesh.float3Attribute(.position)
        let normals = mesh.float3Attribute(.normal)
        let indices = mesh.submeshes.flatMap(\.indices)
        let axes: [SIMD3<Float>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
        let bumpDeltas = positions.map { position in
            let direction = simd_normalize(position)
            return direction * (axes.map { pow(max(0, simd_dot(direction, $0)), 12) }.max() ?? 0) * 0.6
        }
        let squashDeltas = positions.map { SIMD3<Float>($0.x * 0.5, -$0.y * 0.5, $0.z * 0.5) }
        let bumps = SceneGraph.MorphTarget(positionDeltas: bumpDeltas, normalDeltas: DeformationMeshes.normalDeltas(positions: positions, normals: normals, deltas: bumpDeltas, indices: indices))
        let squash = SceneGraph.MorphTarget(positionDeltas: squashDeltas, normalDeltas: DeformationMeshes.normalDeltas(positions: positions, normals: normals, deltas: squashDeltas, indices: indices))
        let blobMaterial: any SceneSprockets.Material = (try? PBRSceneMaterial(device: demoDevice, baseColor: [0.3, 0.8, 0.5, 1], metallic: 0.1, roughness: 0.3)) ?? BlinnPhongSceneMaterial.plastic([0.3, 0.8, 0.5])
        let blob = SceneGraph.Node(parent: slide, label: "Blob", trs: .init(translation: [-2.5, 1.5, 0]), content: .mesh(mesh, material: blobMaterial))
        blob.morphTargets = [bumps, squash]
        blob.morphWeights = [0, 0]
        morphed.append(blob)

        // Many short bones, each turning a little, bend the tube in a smooth curve; two long ones kinked it.
        let tubeHeight: Float = 3
        let jointSpacing = tubeHeight / Float(Self.tubeJointCount - 1)
        let tube = MetalMesh(mesh: DeformationMeshes.tube(height: tubeHeight, radius: 0.3, rings: 48, segments: 24), device: demoDevice)
        let skinVertices = tube.float3Attribute(.position).map { position in
            let along = min(max(position.y / jointSpacing, 0), Float(Self.tubeJointCount - 1))
            let lower = min(Int(along), Self.tubeJointCount - 2)
            let fraction = along - Float(lower)
            return SceneGraph.SkinVertex(joints: [UInt16(lower), UInt16(lower + 1), 0, 0], weights: [1 - fraction, fraction, 0, 0])
        }
        let skeleton = SceneGraph.Node(parent: slide, label: "Skeleton", trs: .init(translation: [2.5, 0, 0]))
        var joints = [SceneGraph.Node(parent: skeleton, label: "Joint 0")]
        for index in 1..<Self.tubeJointCount {
            joints.append(SceneGraph.Node(parent: joints[index - 1], label: "Joint \(index)", trs: .init(translation: [0, jointSpacing, 0])))
        }
        bendingJoints += joints.dropFirst()
        // Skinned vertices end up in world space, so the tube node's own transform does not matter.
        let skeletonInverse = skeleton.worldTransform.inverse
        let inverseBind = joints.map { (skeletonInverse * $0.worldTransform).inverse }
        let tubeMaterial: any SceneSprockets.Material = (try? PBRSceneMaterial(device: demoDevice, baseColor: [0.9, 0.6, 0.2, 1], metallic: 0, roughness: 0.4)) ?? BlinnPhongSceneMaterial.plastic([0.9, 0.6, 0.2])
        let skinned = SceneGraph.Node(parent: slide, label: "Tube", content: .mesh(tube, material: tubeMaterial))
        skinned.skin = SceneGraph.Skin(joints: joints, inverseBindMatrices: inverseBind)
        skinned.skinVertices = skinVertices
    }

    private func performanceSlide(_ slide: SceneGraph.Node) {
        _ = SceneGraph.Node(parent: slide, label: "Sun", transform: .camera(eye: [2, 6, 4], target: .zero), content: .light(Light(type: .directional, intensity: 1)))
        addLight(to: slide, at: [0, 4, 6], color: [0.5, 0.6, 0.9], intensity: 30)
        let box = MetalMesh(mesh: .box(), device: demoDevice)
        let materials = [[0.8, 0.5, 0.2], [0.6, 0.3, 0.15], [0.7, 0.6, 0.3]].map { BlinnPhongSceneMaterial.plastic($0, shininess: 16) }
        let grid = SceneGraph.Node(parent: slide, label: "Grid", trs: .init(translation: [0, 0.5, -3]))
        let size = Self.crateGridSize
        let spacing: Float = 12 / Float(size)
        for row in 0..<size {
            for column in 0..<size {
                let trs = Transform3D(translation: [(Float(column) - Float(size - 1) / 2) * spacing, 0, (Float(row) - Float(size - 1) / 2) * spacing], scale: SIMD3(repeating: spacing * 0.8))
                crates.append(SceneGraph.Node(parent: grid, label: "Crate", trs: trs, content: .mesh(box, material: materials[(row + column) % materials.count])))
            }
        }
        addTitle("\(size * size) crates, \(materials.count) draw calls", size: 0.35, y: 3, color: [0.6, 0.65, 0.75], to: slide)
    }

    private func waveCrates(time: Float) {
        for crate in crates {
            let position = crate.trs.translation
            crate.trs.translation.y = sin(time * 2 + (position.x + position.z) * 0.8) * 0.4
        }
    }

    private func postProcessingSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 80)
        _ = SceneGraph.Node(parent: slide, label: "Floor", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.8, 0.8, 0.82], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        let colors: [SIMD3<Float>] = [[1, 0.35, 0.3], [1, 0.8, 0.3], [0.4, 0.85, 0.45], [0.3, 0.6, 1], [0.75, 0.45, 1]]
        for (index, color) in colors.enumerated() {
            let height = 0.6 + Float(index % 3) * 0.5
            _ = SceneGraph.Node(parent: slide, shape: .box(width: 0.9, height: height, length: 0.9), material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), device: demoDevice, trs: .init(translation: [Float(index) * 1.4 - 2.8, height / 2, 0]))
        }
        let torus = SceneGraph.Node(parent: slide, shape: .torus(ringRadius: 0.5, pipeRadius: 0.18), material: BlinnPhongSceneMaterial.plastic([0.95, 0.95, 0.95], shininess: 64), device: demoDevice, trs: .init(translation: [0, 2.3, 0]))
        torus.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.5, 0]), duration: 6)))
        gradeLabels = Self.grades.map { grade in
            let label = SceneGraph.Node(parent: slide, label: "Grade \(grade.name)")
            addTitle(grade.name, size: 0.4, y: 3.1, color: [0.85, 0.85, 0.9], to: label)
            label.isVisible = false
            return label
        }
        gradeLabels.first?.isVisible = true
    }

    // nil shows the materials; the debug views replace them for the whole view, title and code panel included.
    private static let debugModes: [SceneGraphDebugMode?] = [nil, .normals, .textureCoordinates, .uvChecker, .worldPosition, .wireframe]

    // A selected box with its outline and the transform gizmo, which cycles through its modes.
    private func gizmosSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 60)
        _ = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.6), material: BlinnPhongSceneMaterial.plastic([0.4, 0.75, 0.45], shininess: 32), device: demoDevice, trs: .init(translation: [-3.2, 0.9, 0]))
        _ = SceneGraph.Node(parent: slide, shape: .cone(topRadius: 0, bottomRadius: 0.6, height: 1.3), material: BlinnPhongSceneMaterial.plastic([0.4, 0.55, 0.95], shininess: 32), device: demoDevice, trs: .init(translation: [3.2, 0.9, 0]))
        gizmoTarget = SceneGraph.Node(parent: slide, label: "Box", shape: .box(width: 1.2, height: 1.2, length: 1.2), material: BlinnPhongSceneMaterial.plastic([0.95, 0.55, 0.3], shininess: 32), device: demoDevice, trs: .init(translation: [0, 0.9, 0], rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0])))
    }

    private func debugViewsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 60)
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.sphere(radius: 0.7), [0.9, 0.4, 0.3]),
            (.torus(ringRadius: 0.6, pipeRadius: 0.22), [0.4, 0.75, 0.45]),
            (.box(width: 1.1, height: 1.1, length: 1.1), [0.4, 0.55, 0.95])
        ]
        for (index, (shape, color)) in shapes.enumerated() {
            let node = SceneGraph.Node(parent: slide, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), device: demoDevice, trs: .init(translation: [Float(index) * 2.4 - 3.6, 1.1, 0]))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 7)))
        }
        if let die = DiceDemo.makeDie(.d20, style: .classicIvory) {
            die.physicsBody = nil
            die.trs = .init(translation: [3.6, 1.1, 0], scale: SIMD3(repeating: DiceDemo.dieScale * 2.2))
            slide.addChild(die)
            die.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.6, 0.2]), duration: 9)))
        }
        debugLabels = Self.debugModes.map { mode in
            let name = mode?.name ?? "Materials"
            let label = SceneGraph.Node(parent: slide, label: "Debug \(name)")
            addTitle(name, size: 0.4, y: 3.1, color: [0.85, 0.85, 0.9], to: label)
            label.isVisible = false
            return label
        }
        debugLabels.first?.isVisible = true
    }

    private func updateDebugView(deltaTime: Float) {
        sinceDebugMode += deltaTime
        if sinceDebugMode >= 2 {
            sinceDebugMode = 0
            debugIndex = (debugIndex + 1) % Self.debugModes.count
        }
        if debugMode != Self.debugModes[debugIndex] {
            debugMode = Self.debugModes[debugIndex]
        }
        for (index, label) in debugLabels.enumerated() where label.isVisible != (index == debugIndex) {
            label.isVisible = index == debugIndex
        }
    }

    // Strong, distinct looks so the effect reads from the back of the room.
    private static let grades: [(name: String, settings: SceneGraph.PostProcessing)] = [
        ("Neutral", .init()),
        ("Noir", .init(exposure: -0.1, contrast: 1.8, saturation: 0, vignetteIntensity: 0.9, vignetteRadius: 0.35)),
        ("Vivid", .init(exposure: 0.15, contrast: 1.35, saturation: 2.2, vignetteIntensity: 0.3)),
        ("Overexposed", .init(exposure: 1.2, contrast: 0.8, saturation: 0.6)),
        ("Moody", .init(exposure: -0.8, contrast: 1.5, saturation: 0.5, vignetteIntensity: 1, vignetteRadius: 0.25))
    ]

    // Holds each grade, then eases into the next over `blendTime`.
    private func updateGrade(deltaTime: Float) {
        let holdTime: Float = 2.2
        let blendTime: Float = 0.6
        sinceGrade += deltaTime
        if sinceGrade >= holdTime + blendTime {
            sinceGrade = 0
            gradeIndex = (gradeIndex + 1) % Self.grades.count
        }
        let from = Self.grades[gradeIndex].settings
        let nextIndex = (gradeIndex + 1) % Self.grades.count
        let to = Self.grades[nextIndex].settings
        let linear = max(0, sinceGrade - holdTime) / blendTime
        let t = linear * linear * (3 - 2 * linear)
        func mix(_ a: Float, _ b: Float) -> Float { a + (b - a) * t }
        sceneGraph.postProcessing = SceneGraph.PostProcessing(
            exposure: mix(from.exposure, to.exposure),
            contrast: mix(from.contrast, to.contrast),
            saturation: mix(from.saturation, to.saturation),
            vignetteIntensity: mix(from.vignetteIntensity, to.vignetteIntensity),
            vignetteRadius: mix(from.vignetteRadius, to.vignetteRadius)
        )
        let shown = t < 0.5 ? gradeIndex : nextIndex
        for (index, label) in gradeLabels.enumerated() where label.isVisible != (index == shown) {
            label.isVisible = index == shown
        }
    }

    private func sceneViewSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        // A small window frame around a turntable: SceneView is the window the whole keynote runs in.
        let frame = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.35, 0.38, 0.45]))
        let window = SceneGraph.Node(parent: slide, label: "Window", trs: .init(translation: [0, 1.4, -0.5]))
        for (size, position) in [([6.1, 0.05], [0, 1.7]), ([6.1, 0.05], [0, -1.7]), ([0.05, 3.4], [-3.05, 0]), ([0.05, 3.4], [3.05, 0])] as [(SIMD2<Float>, SIMD2<Float>)] {
            _ = SceneGraph.Node(parent: window, shape: .box(width: size.x, height: size.y, length: 0.05), material: frame, device: demoDevice, trs: .init(translation: [position.x, position.y, 0]))
        }
        let turntable = SceneGraph.Node(parent: slide, label: "Turntable", trs: .init(translation: [0, 1.2, 0]))
        turntable.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)))
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [(.box(width: 0.7, height: 0.7, length: 0.7), [1, 0.4, 0.3]), (.sphere(radius: 0.4), [0.3, 0.8, 1]), (.cone(bottomRadius: 0.4, height: 0.8), [0.5, 0.9, 0.4])]
        for (index, (shape, color)) in shapes.enumerated() {
            let angle = Float(index) * 2 * .pi / 3
            _ = SceneGraph.Node(parent: turntable, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), device: demoDevice, trs: .init(translation: [cos(angle) * 1.4, 0, sin(angle) * 1.4]))
        }
    }
}
