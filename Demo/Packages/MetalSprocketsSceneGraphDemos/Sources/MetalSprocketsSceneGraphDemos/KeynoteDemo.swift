import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsGLTF
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphShaderMaterial
import MetalSprocketsSceneGraphBlinnPhong
import MetalSprocketsSceneGraphPBR
import MetalSprocketsSceneGraphPhysics
import SwiftMesh
import SwiftUI
import simd

// "Introduction to SceneGraph", presented like a keynote and built only from scene graph features (#98). Slides sit
// side by side along +X; the camera flies between them with Transaction.animate, and slides fade in and out with node
// opacity (hidden once faded so they cost nothing). Next/Previous are toolbar actions with the arrow keys; a click
// also advances, and Auto-advance moves on every few seconds.
public final class KeynoteDemo: DemoScene {
    private static let spacing: Float = 24
    private static let titles = [
        "SceneGraph", "Scene Graph", "Shapes", "Materials", "Lights", "Actions", "Constraints", "Opacity & Fades", "Blend Modes",
        "Glass", "Shadows", "Fog", "Implicit Animation", "Animation Blending", "glTF & Model I/O", "Hit Testing", "Physics", "SceneView", "Thank You",
    ]

    private let cameraNode: SceneGraph.Node
    private var slides: [SceneGraph.Node] = []
    private var current = 0
    private var sinceAdvance: Float = 0

    // Per-slide state: each is used only while its slide is showing.
    private let shadowRenderer = SceneGraphShadows(intensity: 0.75, softness: 2)
    private var shuffleCubes: [SceneGraph.Node] = []
    private var sinceShuffle: Float = 0
    private var blendMixer: SceneGraph.AnimationMixer?
    private var blendController: SceneGraph.AnimationController?
    private var foxPlayer: SceneGraph.AnimationPlayer?
    private var hitTargets: Set<ObjectIdentifier> = []
    private var physics: SceneGraphPhysicsWorld?
    private var physicsStack: SceneGraph.Node?
    private var sincePhysicsReset: Float = 0

