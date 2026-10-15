import GeometryLite3D
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsSceneGraph
import SwiftMesh
import simd

// SceneKit-style features in one scene:
// - Shapes (#61): a row of parametric shapes and 3D text; sliders reshape the torus live.
// - Actions (#62): the shapes spin forever, an orbit pivot turns, and "Hop" runs a one-shot sequence on the text.
// - Constraints (#63): a spotlight and a cone track the orbiting ball, the text faces the camera (Y only), and a
//   small cube is kept within reach of the ball.
// - Implicit animation (#64): "Shuffle" moves the shapes with Transaction.animate; a picker chooses the easing.
// - Category masks and order (#65): a red light only lights category-2 shapes; toggles hide category 2 from the
//   camera and limit picking to category 1; two translucent panes swap which is drawn last (renderingOrder).
// - Fog (#44): a toggle adds distance fog.
// - Custom shaders (#48): the capsule uses ShaderMaterial.normals().
final class SceneKitFeaturesDemo: DemoScene {
    private static let easings: [(String, SceneGraph.Action.TimingMode)] = [
        ("Ease In Out", .easeInEaseOut), ("Ease In", .easeIn), ("Ease Out", .easeOut), ("Linear", .linear),
    ]
    private static let categoryTwo: UInt = 0b10

    private let cameraNode: SceneGraph.Node
    private let torus: SceneGraph.Node
    private let shadowRenderer = SceneGraphShadows(intensity: 0.5)
    private let redPane: SceneGraph.Node
    private let bluePane: SceneGraph.Node
    private let text: SceneGraph.Node
    private var holders: [SceneGraph.Node] = []
    private let homePositions: [SIMD3<Float>]

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 5, 11]
        cameraNode = .camera(eye: eye, target: [0, 1, 0])
        root.addChild(cameraNode)
        _ = SceneGraph.Node(parent: root, label: "Sun", transform: .camera(eye: [3, 8, 4], target: .zero), content: .light(Light(type: .directional, color: [1, 0.97, 0.9], intensity: 0.9)))
        let redLight = SceneGraph.Node(parent: root, label: "Red Light (category 2 only)", transform: .translation(0, 3, 3), content: .light(Light(type: .point, color: [1, 0.15, 0.1], intensity: 25)))
        redLight.lightCategoryBitMask = Self.categoryTwo

        _ = SceneGraph.Node(parent: root, label: "Floor", shape: .box(width: 14, height: 0.1, length: 10), material: BlinnPhongSceneMaterial.plastic([0.55, 0.55, 0.6], shininess: 8), device: demoDevice, trs: .init(translation: [0, -0.05, 0]))

        // Shapes, each spinning inside a holder that Shuffle moves.
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.box(width: 1, height: 1, length: 1), [0.9, 0.3, 0.25]),
            (.sphere(radius: 0.55), [0.25, 0.6, 0.9]),
            (.cylinder(radius: 0.45, height: 1.1), [0.95, 0.75, 0.2]),
            (.cone(bottomRadius: 0.55, height: 1.2), [0.4, 0.8, 0.4]),
            (.capsule(capRadius: 0.35, height: 1.3), [0.75, 0.45, 0.9]),
            (.torus(ringRadius: 0.5, pipeRadius: 0.18), [0.95, 0.5, 0.65]),
        ]
        var homePositions: [SIMD3<Float>] = []
        var torus: SceneGraph.Node?
        for (index, (shape, color)) in shapes.enumerated() {
            let position = SIMD3<Float>(Float(index) * 1.6 - 4, 0.75, 1.5)
            homePositions.append(position)
            let holder = SceneGraph.Node(parent: root, label: "Holder \(index)", trs: .init(translation: position))
            // The capsule uses a custom shader (ShaderMaterial, #48); the rest use Blinn-Phong.
            let material: any MetalSprocketsSceneGraph.Material = if case .capsule = shape, let normals = try? ShaderMaterial.normals() {
                normals
            } else {
                BlinnPhongSceneMaterial.plastic(color)
            }
            let node = SceneGraph.Node(parent: holder, shape: shape, material: material, device: demoDevice)
            // The right half is category 2: lit by the red light, and hideable.
            node.categoryBitMask = index >= shapes.count / 2 ? Self.categoryTwo : 1
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 4 + Float(index))), forKey: "spin")
            holders.append(holder)
            if case .torus = shape {
                torus = node
            }
        }
        self.torus = torus!
        self.homePositions = homePositions

        text = SceneGraph.Node(parent: root, shape: .text("SceneGraph", fontName: "Helvetica-Bold", fontSize: 1, extrusionDepth: 0.25), material: BlinnPhongSceneMaterial.plastic([0.95, 0.95, 0.95]), device: demoDevice, trs: .init(translation: [0, 3.2, -2]))
        // Text geometry starts at x = 0; center it inside a child so the billboard turns about its middle.
        if let bounds = text.meshBounds, case let .mesh(mesh, materials, _, _) = text.content {
            text.content = .empty
            _ = SceneGraph.Node(parent: text, label: "Glyphs", trs: .init(translation: [-(bounds.min.x + bounds.max.x) / 2, 0, 0]), content: .mesh(mesh, materials: materials))
        }
        text.constraints = [.billboard(freeAxes: .y)]

        // An orbiting ball; a spotlight, a cone and a follower cube react to it through constraints.
        let pivot = SceneGraph.Node(parent: root, label: "Orbit Pivot", trs: .init(translation: [0, 1.6, -1]))
        pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)), forKey: "orbit")
        let ball = SceneGraph.Node(parent: pivot, label: "Ball", shape: .sphere(radius: 0.3), material: BlinnPhongSceneMaterial.plastic([1, 0.85, 0.2], shininess: 64), device: demoDevice, trs: .init(translation: [3, 0, 0]))
        ball.run(.repeatForever(.sequence([
            .move(by: [0, 1, 0], duration: 1).timingMode(.easeInEaseOut),
            .move(by: [0, -1, 0], duration: 1).timingMode(.easeInEaseOut),
        ])), forKey: "bob")
        let spot = SceneGraph.Node(parent: root, label: "Spotlight (looks at ball)", trs: .init(translation: [-5, 5, 4]), content: .light(.spot(color: [0.6, 0.8, 1], intensity: 40, innerConeAngle: .pi / 16, outerConeAngle: .pi / 10)))
        spot.constraints = [.lookAt(target: ball)]
        let pointer = SceneGraph.Node(parent: root, label: "Pointer (looks at ball)", shape: .cone(bottomRadius: 0.3, height: 1), material: BlinnPhongSceneMaterial.plastic([0.3, 0.9, 0.9]), device: demoDevice, trs: .init(translation: [5, 0.6, -2]))
        // The cone's tip is +Y.
        pointer.constraints = [.lookAt(target: ball, localFront: [0, 1, 0])]
        let follower = SceneGraph.Node(parent: root, label: "Follower (stays 1-2 from ball)", shape: .box(width: 0.4, height: 0.4, length: 0.4), material: BlinnPhongSceneMaterial.plastic([0.9, 0.9, 0.3]), device: demoDevice, trs: .init(translation: [0, 0.2, -1]))
        follower.constraints = [.distance(target: ball, minimum: 1, maximum: 2)]

        // Two overlapping translucent panes: transparent materials blend in renderingOrder, so the toggle swaps which
        // one looks in front.
        let paneMaterial = { (color: SIMD4<Float>) -> any MetalSprocketsSceneGraph.Material in
            (try? ShaderMaterial.rim(color: color)).map { $0 as any MetalSprocketsSceneGraph.Material } ?? BlinnPhongSceneMaterial.plastic(SIMD3(color.x, color.y, color.z))
        }
        redPane = SceneGraph.Node(parent: root, label: "Red Pane", shape: .plane(width: 2, height: 1.5), material: paneMaterial([1, 0.1, 0.1, 0.6]), device: demoDevice, trs: .init(translation: [-5.4, 1.2, -1.5]))
        bluePane = SceneGraph.Node(parent: root, label: "Blue Pane", shape: .plane(width: 2, height: 1.5), material: paneMaterial([0.1, 0.3, 1, 0.6]), device: demoDevice, trs: .init(translation: [-4.6, 1.6, -1.5]))
        for pane in [redPane, bluePane] {
            // Translucent panes would otherwise cast solid shadows.
            if case let .mesh(mesh, materials, _, receivesShadow) = pane.content {
                pane.content = .mesh(mesh, materials: materials, castsShadow: false, receivesShadow: receivesShadow)
            }
        }

        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(), ShaderMaterialRenderer()],
            cameraMatrix: .camera(eye: eye, target: [0, 1, 0]),
            parameters: [
                .slider("Torus Ring", 0.3...0.8, default: 0.5),
                .slider("Torus Pipe", 0.05...0.3, default: 0.18),
                .choice("Shuffle Easing", Self.easings.map(\.0)),
                .toggle("Show Category 2", default: true),
                .toggle("Fog", default: false),
                .toggle("Blue Pane Drawn Last", default: true),
                .toggle("Pick Category 1 Only", default: false),
                .toggle("Shadows", default: true),
            ]
        )
        actions = [
            DemoAction("Shuffle", systemImage: "shuffle") { [weak self] in self?.shuffle() },
            DemoAction("Reset Layout", systemImage: "arrow.uturn.backward") { [weak self] in self?.resetLayout() },
            DemoAction("Hop", systemImage: "arrow.up.circle") { [weak self] in self?.hop() },
        ]
    }

    override func update(time: Float, deltaTime: Float) {
        torus.shape = .torus(ringRadius: self[value: "Torus Ring"], pipeRadius: self[value: "Torus Pipe"])
        let blueLast = self[flag: "Blue Pane Drawn Last"]
        redPane.renderingOrder = blueLast ? 1 : 2
        bluePane.renderingOrder = blueLast ? 2 : 1
        pickCategoryBitMask = self[flag: "Pick Category 1 Only"] ? 1 : .max
        if self[flag: "Shadows"] != (shadows != nil) {
            shadows = self[flag: "Shadows"] ? shadowRenderer : nil
        }
        sceneGraph.fog = self[flag: "Fog"] ? SceneGraph.Fog(color: [0.55, 0.6, 0.7, 1], startDistance: 8, endDistance: 18) : nil
        let mask: UInt = self[flag: "Show Category 2"] ? .max : ~Self.categoryTwo
        if case var .camera(camera) = cameraNode.content, camera.categoryBitMask != mask {
            camera.categoryBitMask = mask
            cameraNode.content = .camera(camera)
        }
    }

    private var easing: SceneGraph.Action.TimingMode {
        Self.easings[min(Int(self[value: "Shuffle Easing"]), Self.easings.count - 1)].1
    }

    private func shuffle() {
        SceneGraph.Transaction.animate(duration: 0.8, timingMode: easing) {
            for holder in holders {
                holder.trs.translation = [Float.random(in: -5...5), 0.75, Float.random(in: -3...3)]
            }
        }
    }

    private func resetLayout() {
        SceneGraph.Transaction.animate(duration: 0.8, timingMode: easing) {
            for (holder, position) in zip(holders, homePositions) {
                holder.trs.translation = position
            }
        }
    }

    private func hop() {
        text.run(.sequence([
            .move(by: [0, 1, 0], duration: 0.3).timingMode(.easeOut),
            .move(by: [0, -1, 0], duration: 0.3).timingMode(.easeIn),
            .scale(to: [1.2, 0.8, 1.2], duration: 0.08),
            .scale(to: [1, 1, 1], duration: 0.12),
        ]), forKey: "hop")
    }
}
