import GeometryLite3D
import Metal
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsShaderMaterial
import simd
import SwiftMesh

// SceneKit-style features in one scene:
// - Orthographic camera (#87): a toggle swaps the camera's projection.
// - Blinn-Phong emission, normal map and cull mode (#83): three objects at the back; a choice sets the cull mode.
// - Opacity and fades (#76): a slider sets the shapes group's opacity, which every shape inherits; "Fade" runs
//   fadeOut then fadeIn on the text.
// - Shapes (#61): a row of parametric shapes and 3D text; sliders reshape the torus live.
// - Actions (#62): the shapes spin forever, an orbit pivot turns, and "Hop" runs a one-shot sequence on the text.
// - Constraints (#63): a spotlight and a cone track the orbiting ball, the text faces the camera (Y only), and a
//   small cube is kept within reach of the ball.
// - Implicit animation (#64): "Shuffle" moves the shapes with Transaction.animate; a picker chooses the easing.
// - Category masks and order (#65): a red light only lights category-2 shapes; toggles hide category 2 from the
//   camera and limit picking to category 1; two translucent panes swap which is drawn last (renderingOrder).
// - Fog (#44): a toggle adds distance fog.
// - Custom shaders (#48): the capsule uses ShaderMaterial.normals().
// - Node transform helpers (#79): yaw/pitch/roll sliders set the normal-mapped box's eulerAngles; "Look at Ball"
//   turns the follower cube once with look(at:); "Snap to Ball" sets its worldPosition and worldOrientation from
//   the ball, using convertPosition and convertVector.
final class SceneKitFeaturesDemo: DemoScene {
    private static let easings: [(String, SceneGraph.Action.TimingMode)] = [
        ("Ease In Out", .easeInEaseOut), ("Ease In", .easeIn), ("Ease Out", .easeOut), ("Linear", .linear)
    ]
    private static let categoryTwo: UInt = 0b10
    private static let perspective = PerspectiveProjection(verticalAngleOfView: .degrees(45))

    private let cameraNode: SceneGraph.Node
    private let torus: SceneGraph.Node
    private let shadowRenderer = Shadows(intensity: 0.5)
    private let redPane: SceneGraph.Node
    private let bluePane: SceneGraph.Node
    private let text: SceneGraph.Node
    private var holders: [SceneGraph.Node] = []
    // Parent of the shape holders, so its opacity fades them all.
    private let shapesGroup: SceneGraph.Node
    private let cullSphere: SceneGraph.Node
    private let bumpyBox: SceneGraph.Node
    private let ball: SceneGraph.Node
    private let follower: SceneGraph.Node
    private static let cullModes: [(String, MTLCullMode)] = [("None", .none), ("Back", .back), ("Front", .front)]
    private let homePositions: [SIMD3<Float>]