    init() {
        let root = SceneGraph.Node(label: "Root")
        cameraNode = .camera(fieldOfView: 40, eye: Self.eye(for: 0), target: Self.target(for: 0))
        root.addChild(cameraNode)
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [0.05, 0.05, 0.07]), PBRMaterialRenderer(device: demoDevice), ShaderMaterialRenderer()],
            cameraMatrix: .camera(eye: Self.eye(for: 0), target: Self.target(for: 0)),
            parameters: [.toggle("Auto-advance", default: false), .slider("Seconds per Slide", 2...15, default: 6)]
        )
        usesSceneCamera = true
        for (index, title) in Self.titles.enumerated() {
            let slide = SceneGraph.Node(parent: root, label: "Slide \(index + 1): \(title)", trs: .init(translation: [Float(index) * Self.spacing, 0, 0]))
            build(slide: slide, index: index, title: title)
            slide.opacity = index == 0 ? 1 : 0
            slide.isVisible = index == 0
            slides.append(slide)
        }
        physics = try? SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
        actions = [
            DemoAction("Previous", systemImage: "chevron.left", shortcut: .leftArrow) { [weak self] in self?.go(by: -1) },
            DemoAction("Next", systemImage: "chevron.right", shortcut: .rightArrow) { [weak self] in self?.go(by: 1) },
        ]
    }

    private static func eye(for index: Int) -> SIMD3<Float> {
        [Float(index) * spacing, 1.6, 13]
    }

    private static func target(for index: Int) -> SIMD3<Float> {
        [Float(index) * spacing, 1.1, 0]
    }

    override public func update(time: Float, deltaTime: Float) {
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
        if let hit, let target = hitTarget(containing: hit.node) {
            target.run(.group([
                .sequence([.move(by: [0, 1, 0], duration: 0.25), .move(by: [0, -1, 0], duration: 0.25)]),
                .rotate(by: .pi * 2, around: [0, 1, 0], duration: 0.5),
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

    private func updateSlide(time: Float, deltaTime: Float) {
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
        case "glTF & Model I/O":
            foxPlayer?.advance(by: deltaTime)
        case "Physics":
            sincePhysicsReset += deltaTime
            if sincePhysicsReset > 7 {
                resetPhysics()
            }
            physics?.step(deltaTime: min(deltaTime, 1.0 / 30.0))
        default:
            break
        }
    }

    // Shadows and fog apply to the whole scene, so they are switched on only for their slides.
    private func applySceneSettings() {
        shadows = currentTitle == "Shadows" ? shadowRenderer : nil
        sceneGraph.fog = currentTitle == "Fog" ? SceneGraph.Fog(color: [0.05, 0.06, 0.1, 1], startDistance: 12, endDistance: 34) : nil
        if currentTitle == "Physics" {
            resetPhysics()
        }
    }

    // Flies the camera to the slide and cross-fades the slides.
    private func go(by step: Int) {
        let next = min(max(current + step, 0), slides.count - 1)
        guard next != current else {
            return
        }
        sinceAdvance = 0
        let previous = slides[current]
        previous.run(.sequence([.fadeOut(duration: 0.6), .run { $0.isVisible = false }]), forKey: "fade")
        let incoming = slides[next]
        incoming.isVisible = true
        incoming.run(.sequence([.wait(duration: 0.4), .fadeIn(duration: 0.8)]), forKey: "fade")
        SceneGraph.Transaction.animate(duration: 1.2, timingMode: .easeInEaseOut) {
            cameraNode.transform = .camera(eye: Self.eye(for: next), target: Self.target(for: next))
        }
        current = next
        applySceneSettings()
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
        current = index
        sinceAdvance = 0
        applySceneSettings()
    }

    public var slideCount: Int {
        slides.count
    }

    // MARK: - Slides

    private func build(slide: SceneGraph.Node, index: Int, title: String) {
        switch index {
        case 0:
            addTitle("SceneGraph", size: 1.6, y: 2.2, to: slide)
            addTitle("for MetalSprockets", size: 0.6, y: 0.9, color: [0.6, 0.65, 0.75], to: slide)
            let torus = SceneGraph.Node(parent: slide, shape: .torus(ringRadius: 1.2, pipeRadius: 0.25), material: BlinnPhongSceneMaterial.plastic([0.3, 0.5, 1], shininess: 64), device: demoDevice, trs: .init(translation: [0, 1.5, -4]))
            torus.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 1, 0]), duration: 10)))
            addLight(to: slide, at: [3, 5, 5], color: [1, 0.95, 0.9], intensity: 60)
        case 1:
            addTitle(title, y: 4, to: slide)
            sceneGraphSlide(slide)
            addCode("""
            let orbit = Node(parent: sun, label: "Planet Orbit")
            orbit.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 8)))
            let planet = Node(parent: orbit, shape: .sphere(radius: 0.4), material: blue)
            planet.trs.translation = [3.2, 0, 0]
            """, to: slide)
        case 2:
            addTitle(title, y: 4, to: slide)
            shapesSlide(slide)
            addCode("""
            Node(shape: .box(width: 1, height: 1, length: 1), material: red)
            Node(shape: .torus(ringRadius: 0.5, pipeRadius: 0.18), material: pink)
            Node(shape: .text("Hello", fontName: "Helvetica-Bold", fontSize: 1), material: white)
            """, to: slide)
        case 3:
            addTitle(title, y: 4, to: slide)
            materialsSlide(slide)
            addCode("""
            BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.25], shininess: 44)
            try PBRSceneMaterial(device: device, baseColor: [0.95, 0.75, 0.3, 1],
                                 metallic: 1, roughness: 0.3)
            """, to: slide)
        case 4:
            addTitle(title, y: 4, to: slide)
            lightsSlide(slide)
            addCode("""
            var light = Light(type: .point, color: [1, 0.2, 0.2], intensity: 25)
            light.range = 14
            Node(parent: pivot, content: .light(light))
            """, to: slide)
        case 5:
            addTitle(title, y: 4, to: slide)
            actionsSlide(slide)
            addCode("""
            var up = Action.move(by: [0, 2, 0], duration: 0.6)
            up.timingMode = .easeInEaseOut
            cube.run(.repeatForever(.sequence([up, down, .wait(duration: 0.8)])))
            """, to: slide)
        case 6:
            addTitle(title, y: 4, to: slide)
            constraintsSlide(slide)
            addCode("""
            // Point each cone's tip (+Y) at the ball.
            cone.constraints = [.lookAt(target: ball, localFront: [0, 1, 0])]
            """, to: slide)
        case 7:
            addTitle(title, y: 4, to: slide)
            fadesSlide(slide)
            addCode("""
            sphere.run(.repeatForever(.sequence([.fadeOut(duration: 1), .fadeIn(duration: 1)])))
            slide.opacity = 0.5 // children inherit it
            """, to: slide)
        case 8:
            addTitle(title, y: 4, to: slide)
            blendModesSlide(slide)
            addCode("""
            BlinnPhongSceneMaterial(..., emission: .color(red),
                renderState: MaterialRenderState(blendMode: .add))
            MaterialRenderState(fillMode: .lines)
            """, to: slide)
        default:
            buildLaterSlide(slide, title: title)
        }
    }

    private func buildLaterSlide(_ slide: SceneGraph.Node, title: String) {
        if title == "Thank You" {
            addTitle(title, size: 1.6, y: 1.5, to: slide)
            addLight(to: slide, at: [0, 4, 6], intensity: 60)
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
            sun.transform = .camera(eye: [3, 6, 4], target: .zero)
            scene.shadows = SceneGraphShadows(intensity: 0.75, softness: 2)
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
            let controller = AnimationController(clips: [bounce, sway])
            controller.blend([0, 1], parameter: weight)
            controller.advance(by: deltaTime)
            mixer.apply(controller.layers)
            """, to: slide)
        case "glTF & Model I/O":
            importSlide(slide)
            addCode("""
            let fox = try GLTFAsset(url: foxURL, device: device).makeSceneGraph(device: device)
            let pedestal = try ModelIOSceneGraph(url: objURL, device: device)
            player = AnimationPlayer(clip: fox.animations[1])
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
            box.physicsBody = .init(type: .dynamic, shape: .boundingBox)
            let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
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
    private func addTitle(_ text: String, size: Float = 0.9, y: Float, color: SIMD3<Float> = [0.95, 0.95, 0.97], to parent: SceneGraph.Node) {
        let holder = SceneGraph.Node(parent: parent, label: "Title \"\(text)\"", trs: .init(translation: [0, y, 0]))
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(color * 0.4), specular: .color(0.3), shininess: 32, emission: .color(color * 0.6))
        let label = SceneGraph.Node(parent: holder, shape: .text(text, fontName: "Helvetica-Bold", fontSize: size, extrusionDepth: size * 0.15), material: material, device: demoDevice)
        if let bounds = label.meshBounds {
            label.trs.translation.x = -(bounds.min.x + bounds.max.x) / 2
        }
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
        // A sun, a planet orbiting it and a moon orbiting the planet: each orbit is a parent node that turns.
        addLight(to: slide, at: [0, 1.5, 0], color: [1, 0.85, 0.6], intensity: 40)
        _ = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.8), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 0.75, 0.3])), device: demoDevice, trs: .init(translation: [0, 1.5, 0]))
        let orbit = SceneGraph.Node(parent: slide, label: "Planet Orbit", trs: .init(translation: [0, 1.5, 0]))
        orbit.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)))
        let planet = SceneGraph.Node(parent: orbit, shape: .sphere(radius: 0.4), material: BlinnPhongSceneMaterial.plastic([0.3, 0.55, 1]), device: demoDevice, trs: .init(translation: [3.2, 0, 0]))
        let moonOrbit = SceneGraph.Node(parent: planet, label: "Moon Orbit")
        moonOrbit.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 2)))
        _ = SceneGraph.Node(parent: moonOrbit, shape: .sphere(radius: 0.15), material: BlinnPhongSceneMaterial.plastic([0.8, 0.8, 0.8]), device: demoDevice, trs: .init(translation: [0.8, 0, 0]))
    }

    private func shapesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 70)
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.box(width: 1, height: 1, length: 1), [1, 0.4, 0.3]),
            (.sphere(radius: 0.6), [1, 0.8, 0.3]),
            (.cylinder(radius: 0.5, height: 1.2), [0.4, 0.9, 0.4]),
            (.cone(bottomRadius: 0.6, height: 1.2), [0.3, 0.8, 1]),
            (.capsule(capRadius: 0.4, height: 1.4), [0.6, 0.5, 1]),
            (.torus(ringRadius: 0.5, pipeRadius: 0.18), [1, 0.5, 0.8]),
        ]
        for (index, (shape, color)) in shapes.enumerated() {
            let node = SceneGraph.Node(parent: slide, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), device: demoDevice, trs: .init(translation: [Float(index) * 1.8 - 4.5, 1.2, 0]))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 5 + Float(index))))
        }
    }

    private func materialsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 5, 6], intensity: 80)
        // Blinn-Phong on the top row; PBR below, from rough to smooth.
        for index in 0..<4 {
            let x = Float(index) * 2 - 3
            _ = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.7), material: BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.25], shininess: 4 + Float(index) * 40), device: demoDevice, trs: .init(translation: [x, 2.2, 0]))
            if let pbr = try? PBRSceneMaterial(device: demoDevice, baseColor: [0.95, 0.75, 0.3, 1], metallic: 1, roughness: 0.8 - Float(index) * 0.25) {
                _ = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.7), material: pbr, device: demoDevice, trs: .init(translation: [x, 0.4, 0]))
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
            let material: any MetalSprocketsSceneGraph.Material = index.isMultiple(of: 2)
                ? BlinnPhongSceneMaterial.plastic([0.95, 0.4, 0.6], shininess: 48)
                : (try? PBRSceneMaterial(device: demoDevice, baseColor: [0.4, 0.6, 1, 1], metallic: 0, roughness: 0.3)) ?? BlinnPhongSceneMaterial.plastic([0.4, 0.6, 1])
            let sphere = SceneGraph.Node(parent: slide, shape: .sphere(radius: 0.6), material: material, device: demoDevice, trs: .init(translation: [Float(index) * 1.6 - 4, 1.2, 0]))
            sphere.run(.sequence([.wait(duration: Float(index) * 0.3), .repeatForever(.sequence([.fadeOut(duration: 1), .fadeIn(duration: 1), .wait(duration: 0.5)]))]))
        }
    }

    private func blendModesSlide(_ slide: SceneGraph.Node) {
        // Three glowing discs in add mode overlap like stage lights; a wireframe sphere turns behind them.
        let colors: [SIMD3<Float>] = [[1, 0.1, 0.1], [0.1, 1, 0.1], [0.1, 0.2, 1]]
        for (index, color) in colors.enumerated() {
            let angle = Float(index) * 2 * .pi / 3 + .pi / 2
            let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color), renderState: MaterialRenderState(blendMode: .add))
            _ = SceneGraph.Node(parent: slide, shape: .cylinder(radius: 1.3, height: 0.02), material: material, device: demoDevice, trs: .init(translation: [cos(angle) * 0.9, 1.6 + sin(angle) * 0.9, 1], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0])))
        }
        let wire = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.5, 0.55, 0.65]), renderState: MaterialRenderState(fillMode: .lines))
        let sphere = SceneGraph.Node(parent: slide, shape: .sphere(radius: 1.5), material: wire, device: demoDevice, trs: .init(translation: [0, 1.5, -3]))
        sphere.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 12)))
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
            let material: any MetalSprocketsSceneGraph.Material = index.isMultiple(of: 2)
                ? BlinnPhongSceneMaterial.plastic(color, shininess: 32)
                : (try? PBRSceneMaterial(device: demoDevice, baseColor: SIMD4(color, 1), metallic: 0, roughness: 0.4)) ?? BlinnPhongSceneMaterial.plastic(color)
            let bar = SceneGraph.Node(parent: slide, shape: .box(width: 0.5, height: 3, length: 0.5), material: material, device: demoDevice, trs: .init(translation: [x, 1.6, -2.5]))
            bar.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6 + Float(index))))
        }
        let shapes: [(SceneGraph.Shape, Float, Float)] = [
            (.sphere(radius: 0.9), -2.6, 0),
            (.box(width: 1.6, height: 1.6, length: 0.4), 0, 0.15),
            (.torus(ringRadius: 0.75, pipeRadius: 0.3), 2.6, 0.05),
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
        _ = SceneGraph.Node(parent: slide, label: "Sun", transform: .camera(eye: [3, 6, 4], target: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 1.5)))
        _ = SceneGraph.Node(parent: slide, label: "Floor", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.7, 0.7, 0.75], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))
        let torus = SceneGraph.Node(parent: slide, shape: .torus(ringRadius: 0.8, pipeRadius: 0.25), material: BlinnPhongSceneMaterial.plastic([0.95, 0.75, 0.3], shininess: 48), device: demoDevice, trs: .init(translation: [0, 1.8, 0]))
        torus.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.5, 0]), duration: 6)))
        _ = SceneGraph.Node(parent: slide, shape: .box(width: 1, height: 1, length: 1), material: BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.3]), device: demoDevice, trs: .init(translation: [-3, 0.5, 0]))
        _ = SceneGraph.Node(parent: slide, shape: .cylinder(radius: 0.35, height: 2), material: BlinnPhongSceneMaterial.plastic([0.4, 0.8, 0.5]), device: demoDevice, trs: .init(translation: [3, 1, 0]))
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
            .init(target: body, path: .translation, sampler: .init(times: [0, 0.5, 1], values: vector([[0, 0.5, 0], [0, 2, 0], [0, 0.5, 0]]), interpolation: .linear)),
        ])
        let sway = SceneGraph.AnimationClip(name: "Sway", channels: [
            .init(target: body, path: .rotation, sampler: .init(times: [0, 1, 2], values: quaternions([-0.4, 0.4, -0.4], axis: [0, 0, 1]), interpolation: .linear)),
            .init(target: head, path: .rotation, sampler: .init(times: [0, 1, 2], values: quaternions([0.6, -0.6, 0.6], axis: [0, 1, 0]), interpolation: .linear)),
        ])
        blendMixer = SceneGraph.AnimationMixer(clips: [bounce, sway])
        blendController = SceneGraph.AnimationController(clips: [bounce, sway])
    }

    private func importSlide(_ slide: SceneGraph.Node) {
        _ = SceneGraph.Node(parent: slide, label: "Sun", transform: .camera(eye: [2, 4, 3], target: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 2)))
        addLight(to: slide, at: [-3, 3, 5], color: [0.6, 0.7, 1], intensity: 30)
        // The fox is about 100 units long and the pedestal about 1; the holder scales both up for the slide.
        let holder = SceneGraph.Node(parent: slide, label: "Imported", trs: .init(translation: [0, 0.3, -1], scale: [1.4, 1.4, 1.4]))
        do {
            if let url = Bundle.module.url(forResource: "Fox", withExtension: "glb", subdirectory: "Resources") {
                let fox = try GLTFAsset(url: url, device: demoDevice).makeSceneGraph(device: demoDevice)
                let foxHolder = SceneGraph.Node(parent: holder, label: "Fox", trs: .init(scale: [0.02, 0.02, 0.02]))
                for child in fox.sceneGraph.root.children {
                    foxHolder.addChild(child)
                }
                if let clip = fox.animations.dropFirst().first ?? fox.animations.first {
                    foxPlayer = SceneGraph.AnimationPlayer(clip: clip)
                }
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

    private func hitTestingSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.box(width: 1, height: 1, length: 1), [1, 0.4, 0.3]),
            (.sphere(radius: 0.6), [1, 0.8, 0.3]),
            (.cone(bottomRadius: 0.6, height: 1.2), [0.3, 0.8, 1]),
            (.torus(ringRadius: 0.5, pipeRadius: 0.18), [1, 0.5, 0.8]),
        ]
        for (index, (shape, color)) in shapes.enumerated() {
            let node = SceneGraph.Node(parent: slide, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), device: demoDevice, trs: .init(translation: [Float(index) * 2.2 - 3.3, 1.2, 0]))
            hitTargets.insert(ObjectIdentifier(node))
        }
        addTitle("Click a shape", size: 0.35, y: 2.8, color: [0.6, 0.65, 0.75], to: slide)
    }

    private func physicsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 80)
        let ground = SceneGraph.Node(parent: slide, label: "Ground", shape: .box(width: 12, height: 0.2, length: 4), material: BlinnPhongSceneMaterial.plastic([0.5, 0.5, 0.55], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.1, 0]))
        ground.physicsBody = .init(type: .static, shape: .boundingBox, friction: 0.6, restitution: 0.3)
        physicsStack = SceneGraph.Node(parent: slide, label: "Bodies")
    }

    // Restacks the boxes and throws a new ball. Hidden slides drop out of the physics world, so this runs on arrival.
    private func resetPhysics() {
        guard let physicsStack else {
            return
        }
        sincePhysicsReset = 0
        physicsStack.removeAllChildren()
        let colors: [SIMD3<Float>] = [[0.8, 0.5, 0.2], [0.6, 0.3, 0.15], [0.7, 0.6, 0.3], [0.5, 0.4, 0.2]]
        for row in 0..<4 {
            let count = 4 - row
            for column in 0..<count {
                let x = 1.5 + Float(column) * 0.62 - Float(count - 1) * 0.31
                let box = SceneGraph.Node(parent: physicsStack, shape: .box(width: 0.6, height: 0.6, length: 0.6), material: BlinnPhongSceneMaterial.plastic(colors[(row + column) % colors.count], shininess: 16), device: demoDevice, trs: .init(translation: [x, 0.3 + Float(row) * 0.61, 0]))
                box.physicsBody = .init(type: .dynamic, shape: .boundingBox, friction: 0.4, restitution: 0.2)
            }
        }
        let ball = SceneGraph.Node(parent: physicsStack, label: "Ball", shape: .sphere(radius: 0.35), material: BlinnPhongSceneMaterial.plastic([0.9, 0.15, 0.15], shininess: 64), device: demoDevice, trs: .init(translation: [-4.5, 1.2, 0]))
        ball.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.35), friction: 0.3, restitution: 0.4)
        physics?.sync()
        physics?.setVelocity([14, 3, 0], of: ball)
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
