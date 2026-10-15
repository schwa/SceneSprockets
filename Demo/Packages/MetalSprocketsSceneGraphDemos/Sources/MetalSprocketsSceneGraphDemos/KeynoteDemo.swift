import GeometryLite3D
import Metal
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphPBR
import SwiftMesh
import SwiftUI
import simd

// "Introduction to SceneGraph", presented like a keynote and built only from scene graph features (#98). Slides sit
// side by side along +X; the camera flies between them with Transaction.animate, and slides fade in and out with node
// opacity (hidden once faded so they cost nothing). Next/Previous are toolbar actions with the arrow keys; a click
// also advances, and Auto-advance moves on every few seconds.
final class KeynoteDemo: DemoScene {
    private static let spacing: Float = 24
    private static let titles = [
        "SceneGraph", "Scene Graph", "Shapes", "Materials", "Lights", "Actions", "Constraints", "Opacity & Fades", "Blend Modes", "Thank You",
    ]

    private let cameraNode: SceneGraph.Node
    private var slides: [SceneGraph.Node] = []
    private var current = 0
    private var sinceAdvance: Float = 0

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
        actions = [
            DemoAction("Previous", systemImage: "chevron.left", shortcut: .leftArrow) { [weak self] in self?.go(by: -1) },
            DemoAction("Next", systemImage: "chevron.right", shortcut: .rightArrow) { [weak self] in self?.go(by: 1) },
        ]
    }

    private static func eye(for index: Int) -> SIMD3<Float> {
        [Float(index) * spacing, 2.2, 11]
    }

    private static func target(for index: Int) -> SIMD3<Float> {
        [Float(index) * spacing, 1.8, 0]
    }

    override func update(time: Float, deltaTime: Float) {
        guard self[flag: "Auto-advance"] else {
            sinceAdvance = 0
            return
        }
        sinceAdvance += deltaTime
        if sinceAdvance >= self[value: "Seconds per Slide"] {
            go(by: current == slides.count - 1 ? -current : 1)
        }
    }

    override func didPick(_ hit: SceneGraph.Hit?) {
        go(by: 1)
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
        hierarchyDidChange()
    }

    // Jumps to a slide with no transition.
    func show(slide index: Int) {
        for (slideIndex, slide) in slides.enumerated() {
            slide.removeAction(forKey: "fade")
            slide.opacity = slideIndex == index ? 1 : 0
            slide.isVisible = slideIndex == index
        }
        cameraNode.transform = .camera(eye: Self.eye(for: index), target: Self.target(for: index))
        current = index
        sinceAdvance = 0
    }

    var slideCount: Int {
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
        case 2:
            addTitle(title, y: 4, to: slide)
            shapesSlide(slide)
        case 3:
            addTitle(title, y: 4, to: slide)
            materialsSlide(slide)
        case 4:
            addTitle(title, y: 4, to: slide)
            lightsSlide(slide)
        case 5:
            addTitle(title, y: 4, to: slide)
            actionsSlide(slide)
        case 6:
            addTitle(title, y: 4, to: slide)
            constraintsSlide(slide)
        case 7:
            addTitle(title, y: 4, to: slide)
            fadesSlide(slide)
        case 8:
            addTitle(title, y: 4, to: slide)
            blendModesSlide(slide)
        default:
            addTitle(title, size: 1.6, y: 1.5, to: slide)
            addLight(to: slide, at: [0, 4, 6], intensity: 60)
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
}