    init() {
        let root = SceneGraph.Node(label: "Root")
        let eye: SIMD3<Float> = [0, 5, 11]
        cameraNode = .camera(.demo, label: "Camera", transform: .init(position: eye, lookingAt: [0, 1, 0]))
        root.addChild(cameraNode)
        root.addChild(SceneGraph.Node(label: "Sun", transform: Transform3D(position: [3, 8, 4], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 0.97, 0.9], intensity: 0.9))))
        let redLight = root.addChild(SceneGraph.Node(label: "Red Light (category 2 only)", transform: Transform3D(storing: .translation(0, 3, 3)), content: .light(Light(type: .point, color: [1, 0.15, 0.1], intensity: 25))))
        redLight.lightCategoryBitMask = Self.categoryTwo

        root.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 14, height: 0.1, length: 10), material: BlinnPhongSceneMaterial.plastic([0.55, 0.55, 0.6], shininess: 8), transform: .init(translation: [0, -0.05, 0])))

        // Shapes, each spinning inside a holder that Shuffle moves.
        let shapesGroup = root.addChild(SceneGraph.Node(label: "Shapes"))
        self.shapesGroup = shapesGroup
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.box(width: 1, height: 1, length: 1), [0.9, 0.3, 0.25]),
            (.sphere(radius: 0.55), [0.25, 0.6, 0.9]),
            (.cylinder(radius: 0.45, height: 1.1), [0.95, 0.75, 0.2]),
            (.cone(bottomRadius: 0.55, height: 1.2), [0.4, 0.8, 0.4]),
            (.capsule(capRadius: 0.35, height: 1.3), [0.75, 0.45, 0.9]),
            (.torus(ringRadius: 0.5, pipeRadius: 0.18), [0.95, 0.5, 0.65])
        ]
        var homePositions: [SIMD3<Float>] = []
        var torus: SceneGraph.Node?
        for (index, (shape, color)) in shapes.enumerated() {
            let position = SIMD3<Float>(Float(index) * 1.6 - 4, 0.75, 1.5)
            homePositions.append(position)
            let holder = shapesGroup.addChild(SceneGraph.Node(label: "Holder \(index)", transform: .init(translation: position)))
            // The capsule uses a custom shader (ShaderMaterial, #48); the rest use Blinn-Phong.
            let material: any SceneMaterial = if case .capsule = shape {
                ShaderMaterial.normals()
            } else {
                BlinnPhongSceneMaterial.plastic(color)
            }
            let node = holder.addChild(SceneGraph.Node(shape: shape, material: material))
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

        text = root.addChild(SceneGraph.Node(shape: .text("SceneGraph", fontName: "Helvetica-Bold", fontSize: 1, extrusionDepth: 0.25), material: BlinnPhongSceneMaterial.plastic([0.95, 0.95, 0.95]), transform: .init(translation: [0, 3.2, -2])))
        // Text geometry starts at x = 0; center it inside a child so the billboard turns about its middle.
        if let bounds = text.meshBounds, case let .mesh(mesh, materials, _, _) = text.content {
            text.content = .empty
            text.addChild(SceneGraph.Node(label: "Glyphs", transform: .init(translation: [-(bounds.min.x + bounds.max.x) / 2, 0, 0]), content: .mesh(mesh, materials: materials)))
        }
        text.constraints = [.billboard(freeAxes: .y)]

        // An orbiting ball; a spotlight, a cone and a follower cube react to it through constraints.
        let pivot = root.addChild(SceneGraph.Node(label: "Orbit Pivot", transform: .init(translation: [0, 1.6, -1])))
        pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)), forKey: "orbit")
        ball = pivot.addChild(SceneGraph.Node(label: "Ball", shape: .sphere(radius: 0.3), material: BlinnPhongSceneMaterial.plastic([1, 0.85, 0.2], shininess: 64), transform: .init(translation: [3, 0, 0])))
        ball.run(.repeatForever(.sequence([
            .move(by: [0, 1, 0], duration: 1).timingMode(.easeInEaseOut),
            .move(by: [0, -1, 0], duration: 1).timingMode(.easeInEaseOut)
        ])), forKey: "bob")
        let spot = root.addChild(SceneGraph.Node(label: "Spotlight (looks at ball)", transform: .init(translation: [-5, 5, 4]), content: .light(.spot(color: [0.6, 0.8, 1], intensity: 40, innerConeAngle: .pi / 16, outerConeAngle: .pi / 10))))
        spot.constraints = [.lookAt(target: ball)]
        let pointer = root.addChild(SceneGraph.Node(label: "Pointer (looks at ball)", shape: .cone(bottomRadius: 0.3, height: 1), material: BlinnPhongSceneMaterial.plastic([0.3, 0.9, 0.9]), transform: .init(translation: [5, 0.6, -2])))
        // The cone's tip is +Y.
        pointer.constraints = [.lookAt(target: ball, localFront: [0, 1, 0])]
        follower = root.addChild(SceneGraph.Node(label: "Follower (stays 1-2 from ball)", shape: .box(width: 0.4, height: 0.4, length: 0.4), material: BlinnPhongSceneMaterial.plastic([0.9, 0.9, 0.3]), transform: .init(translation: [0, 0.2, -1])))
        follower.constraints = [.distance(target: ball, minimum: 1, maximum: 2)]

        // Blinn-Phong extras (#83), at the back: an emissive sphere, a box with a generated bump normal map (lit from
        // above, so each bump's upper side is brighter when the map's +Y is up), and a sphere whose cull mode the
        // "Cull Mode" choice sets (Front shows its inside).
        let glow = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0.1), specular: .color(0.2), shininess: 32, emission: .color([0.2, 1, 0.6]))
        root.addChild(SceneGraph.Node(label: "Emissive Sphere", shape: .sphere(radius: 0.5), material: glow, transform: .init(translation: [-2.2, 0.5, -3.8])))
        var bumpy = BlinnPhongSceneMaterial.plastic([0.85, 0.75, 0.6], shininess: 24)
        bumpy.normalMap = Self.bumpNormalMap().map { .texture($0) }
        bumpyBox = root.addChild(SceneGraph.Node(label: "Normal-Mapped Box", shape: .box(width: 1.4, height: 1.4, length: 0.3), material: bumpy, transform: .init(translation: [0, 0.75, -3.8])))
        cullSphere = root.addChild(SceneGraph.Node(label: "Culled Sphere", shape: .sphere(radius: 0.5), material: BlinnPhongSceneMaterial.plastic([0.95, 0.55, 0.2]), transform: .init(translation: [2.2, 0.5, -3.8])))

        // Two overlapping translucent panes: transparent materials blend in renderingOrder, so the toggle swaps which
        // one looks in front.
        redPane = root.addChild(SceneGraph.Node(label: "Red Pane", shape: .plane(width: 2, height: 1.5), material: ShaderMaterial.rim(color: [1, 0.1, 0.1], opacity: 0.6), transform: .init(translation: [-5.4, 1.2, -1.5])))
        bluePane = root.addChild(SceneGraph.Node(label: "Blue Pane", shape: .plane(width: 2, height: 1.5), material: ShaderMaterial.rim(color: [0.1, 0.3, 1], opacity: 0.6), transform: .init(translation: [-4.6, 1.6, -1.5])))
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
                .toggle("Orthographic", default: false),
                .slider("Shapes Opacity", 0...1, default: 1),
                .choice("Cull Mode", Self.cullModes.map(\.0)),
                .slider("Box Yaw", -Float.pi...Float.pi, default: 0),
                .slider("Box Pitch", -Float.pi...Float.pi, default: 0),
                .slider("Box Roll", -Float.pi...Float.pi, default: 0)
            ]
        )
        actions = [
            DemoAction("Shuffle", systemImage: "shuffle") { [weak self] in self?.shuffle() },
            DemoAction("Reset Layout", systemImage: "arrow.uturn.backward") { [weak self] in self?.resetLayout() },
            DemoAction("Hop", systemImage: "arrow.up.circle") { [weak self] in self?.hop() },
            DemoAction("Fade", systemImage: "circle.lefthalf.filled") { [weak self] in self?.fade() },
            DemoAction("Look at Ball", systemImage: "eye") { [weak self] in self?.lookAtBall() },
            DemoAction("Snap to Ball", systemImage: "arrow.down.to.line") { [weak self] in self?.snapToBall() }
        ]
    }

    override func update(time _: Float, deltaTime _: Float) {
        torus.shape = .torus(ringRadius: self[value: "Torus Ring"], pipeRadius: self[value: "Torus Pipe"])
        var angles = bumpyBox.transform.rotation.euler
        (angles.roll, angles.pitch, angles.yaw) = (self[value: "Box Roll"], self[value: "Box Pitch"], self[value: "Box Yaw"])
        bumpyBox.transform.rotation = .euler(angles)
        if shapesGroup.opacity != self[value: "Shapes Opacity"] {
            shapesGroup.opacity = self[value: "Shapes Opacity"]
        }
        let cullMode = Self.cullModes[min(Int(self[value: "Cull Mode"]), Self.cullModes.count - 1)].1
        if case let .mesh(mesh, materials, castsShadow, receivesShadow) = cullSphere.content, var material = materials.first as? BlinnPhongSceneMaterial, material.renderState.cullMode != cullMode {
            material.renderState.cullMode = cullMode
            cullSphere.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
        let blueLast = self[flag: "Blue Pane Drawn Last"]
        redPane.renderingOrder = blueLast ? 1 : 2
        bluePane.renderingOrder = blueLast ? 2 : 1
        pickCategoryBitMask = self[flag: "Pick Category 1 Only"] ? 1 : .max
        if self[flag: "Shadows"] != (shadows != nil) {
            shadows = self[flag: "Shadows"] ? shadowRenderer : nil
        }
        sceneGraph.fog = self[flag: "Fog"] ? SceneGraph.Fog(color: [0.55, 0.6, 0.7, 1], startDistance: 8, endDistance: 18) : nil
        let mask: UInt = self[flag: "Show Category 2"] ? .max : ~Self.categoryTwo
        if case var .camera(camera) = cameraNode.content {
            let isOrthographic = self[flag: "Orthographic"]
            if camera.categoryBitMask != mask || (camera.projection is OrthographicProjection) != isOrthographic {
                camera.categoryBitMask = mask
                // The orthographic view is about as tall as the perspective one at the scene's center.
                camera.projection = isOrthographic ? OrthographicProjection(halfHeight: 4.5, depthMode: .standard(zClip: 0.01 ... 100)) : Self.perspective
                cameraNode.content = .camera(camera)
            }
        }
    }

    private var easing: SceneGraph.Action.TimingMode {
        Self.easings[min(Int(self[value: "Shuffle Easing"]), Self.easings.count - 1)].1
    }

    private func shuffle() {
        SceneGraph.Transaction.animate(duration: 0.8, timingMode: easing) {
            for holder in holders {
                holder.transform.translation = [Float.random(in: -5...5), 0.75, Float.random(in: -3...3)]
            }
        }
    }

    private func resetLayout() {
        SceneGraph.Transaction.animate(duration: 0.8, timingMode: easing) {
            for (holder, position) in zip(holders, homePositions) {
                holder.transform.translation = position
            }
        }
    }

    // 4 x 4 round bumps, as a tangent-space normal map (+Y up, as BlinnPhongSceneMaterial.normalMap expects).
    static func bumpNormalMap(size: Int = 128) -> MTLTexture? {
        let cells = 4
        let cellSize = Float(size) / Float(cells)
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for row in 0..<size {
            for column in 0..<size {
                // -1...1 within the cell; image rows run down, so up is -row.
                let x = (Float(column).truncatingRemainder(dividingBy: cellSize) + 0.5) / cellSize * 2 - 1
                let y = -((Float(row).truncatingRemainder(dividingBy: cellSize) + 0.5) / cellSize * 2 - 1)
                let radius: Float = 0.8
                let distanceSquared = x * x + y * y
                // A dome of `radius`: its normal points away from the center, flat outside.
                let normal = distanceSquared < radius * radius ? simd_normalize(SIMD3(x, y, sqrt(radius * radius - distanceSquared))) : SIMD3<Float>(0, 0, 1)
                let encoded = (normal * 0.5 + 0.5) * 255
                let index = (row * size + column) * 4
                bytes[index] = UInt8(encoded.x)
                bytes[index + 1] = UInt8(encoded.y)
                bytes[index + 2] = UInt8(encoded.z)
                bytes[index + 3] = 255
            }
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = demoDevice.makeTexture(descriptor: descriptor) else {
            return nil
        }
        texture.label = "Bump Normal Map"
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * 4)
        return texture
    }

    // A one-off turn, unlike the pointer's lookAt constraint. Up is the camera's up, converted to world space.
    private func lookAtBall() {
        follower.look(at: ball.worldPosition, up: cameraNode.convertVector([0, 1, 0], to: nil))
    }

    // Puts the follower just above the ball (a point in the ball's space, converted to world space), turned like it.
    // Its distance constraint then pulls it back out to 1 from the ball.
    private func snapToBall() {
        follower.worldPosition = ball.convertPosition([0, 0.6, 0], to: nil)
        follower.worldOrientation = ball.worldOrientation
    }

    private func fade() {
        text.run(.sequence([.fadeOut(duration: 0.6), .wait(duration: 0.3), .fadeIn(duration: 0.6)]), forKey: "fade")
    }

    private func hop() {
        text.run(.sequence([
            .move(by: [0, 1, 0], duration: 0.3).timingMode(.easeOut),
            .move(by: [0, -1, 0], duration: 0.3).timingMode(.easeIn),
            .scale(to: [1.2, 0.8, 1.2], duration: 0.08),
            .scale(to: [1, 1, 1], duration: 0.12)
        ]), forKey: "hop")
    }
}
