import AVFoundation
import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsGLTF
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsBlinnPhong
import SceneSprocketsGizmos
import SceneSprocketsPBR
import SceneSprocketsPhysics
import SceneSprocketsShaderMaterial
import SceneSprocketsTerrain
import SceneSprocketsToon
import SceneSprocketsVoxels
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
    // debugging, then add-ons (#310). Slides are built by title, so reordering only means editing this list.
    public static let titles = [
        "SceneSprockets", "SceneView", "Scene Graph", "Shapes", "Materials", "Lights",
        "Shadows", "Fog", "Opacity & Fades", "Blend Modes", "Glass", "PBR Extensions", "Custom Shaders", "Video Textures", "glTF & Model I/O",
        "Actions", "Implicit Animation", "Constraints", "Animation Blending", "Deformation",
        "Particles", "Mesh Emitters",
        "Physics", "Post-Processing", "Level of Detail", "Performance", "SwiftECS World",
        "Hit Testing", "Gizmos", "Debug Views",
        "Point Clouds", "Terrain", "Metaballs", "Voxels", "Toon",
        "Thank You"
    ]

    private let cameraNode: SceneGraph.Node
    private var slides: [SceneGraph.Node] = []
    private var current = 0
    private var sinceAdvance: Float = 0
    // 0 = no fog, 1 = the Fog slide's fog. Eases with the transition so the fog does not pop in (#333).
    private var fogAmount: Float = 0

    // Per-slide state: each is used only while its slide is showing.
    private let shadowRenderer = Shadows(intensity: 0.75, softness: 2)
    private static let shadowedTitles: Set<String> = ["Shadows", "Metaballs", "Voxels", "Toon"]
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
    private var videoTexture: VideoTexture?
    private var videoLoopObserver: NSObjectProtocol?
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
    // Metaballs slide: the signed distance node, reshaped every frame.
    private var metaballs: SceneGraph.Node?
    // Voxels slide: the monument, whose surface follows the Voxel Lighting control.
    private var monument: SceneGraph.Node?
    // Toon slide: each shape and its base material, restyled by the Bands and Outline Width controls.
    private var toonShapes: [(node: SceneGraph.Node, material: ToonMaterial)] = []
    // Slide controls (#446–#473). `appliedValues` holds the last value each control was applied with.
    private var appliedValues: [String: Float] = [:]
    private var baseLightIntensities: [ObjectIdentifier: Float] = [:]
    private var orbitPaths: [SceneGraph.Node] = []
    private var colorLightPivots: [SceneGraph.Node] = []
    private var shadowSun: SceneGraph.Node?
    private var alphaDisc: SceneGraph.Node?
    private var glassMaterials: [(material: PBRSceneMaterial, roughness: Float)] = []
    private var pbrExtensionMaterials: [(material: PBRSceneMaterial, base: PBRMaterialUniforms)] = []
    private var rimNodes: [SceneGraph.Node] = []
    private var fireflyTrails: [(node: SceneGraph.Node, system: SceneParticleSystem)] = []
    private var hopCubes: [SceneGraph.Node] = []
    private var fadeSpheres: [SceneGraph.Node] = []
    private var lookAtCones: [(node: SceneGraph.Node, constraint: SceneGraph.Constraint)] = []
    private var slideEmitters: [String: (node: SceneGraph.Node, system: SceneParticleSystem)] = [:]
    private var crateCountLabel: SceneGraph.Node?
    private var crateGrid: SceneGraph.Node?
    private var galaxy: SceneGraph.Node?
    private var terrainNode: SceneGraph.Node?

    init() {
        let root = SceneGraph.Node(label: "Root")
        // Shared so raymarched PBR surfaces use the same environment as PBR meshes.
        let pbr = PBRMaterialRenderer()
        cameraNode = .camera(.perspective(fieldOfView: .degrees(40), zClip: 0.01 ... 100), label: "Camera", transform: .init(position: Self.eye(for: 0), lookingAt: Self.target(for: 0)))
        root.addChild(cameraNode)
        super.init(
            sceneGraph: SceneGraph(root: root),
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [0.05, 0.05, 0.07]), pbr, ShaderMaterialRenderer(), PointCloudRenderer(), TerrainRenderer(), SignedDistanceRenderer(ambientLightColor: [0.05, 0.05, 0.07], pbr: pbr), VoxelRenderer(ambientLightColor: [0.15, 0.15, 0.18], pbr: pbr), ToonRenderer()],
            cameraMatrix: .camera(eye: Self.eye(for: 0), target: Self.target(for: 0)),
            parameters: [.choice("Slide", Self.titles), .toggle("Auto-advance", default: false), .slider("Seconds per Slide", 2...15, default: 6)]
        )
        usesSceneCamera = true
        for (index, title) in Self.titles.enumerated() {
            let slide = root.addChild(SceneGraph.Node(label: "Slide \(index + 1): \(title)", transform: .init(translation: [Float(index) * Self.spacing, 0, 0])))
            build(slide: slide, title: title)
            Self.isolateLights(of: slide, index: index)
            slide.opacity = index == 0 ? 1 : 0
            slide.isVisible = index == 0
            slides.append(slide)
        }
        // Every slide's controls get their defaults now, so update code can read them before a slide is shown and
        // values given on the command line are kept.
        for parameter in Self.titles.flatMap(Self.slideParameters(for:)) where values[parameter.name] == nil {
            values[parameter.name] = parameter.defaultValue
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
        • .sceneCameraControl() gives you orbit and zoom for free.
        • Shadows are one more argument.
        """,
        "Scene Graph": """
        • A tree of nodes. Each node has a transform, and children move with their parent.
        • The planet orbits because its parent spins; the moon rides along on the planet.
        • Nodes are stored in a SwiftECS world, so large scenes stay fast.
        """,
        "Shapes": """
        • Built-in shapes: box, sphere, cylinder, teapot, cone, capsule, torus, plus 3D text and extruded paths.
        • One line each: Node(shape:material:).
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
        • Turn them on in SceneView with Shadows; softness and intensity are settings.
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
        "Video Textures": """
        • VideoTexture plays an AVPlayer into a Metal texture.
        • Use it in any material slot that takes a texture, like SceneKit's material.diffuse.contents = player.
        • Here it is the emission of a screen and of a spinning cube.
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
        "Point Clouds": """
        • An add-on, not built in: import SceneSprocketsAddOns and add PointCloudRenderer.
        • Points are rasterized with compute shaders (MetalSprocketsAddOns), nearest point per pixel.
        • They depth-test against the rest of the scene like any mesh.
        """,
        "Terrain": """
        • An add-on: import SceneSprocketsTerrain and add TerrainRenderer.
        • The Golden Gate from USGS elevation data, 16 km square, tessellated on the GPU every frame.
        • A concurrent binary tree splits triangles near the camera and merges them far away.
        • Lit by the scene's directional light; heights are exaggerated here.
        """,
        "Metaballs": """
        • An add-on: import SceneSprocketsAddOns and add SignedDistanceRenderer.
        • Spheres in a smooth union merge as they move, raymarched on the GPU every frame.
        • Lit like PBR (or Blinn-Phong) meshes; they write depth, and cast and receive shadows.
        """,
        "Voxels": """
        • An add-on: import SceneSprocketsVoxels and add VoxelRenderer.
        • A MagicaVoxel .vox file loads into a 3D texture; the GPU ray-marches the grid, no meshes.
        • A .vox scene graph places every model; voxels are lit like PBR or Blinn-Phong meshes.
        • Voxels write depth and cast shadows, on the floor and on themselves.
        • Model: "monu10" from MagicaVoxel's samples by @ephtracy, after Monument Valley.
        """,
        "Toon": """
        • An add-on: import SceneSprocketsToon and add ToonRenderer.
        • Cel shading: each light's N·L is cut into flat bands, with a hard highlight and a rim light.
        • Outlines are the mesh's back faces pushed out a fixed number of pixels (an inverted hull).
        • Toon meshes cast and receive shadows like any other mesh.
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
        publishSlideControls()
    }

    // Shows the current slide's own controls in the inspector (#441).
    private func publishSlideControls() {
        contextTitle = "Slide: \(currentTitle)"
        contextParameters = Self.slideParameters(for: currentTitle)
        contextActions = slideActions(for: currentTitle)
    }

    // Slides share one value dictionary, so every name here must be unique across the deck.
    static func slideParameters(for title: String) -> [DemoParameter] {
        switch title {
        case "Scene Graph":
            [.slider("Orbit Speed", 0...3, default: 1), .toggle("Orbit Paths", default: true)]
        case "Materials":
            [.slider("Material Spin", 0...3, default: 1), .slider("Materials Lighting", 0...2, default: 1)]
        case "Lights":
            [
                .slider("Light Orbit Speed", 0...3, default: 1), .slider("Light Intensity", 0...3, default: 1), .slider("Light Range", 1...14, default: 14),
                .toggle("Red Light", default: true), .toggle("Green Light", default: true), .toggle("Blue Light", default: true)
            ]
        case "Shadows":
            [.toggle("Cast Shadows", default: true), .slider("Sun Angle", -90...90, default: 0), .slider("Shadow Spin", 0...3, default: 1)]
        case "Fog":
            [.toggle("Fog", default: true), .slider("Fog Start", 0...40, default: 12), .slider("Fog End", 5...80, default: 34)]
        case "Opacity & Fades":
            [.slider("Fade Speed", 0...3, default: 1)]
        case "Blend Modes":
            [.slider("Wall Speed", 0...3, default: 1), .slider("Alpha Opacity", 0...1, default: 0.5)]
        case "Glass":
            [.slider("Frosting", 0...1, default: 0), .slider("Thickness", 0...3, default: 0.6), .slider("Transmission", 0.05...1, default: 1), .slider("Glass Spin", 0...3, default: 1)]
        case "PBR Extensions":
            [
                .toggle("Sheen", default: true), .toggle("Diffuse Transmission", default: true), .toggle("Clearcoat", default: true), .toggle("Iridescence", default: true),
                .slider("Piece Spin", 0...3, default: 1)
            ]
        case "Custom Shaders":
            [.choice("Rim Colors", rimColorPairs.map(\.name)), .slider("Shader Spin", 0...3, default: 1)]
        case "glTF & Model I/O":
            [.slider("Animation Speed", 0...3, default: 1), .toggle("Firefly Trails", default: true)]
        case "Actions":
            [.slider("Hop Speed", 0...3, default: 1)]
        case "Implicit Animation":
            [.toggle("Auto-shuffle", default: true), .slider("Shuffle Duration", 0.1...3, default: 0.8)]
        case "Constraints":
            [.toggle("Look At", default: true), .slider("Ball Speed", 0...3, default: 1)]
        case "Animation Blending":
            [.toggle("Auto Blend", default: true), .slider("Blend", 0...1, default: 0.5), .slider("Clip Speed", 0...3, default: 1)]
        case "Deformation":
            [.toggle("Animate Deformation", default: true), .slider("Bumps", 0...1, default: 0.5), .slider("Squash", 0...1, default: 0), .slider("Bend", -1.4...1.4, default: 0.7)]
        case "Particles":
            [.toggle("Campfire", default: true), .toggle("Geyser", default: true), .toggle("Fireworks", default: true)]
        case "Post-Processing":
            [
                .choice("Grade", ["Cycle"] + grades.map(\.name) + ["Custom"]), .slider("Exposure", -2...2, default: 0), .slider("Contrast", 0...2, default: 1),
                .slider("Saturation", 0...3, default: 1), .slider("Vignette", 0...1, default: 0)
            ]
        case "Level of Detail":
            [.toggle("Animate Distance", default: true), .slider("Distance", 11...27, default: 15)]
        case "Performance":
            [.toggle("Wave", default: true), .slider("Crate Grid", 1...Float(crateGridSize), default: Float(crateGridSize))]
        case "SwiftECS World":
            [.slider("Cohesion", 0...2, default: 0.6), .slider("Alignment", 0...2, default: 0.8), .slider("Separation", 0...1, default: 0.35)]
        case "Gizmos":
            [.choice("Gizmo Mode", ["Cycle", "Translate", "Rotate", "Scale"])]
        case "Debug Views":
            [.choice("Debug View", ["Cycle"] + debugModes.map { $0?.name ?? "Materials" })]
        case "Point Clouds":
            [.slider("Galaxy Speed", 0...5, default: 1), .slider("Point Size", 1...8, default: 2)]
        case "Terrain":
            [.slider("Terrain Speed", 0...5, default: 1), .slider("Height Exaggeration", 0...8, default: 3), .choice("Terrain Style", terrainStyles.map(\.name), default: 3)]
        case "Physics":
            [.toggle("Auto-roll", default: true)]
        case "Metaballs":
            [.slider("Metaball Count", 1...16, default: 7), .slider("Metaball Size", 0.15...0.7, default: 0.38), .slider("Smoothing", 0.05...1.5, default: 0.7), .choice("Metaball Lighting", lightingModels, default: 0)]
        case "Voxels":
            [.choice("Voxel Lighting", lightingModels, default: 1)]
        case "Toon":
            [.slider("Bands", 1...5, default: 2), .slider("Outline Width", 0...8, default: 3)]
        default:
            []
        }
    }

    private func slideActions(for title: String) -> [DemoAction] {
        func action(_ name: String, _ image: String, _ perform: @escaping (KeynoteDemo) -> Void) -> DemoAction {
            DemoAction(name, systemImage: image) { [weak self] in
                if let self {
                    perform(self)
                }
            }
        }
        return switch title {
        case "Opacity & Fades":
            [action("Restart Fades", "arrow.counterclockwise") { $0.startFades() }]
        case "Video Textures":
            [action("Play/Pause", "playpause") { $0.toggleVideo() }, action("Restart Video", "arrow.counterclockwise") { $0.restartVideo() }]
        case "glTF & Model I/O":
            [action("Restart Animation", "arrow.counterclockwise") { $0.importedPlayer?.time = 0 }]
        case "Actions":
            [action("Restart Hops", "arrow.counterclockwise") { $0.startHops() }]
        case "Implicit Animation":
            [action("Shuffle", "shuffle") { $0.shuffle() }]
        case "Particles":
            [action("Restart Particles", "arrow.counterclockwise") { $0.restartParticles() }]
        case "Mesh Emitters":
            [action("Restart Fox", "arrow.counterclockwise") { $0.burningFox?.restart() }]
        case "SwiftECS World":
            [action("Scatter Boids", "sparkles") { $0.boids?.scatter() }]
        case "Gizmos":
            [action("Reset Box", "arrow.counterclockwise") { $0.resetGizmoTarget() }]
        case "Physics":
            [action("Roll Dice", "dice") { $0.resetPhysics() }]
        case "Thank You":
            [action("Replay Finale", "party.popper") { $0.startFinale(after: 0) }]
        default:
            []
        }
    }

    private func updateFog(deltaTime: Float) {
        let target: Float = currentTitle == "Fog" && self[flag: "Fog"] ? 1 : 0
        fogAmount += min(max(target - fogAmount, -deltaTime), deltaTime)
        guard fogAmount > 0 else {
            sceneGraph.fog = nil
            return
        }
        // Pushes the fog out of sight as the amount drops.
        let distance = (1 - fogAmount) * 300
        let start = self[value: "Fog Start"]
        let end = max(self[value: "Fog End"], start + 0.1)
        sceneGraph.fog = SceneGraph.Fog(color: [0.05, 0.06, 0.1, 1], startDistance: start + distance, endDistance: end + distance)
    }

    private func updateSlide(time: Float, deltaTime: Float) {
        updateFog(deltaTime: deltaTime)
        updateTumblingLetters(deltaTime: deltaTime)
        updateSlideControls()
        switch currentTitle {
        case "Implicit Animation":
            sinceShuffle += deltaTime
            if self[flag: "Auto-shuffle"], sinceShuffle >= 0.8 + self[value: "Shuffle Duration"] {
                shuffle()
            }
        case "Animation Blending":
            guard var controller = blendController, let blendMixer else {
                return
            }
            // The blend weight sweeps from bounce to sway and back, unless the Blend control sets it.
            if self[flag: "Auto Blend"] {
                self[value: "Blend"] = (sin(time * 0.8) + 1) / 2
            }
            controller.blend([0, 1], parameter: self[value: "Blend"])
            controller.advance(by: deltaTime * self[value: "Clip Speed"])
            blendMixer.apply(controller.layers)
            blendController = controller
        case "PBR Extensions":
            for piece in pbrExtensionPieces {
                piece.node.transform.rotation = Rotation3D(simd_normalize(simd_quatf(angle: deltaTime * piece.speed * self[value: "Piece Spin"], axis: piece.axis) * piece.node.transform.rotation.quaternion))
            }
        case "Deformation":
            if self[flag: "Animate Deformation"] {
                self[value: "Bumps"] = (sin(time * 1.3) + 1) / 2
                self[value: "Squash"] = max(0, sin(time * 0.7))
                self[value: "Bend"] = sin(time * 1.5) * 1.4
            }
            let weights = [self[value: "Bumps"], self[value: "Squash"]]
            for node in morphed {
                node.morphWeights = weights
            }
            // The total bend at the tip, shared by every bending joint.
            let rotation = simd_quatf(angle: self[value: "Bend"] / Float(Self.tubeJointCount - 1), axis: [0, 0, 1])
            for joint in bendingJoints {
                joint.transform.rotation = Rotation3D(rotation)
            }
        case "Level of Detail":
            // Out of phase, 11 to 27 units from the camera, so each crosses both switch distances. Without animation,
            // all sit at the Distance control's distance (z = 13 is the camera).
            let animates = self[flag: "Animate Distance"]
            for (index, node) in detailed.enumerated() {
                node.transform.translation.z = animates ? -6 + sin(time * 0.8 + Float(index) * 2.1) * 8 : 13 - self[value: "Distance"]
            }
        case "Performance":
            if self[flag: "Wave"] {
                waveCrates(time: time)
            }
        case "Post-Processing":
            updateGrade(deltaTime: deltaTime)
        case "Debug Views":
            updateDebugView(deltaTime: deltaTime)
        case "SwiftECS World":
            boids?.step(deltaTime: deltaTime)
        case "Gizmos":
            let modes: [TransformGizmo.Mode] = [.translate, .rotate, .scale]
            let picked = Int(self[value: "Gizmo Mode"])
            gizmoMode = picked == 0 ? modes[Int(time / 2.5) % modes.count] : modes[min(picked - 1, modes.count - 1)]
        case "Metaballs":
            updateMetaballs(time: time)
        case "Voxels":
            updateVoxelLighting()
        case "Toon":
            updateToonMaterials()
        case "Video Textures":
            videoTexture?.update()
        case "glTF & Model I/O":
            importedPlayer?.advance(by: deltaTime * self[value: "Animation Speed"])
        case "Particles":
            flickerCampfire(time: time)
        case "Mesh Emitters":
            burningFox?.update(sceneGraph: sceneGraph, deltaTime: deltaTime)
        case "Physics":
            sincePhysicsReset += deltaTime
            if self[flag: "Auto-roll"], sincePhysicsReset > 5 {
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
        let castsShadows = currentTitle != "Shadows" || self[flag: "Cast Shadows"]
        shadows = Self.shadowedTitles.contains(currentTitle) && castsShadows ? shadowRenderer : nil
        // The Gizmos slide selects its box; other slides show no selection.
        let showsGizmo = currentTitle == "Gizmos"
        showsSelectionOutline = showsGizmo
        selectedNodeID = showsGizmo ? gizmoTarget?.id : nil
        gizmoMode = showsGizmo ? .translate : nil
        // A debug view replaces every material in the view, so it is on only for its slide.
        debugIndex = 0
        sinceDebugMode = 0
        debugMode = nil
        if currentTitle != "Video Textures" {
            videoTexture?.player.pause()
        }
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
        if currentTitle == "Video Textures", let player = videoTexture?.player {
            player.seek(to: .zero)
            player.play()
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
        if Self.shadowedTitles.contains(Self.titles[current]) || Self.shadowedTitles.contains(Self.titles[next]) {
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
                cameraNode.transform = Transform3D(position: Self.eye(for: next), lookingAt: Self.target(for: next))
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
        cameraNode.transform = Transform3D(position: Self.eye(for: index), lookingAt: Self.target(for: index))
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

    // MARK: - Slide controls

    // Each slide's speed control, which scales the speed of every action on the slide.
    private static let speedControls: [String: String] = [
        "Scene Graph": "Orbit Speed", "Materials": "Material Spin", "Lights": "Light Orbit Speed", "Shadows": "Shadow Spin",
        "Opacity & Fades": "Fade Speed", "Blend Modes": "Wall Speed", "Glass": "Glass Spin", "Custom Shaders": "Shader Spin",
        "Actions": "Hop Speed", "Constraints": "Ball Speed", "Point Clouds": "Galaxy Speed", "Terrain": "Terrain Speed"
    ]
    private static let rimColorPairs: [(name: String, colors: [SIMD3<Float>])] = [
        ("Cyan & Pink", [[0.3, 0.8, 1], [1, 0.4, 0.7]]),
        ("Gold & Green", [[1, 0.75, 0.2], [0.4, 1, 0.4]]),
        ("White & Red", [[1, 1, 1], [1, 0.25, 0.2]])
    ]
    // The built-in styles; the maps demo style needs data the keynote does not load.
    private static let terrainStyles = Array(TerrainStyle.presets.prefix(4))

    // True if any of the controls changed since the last call that named them.
    private func changed(_ names: String...) -> Bool {
        var result = false
        for name in names where appliedValues[name] != self[value: name] {
            appliedValues[name] = self[value: name]
            result = true
        }
        return result
    }

    private static func descendants(of node: SceneGraph.Node) -> [SceneGraph.Node] {
        node.children.flatMap { [$0] + descendants(of: $0) }
    }

    // Applies the current slide's controls that change the scene, when they change.
    private func updateSlideControls() {
        let title = currentTitle
        // Only the slide's contents: the slide node runs its own fade.
        if let name = Self.speedControls[title], changed(name) {
            Self.descendants(of: slides[current]).forEach { $0.actionSpeed = self[value: name] }
        }
        switch title {
        case "Scene Graph":
            if changed("Orbit Paths") {
                orbitPaths.forEach { $0.isVisible = self[flag: "Orbit Paths"] }
            }
        case "Materials":
            if changed("Materials Lighting") {
                adjustLights(in: slides[current], scale: self[value: "Materials Lighting"])
            }
        case "Lights":
            if changed("Light Intensity", "Light Range") {
                for pivot in colorLightPivots {
                    adjustLights(in: pivot, scale: self[value: "Light Intensity"], range: self[value: "Light Range"])
                }
            }
            if changed("Red Light", "Green Light", "Blue Light") {
                for (pivot, name) in zip(colorLightPivots, ["Red Light", "Green Light", "Blue Light"]) {
                    pivot.isVisible = self[flag: name]
                }
            }
        case "Shadows":
            if changed("Sun Angle"), let shadowSun {
                let angle = self[value: "Sun Angle"] * .pi / 180
                shadowSun.transform = Transform3D(position: simd_quatf(angle: angle, axis: [0, 1, 0]).act([3, 6, 4]), lookingAt: .zero)
            }
            if changed("Cast Shadows") {
                shadows = self[flag: "Cast Shadows"] ? shadowRenderer : nil
            }
        case "Blend Modes":
            if changed("Alpha Opacity"), let alphaDisc, case let .mesh(mesh, materials, castsShadow, receivesShadow) = alphaDisc.content, var material = materials.first as? BlinnPhongSceneMaterial {
                material.opacity = self[value: "Alpha Opacity"]
                alphaDisc.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        case "Glass":
            if changed("Frosting", "Thickness", "Transmission") {
                for (material, roughness) in glassMaterials {
                    material.pbrMaterial.uniforms.roughnessFactor = min(roughness + self[value: "Frosting"], 1)
                    material.pbrMaterial.uniforms.thicknessFactor = self[value: "Thickness"]
                    material.pbrMaterial.uniforms.transmissionFactor = self[value: "Transmission"]
                }
            }
        case "PBR Extensions":
            if changed("Sheen", "Diffuse Transmission", "Clearcoat", "Iridescence") {
                for (material, base) in pbrExtensionMaterials {
                    material.pbrMaterial.uniforms.sheenColorFactor = self[flag: "Sheen"] ? base.sheenColorFactor : .zero
                    material.pbrMaterial.uniforms.diffuseTransmissionFactor = self[flag: "Diffuse Transmission"] ? base.diffuseTransmissionFactor : 0
                    material.pbrMaterial.uniforms.clearcoatFactor = self[flag: "Clearcoat"] ? base.clearcoatFactor : 0
                    material.pbrMaterial.uniforms.iridescenceFactor = self[flag: "Iridescence"] ? base.iridescenceFactor : 0
                }
            }
        case "Custom Shaders":
            if changed("Rim Colors") {
                let pair = Self.rimColorPairs[min(Int(self[value: "Rim Colors"]), Self.rimColorPairs.count - 1)]
                for (node, color) in zip(rimNodes, pair.colors) {
                    if case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content {
                        node.content = .mesh(mesh, materials: [ShaderMaterial.rim(color: color)], castsShadow: castsShadow, receivesShadow: receivesShadow)
                    }
                }
            }
        case "glTF & Model I/O":
            if changed("Firefly Trails") {
                for (node, system) in fireflyTrails {
                    node.particleSystems = self[flag: "Firefly Trails"] ? [system] : []
                }
            }
        case "Constraints":
            if changed("Look At") {
                for (cone, constraint) in lookAtCones {
                    cone.constraints = self[flag: "Look At"] ? [constraint] : []
                    if !self[flag: "Look At"] {
                        cone.transform.rotation = Rotation3D(simd_quatf(ix: 0, iy: 0, iz: 0, r: 1))
                    }
                }
            }
        case "Particles":
            if changed("Campfire", "Geyser", "Fireworks") {
                for (name, emitter) in slideEmitters {
                    emitter.node.particleSystems = self[flag: name] ? [emitter.system] : []
                }
            }
        case "Performance":
            if changed("Crate Grid") {
                setCrateCount(Int(self[value: "Crate Grid"].rounded()))
            }
        case "SwiftECS World":
            boids?.cohesion = self[value: "Cohesion"]
            boids?.alignment = self[value: "Alignment"]
            boids?.separation = self[value: "Separation"]
        case "Point Clouds":
            if changed("Point Size"), let galaxy, case let .mesh(mesh, materials, castsShadow, receivesShadow) = galaxy.content, var material = materials.first as? PointCloudMaterial {
                material.pointSize = self[value: "Point Size"]
                galaxy.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        case "Terrain":
            if changed("Height Exaggeration", "Terrain Style"), let terrainNode, case let .mesh(mesh, materials, castsShadow, receivesShadow) = terrainNode.content, var material = materials.first as? TerrainSceneMaterial {
                material.settings.heightExaggeration = self[value: "Height Exaggeration"]
                material.settings.style = Self.terrainStyles[min(Int(self[value: "Terrain Style"]), Self.terrainStyles.count - 1)].style
                terrainNode.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        default:
            break
        }
    }

    // Scales every light under `node` from its built intensity, and sets their range if given.
    private func adjustLights(in node: SceneGraph.Node, scale: Float, range: Float? = nil) {
        for light in [node] + Self.descendants(of: node) {
            guard case var .light(settings) = light.content else {
                continue
            }
            let base = baseLightIntensities[ObjectIdentifier(light)] ?? settings.intensity
            baseLightIntensities[ObjectIdentifier(light)] = base
            settings.intensity = base * scale
            if let range {
                settings.range = range
            }
            light.content = .light(settings)
        }
    }

    // Shows the first `size` × `size` crates of the grid, and says how many show.
    private func setCrateCount(_ size: Int) {
        let full = Self.crateGridSize
        for (index, crate) in crates.enumerated() {
            crate.isVisible = index / full < size && index % full < size
        }
        guard let crateCountLabel else {
            return
        }
        crateCountLabel.removeAllChildren()
        addTitle("\(size * size) crates, 3 draw calls", size: 0.35, y: 3, color: [0.6, 0.65, 0.75], to: crateCountLabel)
        // While building, the slide is not in `slides` yet; init tags it afterwards.
        if let index = Self.titles.firstIndex(of: "Performance"), slides.indices.contains(index) {
            Self.isolateLights(of: slides[index], index: index)
            hierarchyDidChange()
        }
    }

    private func toggleVideo() {
        guard let player = videoTexture?.player else {
            return
        }
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    private func restartVideo() {
        videoTexture?.player.seek(to: .zero)
        videoTexture?.player.play()
    }

    private func restartParticles() {
        for emitter in slideEmitters.values {
            emitter.system.restart()
        }
    }

    private func resetGizmoTarget() {
        gizmoTarget?.transform = .init(translation: [0, 0.9, 0], rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0]))
    }

    // MARK: - Slides

    // By title, so the deck can be reordered by editing `titles` (#310).
    private func build(slide: SceneGraph.Node, title: String) {
        switch title {
        case "SceneSprockets":
            // Flat (2D) until the keynote moves on; go(by:) breaks them into tumbling 3D letters.
            introTitles = Self.introTitleSpecs.map { spec in
                let title = addTitle(spec.text, size: spec.size, y: spec.y, color: spec.color, to: slide)
                title.transform.scale.z = Self.flatDepth
                return title
            }
            addLight(to: slide, at: [3, 5, 5], color: [1, 0.95, 0.9], intensity: 60)
        case "Scene Graph":
            addTitle(title, y: 4, to: slide)
            sceneGraphSlide(slide)
            addCode("""
            let orbit = sun.addChild(SceneGraph.Node(label: "Planet Orbit"))
            orbit.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 8)))
            let planet = orbit.addChild(SceneGraph.Node(shape: .sphere(radius: 0.4), material: blue))
            planet.transform.translation = [3.2, 0, 0]
            """, to: slide)
        case "Shapes":
            addTitle(title, y: 4, to: slide)
            shapesSlide(slide)
            addCode("""
            SceneGraph.Node(shape: .box(width: 1, height: 1, length: 1), material: red)
            SceneGraph.Node(shape: .torus(ringRadius: 0.5, pipeRadius: 0.18), material: pink)
            SceneGraph.Node(shape: .teapot(diameter: 2.2), material: porcelain)
            SceneGraph.Node(shape: .text("Hello", fontName: "Helvetica-Bold", fontSize: 1), material: white)
            """, to: slide)
        case "Materials":
            addTitle(title, y: 4, to: slide)
            materialsSlide(slide)
            addCode("""
            BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.9, 0.35, 0.25]),
                                    specular: .color(0.5), shininess: 44)
            PBRSceneMaterial(baseColor: [0.95, 0.75, 0.3],
                                 metallic: 1, roughness: 0.3)
            """, to: slide)
        case "Lights":
            addTitle(title, y: 4, to: slide)
            lightsSlide(slide)
            addCode("""
            var light = Light(type: .point, color: [1, 0.2, 0.2], intensity: 25)
            light.range = 14
            pivot.addChild(SceneGraph.Node(content: .light(light)))
            """, to: slide)
        case "Actions":
            addTitle(title, y: 4, to: slide)
            actionsSlide(slide)
            addCode("""
            var up = SceneGraph.Action.move(by: [0, 2, 0], duration: 0.6)
            up.timingMode = .easeInEaseOut
            let down = up.reversed()
            let spin = SceneGraph.Action.rotate(by: .pi, around: [0, 1, 0], duration: 0.6)
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
            let glass = PBRSceneMaterial(roughness: 0)
            glass.pbrMaterial.uniforms.transmissionFactor = 1
            // Blinn-Phong and PBR objects behind it are refracted alike.
            """, to: slide)
        case "Shadows":
            shadowsSlide(slide)
            addCode("""
            let sun = SceneGraph.Node(content: .light(Light(type: .directional, intensity: 1.5)))
            sun.transform.translation = [3, 6, 4]
            sun.look(at: .zero)
            SceneView(scene, renderers: renderers)
                .sceneShadows(Shadows(intensity: 0.75, softness: 2))
            """, to: slide)
        case "Custom Shaders":
            customShadersSlide(slide)
            addCode("""
            let normals = ShaderMaterial.normals()
            let rim = ShaderMaterial.rim(color: [0.3, 0.8, 1])
            ShaderMaterial(vertexShader: vertex, fragmentShader: fragment,
                           parameters: ["time": .float(t)])
            """, to: slide)
        case "Video Textures":
            videoTexturesSlide(slide)
            addCode("""
            let video = try await VideoTexture.load(contentsOf: url)
            video.player.play()
            BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0),
                                    shininess: 1, emission: .texture(video.texture))
            // Every frame: video.update()
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
        case "Point Clouds":
            pointCloudsSlide(slide)
            addTag("Add-On", below: 4, to: slide)
            addCode("""
            import SceneSprocketsAddOns

            let galaxy = PointCloud(points: stars, pointSize: 2)
            scene.root.addChild(try galaxy.makeNode(device: device))
            SceneView(scene, renderers: renderers + [PointCloudRenderer()])
            """, to: slide)
        case "Terrain":
            terrainSlide(slide)
            addTag("Add-On", below: 4, to: slide)
            addCode("""
            import SceneSprocketsTerrain

            let terrain = try Terrain(device: device, heightSource: .sanFranciscoBay())
            scene.root.addChild(terrain.makeNode())
            SceneView(scene, renderers: renderers + [TerrainRenderer()])
            """, to: slide)
        case "Voxels":
            voxelsSlide(slide)
            addTag("Add-On", below: 4, to: slide)
            addCode("""
            import SceneSprocketsVoxels

            let vox = try MagicaVoxelScene(contentsOf: url)
            let node = try vox.makeNode(voxelSize: 0.03, device: device)
            SceneView(scene, renderers: renderers + [VoxelRenderer()])
                .sceneShadows(Shadows())
            """, to: slide)
        case "Toon":
            toonSlide(slide)
            addTag("Add-On", below: 4, to: slide)
            addCode("""
            import SceneSprocketsToon

            let material = ToonMaterial(color: orange, bands: 2, outlineWidth: 3)
            let teapot = SceneGraph.Node(shape: .teapot(), material: material)
            SceneView(scene, renderers: renderers + [ToonRenderer()])
            """, to: slide)
        case "Metaballs":
            metaballsSlide(slide)
            addTag("Add-On", below: 4, to: slide)
            addCode("""
            import SceneSprocketsAddOns

            let blobs = SignedDistanceShape.smoothUnion(spheres, smoothing: 0.7)
            try node.setSignedDistanceShape(blobs, surface: .pbr(material), device: device)
            SceneView(scene, renderers: renderers + [SignedDistanceRenderer(pbr: pbr)])
                .sceneShadows(Shadows())
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
            tube.skin = SceneGraph.Skin(joints: joints, inverseBindMatrices: inverseBind)
            """, to: slide)
        case "Level of Detail":
            levelOfDetailSlide(slide)
            addCode("""
            node.levelsOfDetail = [
                SceneGraph.LevelOfDetail(mesh: medium, distance: 15),
                SceneGraph.LevelOfDetail(mesh: low, distance: 22),
            ]
            """, to: slide)
        case "Performance":
            performanceSlide(slide)
            addCode("""
            // Same mesh + material: one instanced draw per color.
            // Nodes outside the view are culled.
            grid.addChild(SceneGraph.Node(content: .mesh(box, material: crate)))
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
            SceneView(scene, renderers: renderers)
                .sceneManipulator(TransformGizmo(target: box, mode: .rotate))
                .sceneOverlay { viewport in
                    try outline.element(nodes: [box], sceneGraph: scene, viewport: viewport)
                }
            """, to: slide)
        case "Debug Views":
            debugViewsSlide(slide)
            addCode("""
            SceneView(scene, renderers: renderers)
                .sceneDebugMode(.normals)  // .uvChecker, .wireframe, ...
            """, to: slide)
        case "Post-Processing":
            postProcessingSlide(slide)
            addCode("""
            // Noir
            sceneGraph.postProcessing = SceneGraph.PostProcessing(contrast: 1.8, saturation: 0,
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
                    cube.transform.translation = randomPosition()
                }
            }
            """, to: slide)
        case "Animation Blending":
            animationBlendingSlide(slide)
            addCode("""
            let mixer = SceneGraph.AnimationMixer(clips: [bounce, sway])
            var controller = SceneGraph.AnimationController(clips: [bounce, sway])
            controller.blend([0, 1], parameter: weight)
            controller.advance(by: deltaTime)
            mixer.apply(controller.layers)
            """, to: slide)
        case "glTF & Model I/O":
            importSlide(slide)
            addCode("""
            let plant = try ModelFile.load(plantURL)     // .glb, .gltf, .usdz, .obj, ...
            let pedestal = try ModelFile.load(objURL)
            player = SceneGraph.AnimationPlayer(clip: plant.animations[0]) // fireflies with point lights
            """, to: slide)
        case "Hit Testing":
            hitTestingSlide(slide)
            addCode("""
            // Click a shape.
            SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
                .onSceneTap { hit in
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
                    SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
                        .sceneCameraControl()
                        .sceneShadows(Shadows())
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
        let holder = parent.addChild(SceneGraph.Node(label: "Title \"\(text)\"", transform: .init(translation: [0, y, 0])))
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(color * 0.4), specular: .color(0.3), shininess: 32, emission: .color(color * 0.6))
        let label = holder.addChild(SceneGraph.Node(shape: .text(text, fontName: "Helvetica-Bold", fontSize: size, extrusionDepth: size * 0.15), material: material))
        if let bounds = label.meshBounds {
            label.transform.translation.x = -(bounds.min.x + bounds.max.x) / 2
        }
        // Titles are not part of the scene: no shadows on the Shadows slide's floor.
        if case let .mesh(mesh, materials, _, receivesShadow) = label.content {
            label.content = .mesh(mesh, materials: materials, castsShadow: false, receivesShadow: receivesShadow)
        }
        return holder
    }

    // A small pill under a title at height `titleY`, for marking slides such as add-ons that are not built in.
    private func addTag(_ text: String, below titleY: Float, to slide: SceneGraph.Node) {
        let accent: SIMD3<Float> = [1, 0.62, 0.12]
        let tag = slide.addChild(SceneGraph.Node(label: "Tag \"\(text)\"", transform: .init(translation: [0, titleY - 0.75, 0.1])))
        let pill = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(accent * 0.3), specular: .color(0.2), shininess: 16, emission: .color(accent * 0.7))
        let label = tag.addChild(SceneGraph.Node(shape: .text(text.uppercased(), fontName: "Helvetica-Bold", fontSize: 0.32, extrusionDepth: 0.04), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.08, 0.05, 0.02]))))
        let bounds = label.meshBounds
        let width = (bounds.map { $0.max.x - $0.min.x } ?? 1) + 0.4
        if let bounds {
            label.transform.translation = [-(bounds.min.x + bounds.max.x) / 2, -(bounds.min.y + bounds.max.y) / 2, 0.08]
        }
        // A capsule on its side, flattened into a pill.
        tag.addChild(SceneGraph.Node(shape: .capsule(capRadius: 0.24, height: width), material: pill, transform: .init(rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]), scale: [1, 1, 0.25])))
    }

    // A spiral galaxy of colored points, turning slowly.
    private func pointCloudsSlide(_ slide: SceneGraph.Node) {
        // Seeded, so every run draws the same galaxy.
        var random = SeededRandom("galaxy")
        func gaussian() -> Float {
            // Box-Muller.
            let u = max(random.next(), .ulpOfOne)
            return sqrt(-2 * log(u)) * cos(2 * .pi * random.next())
        }
        var stars: [PointCloud.Point] = []
        stars.reserveCapacity(60_000)
        for index in 0..<60_000 {
            let arm = Float(index % 3) * 2 * .pi / 3
            let distance = pow(random.next(), 0.6) * 3.2
            let angle = arm + distance * 1.6 + gaussian() * 0.25
            let height = gaussian() * 0.12 * (1.2 - distance / 3.2)
            let position = SIMD3<Float>(cos(angle) * distance, height, sin(angle) * distance) + SIMD3(gaussian(), gaussian() * 0.3, gaussian()) * 0.08
            // Warm core, blue arms.
            let warmth = max(0, 1 - distance / 1.4)
            let color = simd_mix(SIMD3<Float>(0.35, 0.55, 1), SIMD3<Float>(1, 0.8, 0.45), SIMD3(repeating: warmth)) * random.range(0.6, 1.2)
            stars.append(PointCloud.Point(position: position, color: SIMD4(color, 1)))
        }
        guard let galaxy = try? PointCloud(points: stars, pointSize: 2).makeNode(device: demoDevice) else {
            return
        }
        let holder = slide.addChild(SceneGraph.Node(label: "Galaxy", transform: .init(translation: [0, 1.4, 0], rotation: simd_quatf(angle: 0.45, axis: [1, 0, 0]))))
        holder.addChild(galaxy)
        self.galaxy = galaxy
        galaxy.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 40)))
    }

    // The Golden Gate, 16 km of real elevation shrunk to a tabletop and turning slowly.
    private func terrainSlide(_ slide: SceneGraph.Node) {
        guard let source = try? HeightSource.sanFranciscoBay(), let terrain = try? Terrain(device: demoDevice, heightSource: source) else {
            return
        }
        var settings = TerrainSettings()
        settings.heightExaggeration = 3
        settings.style = .coastal
        let scale = 6 / terrain.worldSize
        let holder = slide.addChild(SceneGraph.Node(label: "Terrain", transform: .init(translation: [0, 1.2, 0], rotation: simd_quatf(angle: 0.5, axis: [1, 0, 0]), scale: SIMD3(repeating: scale))))
        let node = holder.addChild(terrain.makeNode(settings: settings))
        terrainNode = node
        node.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 60)))
        let sun = slide.addChild(SceneGraph.Node(label: "Sun", transform: .init(translation: [3, 4, 2]), content: .light(Light(type: .directional, color: [1, 0.95, 0.85], intensity: 3))))
        sun.look(at: .zero)
    }

    // A MagicaVoxel monument, turning slowly.
    private func voxelsSlide(_ slide: SceneGraph.Node) {
        guard let url = Bundle.module.url(forResource: "Monument", withExtension: "vox", subdirectory: "DemoAssets"),
              let data = try? Data(contentsOf: url),
              let grid = try? VoxelGrid.magicaVoxelModels(data: data).max(by: { $0.filledCount < $1.filledCount }) else {
            return
        }
        let height: Float = 3.3
        let voxelSize = height / Float(grid.size.y)
        // Tilted toward the camera so the turning model shows its roofs.
        let tilt = slide.addChild(SceneGraph.Node(label: "Monument Tilt", transform: .init(translation: [0, 1.2, 0], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0]))))
        let holder = tilt.addChild(SceneGraph.Node(label: "Monument"))
        try? holder.setVoxels(grid, voxelSize: voxelSize, device: demoDevice)
        monument = holder
        holder.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 40)))
        // A floor under the turning model catches its shadow; the sun casts it, the fill light does not.
        tilt.addChild(SceneGraph.Node(label: "Floor", shape: .cylinder(radius: 1.9, height: 0.08), material: BlinnPhongSceneMaterial.plastic([0.25, 0.25, 0.28], shininess: 8), transform: .init(translation: [0, -height / 2 - 0.04, 0])))
        tilt.addChild(SceneGraph.Node(label: "Sun", transform: .init(position: [-4, 3, 1.5], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.85], intensity: 1.5))))
        addLight(to: slide, at: [3, 2, 3], color: [0.6, 0.7, 1], intensity: 8, castsShadow: false)
    }

    // A teapot between a sphere, a torus and a capsule on a toon floor, turning slowly.
    private func toonSlide(_ slide: SceneGraph.Node) {
        let stage = slide.addChild(SceneGraph.Node(label: "Toon Stage", transform: .init(translation: [0, 0.5, -0.8], rotation: simd_quatf(angle: 0.3, axis: [1, 0, 0]), scale: [1.6, 1.6, 1.6])))
        let floor = ToonMaterial(color: [0.35, 0.55, 0.3], highlightSize: 0, outlineWidth: 0)
        stage.addChild(SceneGraph.Node(label: "Floor", shape: .cylinder(radius: 2.1, height: 0.08), material: floor, transform: .init(translation: [0, -0.04, 0])))
        let turntable = stage.addChild(SceneGraph.Node(label: "Turntable"))
        turntable.run(.repeatForever(.rotate(by: 2 * .pi, around: [0, 1, 0], duration: 30)))
        let shapes: [(SceneGraph.Shape, SIMD3<Float>, ToonMaterial)] = [
            (.teapot(diameter: 1.6), [0, 0.6, 0], ToonMaterial(color: [0.95, 0.45, 0.15])),
            (.sphere(radius: 0.45), [-1.4, 0.45, 0.4], ToonMaterial(color: [0.85, 0.2, 0.3], rimColor: [0.35, 0.35, 0.45])),
            (.torus(ringRadius: 0.4, pipeRadius: 0.16), [1.4, 0.56, 0.4], ToonMaterial(color: [0.95, 0.8, 0.2])),
            (.capsule(capRadius: 0.25, height: 1.2), [0, 0.6, -1.3], ToonMaterial(color: [0.3, 0.5, 0.95]))
        ]
        toonShapes = shapes.map { shape, position, material in
            (turntable.addChild(SceneGraph.Node(shape: shape, material: material, transform: .init(translation: position))), material)
        }
        stage.addChild(SceneGraph.Node(label: "Sun", transform: .init(position: [-3, 5, 3], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 0.97, 0.9], intensity: 1.3))))
    }

    private func updateToonMaterials() {
        let bands = max(Int((values["Bands"] ?? 2).rounded()), 1)
        let outlineWidth = values["Outline Width"] ?? 3
        for (node, base) in toonShapes {
            guard case let .mesh(mesh, materials, castsShadow, receivesShadow) = node.content, let current = materials.first as? ToonMaterial else {
                continue
            }
            guard current.bands != bands || current.outlineWidth != outlineWidth else {
                continue
            }
            var material = base
            material.bands = bands
            material.outlineWidth = outlineWidth
            node.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
        }
    }

    private static let lightingModels = ["PBR", "Blinn-Phong"]
    private let voxelPBRMaterial = PBRSceneMaterial(roughness: 0.75)

    // Swaps the monument's surface when the Voxel Lighting control changes; the voxel texture is kept.
    private func updateVoxelLighting() {
        guard let monument, case let .mesh(_, materials, _, _) = monument.content, var material = materials.first as? VoxelMaterial else {
            return
        }
        let usesPBR = (values["Voxel Lighting"] ?? 1) == 0
        let isPBR = if case .pbr = material.surface { true } else { false }
        guard usesPBR != isPBR else {
            return
        }
        material.surface = usesPBR ? .pbr(voxelPBRMaterial) : .blinnPhong(BlinnPhongSceneMaterial(color: [1, 1, 1]))
        monument.setVoxels(material, device: demoDevice)
    }

    // Blobs orbiting a pillar; the shape is set in updateMetaballs.
    private func metaballsSlide(_ slide: SceneGraph.Node) {
        // Tilted toward the camera so the blobs' shadows on the floor show.
        let stage = slide.addChild(SceneGraph.Node(label: "Metaballs Stage", transform: .init(translation: [0, 0.4, 0], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0]))))
        stage.addChild(SceneGraph.Node(label: "Pillar", shape: .cylinder(radius: 0.12, height: 2.6), material: BlinnPhongSceneMaterial.plastic([0.9, 0.5, 0.3]), transform: .init(translation: [0, 0.3, 0])))
        stage.addChild(SceneGraph.Node(label: "Floor", shape: .cylinder(radius: 1.8, height: 0.08), material: BlinnPhongSceneMaterial.plastic([0.25, 0.25, 0.28], shininess: 8), transform: .init(translation: [0, -1.04, 0])))
        metaballs = stage.addChild(SceneGraph.Node(label: "Metaballs"))
        stage.addChild(SceneGraph.Node(label: "Sun", transform: .init(position: [2, 6, 3], lookingAt: [0, 0, 0]), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 1.2))))
        addLight(to: slide, at: [-3, 1, 3], color: [0.5, 0.6, 1], intensity: 6, castsShadow: false)
        updateMetaballs(time: 0)
    }

    // Made once: the shape is replaced every frame.
    private let metaballMaterial = PBRSceneMaterial(baseColor: [0.3, 0.55, 0.95], metallic: 0.2, roughness: 0.25)

    private func updateMetaballs(time: Float) {
        guard let metaballs else {
            return
        }
        // The slide's controls have no values until the slide is first shown.
        let count = max(Int((values["Metaball Count"] ?? 7).rounded()), 1)
        let radius = values["Metaball Size"] ?? 0.38
        let smoothing = values["Smoothing"] ?? 0.7
        let spheres = (0..<count).map { index -> SignedDistanceShape in
            let phase = Float(index) / Float(count) * 2 * .pi
            let position = SIMD3<Float>(
                cos(phase + time * 0.7) * 1.1,
                1.6 + sin(phase * 2 + time * 1.3) * 0.6,
                sin(phase + time * 0.9) * 1.1
            )
            return .sphere(radius: radius + 0.1 * sin(phase * 3 + time), transform: .init(translation: position))
        }
        try? metaballs.setSignedDistanceShape(.smoothUnion(spheres, smoothing: smoothing), surface: (values["Metaball Lighting"] ?? 0) == 0 ? .pbr(metaballMaterial) : .blinnPhong(.plastic([0.3, 0.55, 0.95], shininess: 48)), device: demoDevice)
    }

    // A code panel below the slide's live content, tilted a little toward the camera.
    private func addCode(_ code: String, to slide: SceneGraph.Node) {
        guard let panel = CodePanel.node(code: code, device: demoDevice) else {
            return
        }
        panel.transform = .init(translation: [0, -1.6, 1.5], rotation: simd_quatf(angle: -0.15, axis: [1, 0, 0]))
        slide.addChild(panel)
    }

    // Lights reach only their own slide.
    @discardableResult
    private func addLight(to parent: SceneGraph.Node, at position: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float, castsShadow: Bool = true) -> SceneGraph.Node {
        var light = Light(type: .point, color: color, intensity: intensity, castsShadow: castsShadow)
        light.range = 14
        return parent.addChild(SceneGraph.Node(label: "Light", transform: .init(translation: position), content: .light(light)))
    }

    private func sceneGraphSlide(_ slide: SceneGraph.Node) {
        // A sun with planets, a moon and a ring: each orbit is a parent node that turns, and children ride along. The
        // system is tilted toward the camera so the orbits read as ellipses (#343).
        let system = slide.addChild(SceneGraph.Node(label: "Solar System", transform: .init(translation: [0, 1.9, 0], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0]))))
        var sunlight = Light(type: .point, color: [1, 0.9, 0.75], intensity: 45)
        sunlight.range = 30
        system.addChild(SceneGraph.Node(label: "Sunlight", content: .light(sunlight)))
        // A dim fill from the camera side, so the planets' night sides are not pure black.
        addLight(to: slide, at: [0, 4, 10], color: [0.4, 0.5, 0.8], intensity: 6)
        let sun = system.addChild(SceneGraph.Node(label: "Sun", shape: .sphere(radius: 0.75), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 0.7, 0.25]))))
        func pbr(_ color: SIMD3<Float>, metallic: Float = 0, roughness: Float) -> any SceneMaterial {
            PBRSceneMaterial(baseColor: color, metallic: metallic, roughness: roughness)
        }
        let pathMaterial = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.25, 0.27, 0.35]), renderState: MaterialRenderState(fillMode: .lines))
        // (radius, size, period, color, roughness)
        let planets: [(Float, Float, Float, SIMD3<Float>, Float)] = [(1.6, 0.18, 5, [0.75, 0.45, 0.3], 0.9), (3.2, 0.4, 8, [0.3, 0.55, 1], 0.35), (4.3, 0.3, 13, [0.9, 0.78, 0.55], 0.6)]
        for (index, (radius, size, period, color, roughness)) in planets.enumerated() {
            orbitPaths.append(sun.addChild(SceneGraph.Node(label: "Orbit Path", shape: .torus(ringRadius: radius, pipeRadius: 0.004), material: pathMaterial)))
            // Parented to the sun, as the code panel shows; the sun does not turn, so only the orbit spins the planet.
            let orbit = sun.addChild(SceneGraph.Node(label: "Planet Orbit", transform: .init(rotation: simd_quatf(angle: Float(index) * 2.1, axis: [0, 1, 0]))))
            orbit.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: period)))
            let planet = orbit.addChild(SceneGraph.Node(label: "Planet", shape: .sphere(radius: size), material: pbr(color, roughness: roughness), transform: .init(translation: [radius, 0, 0])))
            planet.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 3)))
            switch index {
            case 1:
                let moonOrbit = planet.addChild(SceneGraph.Node(label: "Moon Orbit"))
                moonOrbit.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 2)))
                moonOrbit.addChild(SceneGraph.Node(label: "Moon", shape: .sphere(radius: 0.1), material: pbr([0.8, 0.8, 0.82], roughness: 0.8), transform: .init(translation: [0.7, 0, 0])))
            case 2:
                // The ring is a child of the planet: it tilts and spins with it.
                let ring = planet.addChild(SceneGraph.Node(label: "Ring", shape: .torus(ringRadius: 0.58, pipeRadius: 0.06), material: pbr([0.85, 0.75, 0.6], metallic: 0.3, roughness: 0.4), transform: .init(rotation: simd_quatf(angle: 0.35, axis: [0, 0, 1]))))
                ring.transform.scale = [1, 0.15, 1]
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
            let node = slide.addChild(SceneGraph.Node(shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), transform: .init(translation: [Float(index) * 1.6 - 4.8, 1.2, 0])))
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
            var materials: [any SceneMaterial] = [BlinnPhongSceneMaterial.plastic(paints[column], shininess: 4 + smoothness * 120)]
            materials.append(PBRSceneMaterial(baseColor: metals[column], metallic: 1, roughness: 0.75 - smoothness * 0.7))
            let plastic = PBRSceneMaterial(baseColor: plastics[column], metallic: 0, roughness: 0.8 - smoothness * 0.7)
            // The glossiest plastics get a clear coat, like car paint.
            if column >= 4 {
                plastic.pbrMaterial.uniforms.clearcoatFactor = 1
                plastic.pbrMaterial.uniforms.clearcoatRoughnessFactor = 0.05
            }
            materials.append(plastic)
            for (row, material) in materials.enumerated() {
                let node = slide.addChild(SceneGraph.Node(shape: shapes[(column + row * 2) % shapes.count], material: material, transform: .init(translation: [x, 2.7 - Float(row) * 1.3, 0])))
                node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 8 + Float(column + row))))
            }
        }
    }

    private func lightsSlide(_ slide: SceneGraph.Node) {
        slide.addChild(SceneGraph.Node(shape: .box(width: 10, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.8, 0.8, 0.85], shininess: 16), transform: .init(translation: [0, -0.05, 0])))
        for index in 0..<5 {
            slide.addChild(SceneGraph.Node(shape: .sphere(radius: 0.45), material: BlinnPhongSceneMaterial.plastic([0.9, 0.9, 0.9], shininess: 64), transform: .init(translation: [Float(index) * 1.8 - 3.6, 0.45, 0])))
        }
        let colors: [SIMD3<Float>] = [[1, 0.2, 0.2], [0.2, 1, 0.3], [0.3, 0.4, 1]]
        for (index, color) in colors.enumerated() {
            let pivot = slide.addChild(SceneGraph.Node(label: "Light Orbit", transform: .init(rotation: simd_quatf(angle: Float(index) * 2 * .pi / 3, axis: [0, 1, 0]))))
            pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6)))
            colorLightPivots.append(pivot)
            addLight(to: pivot, at: [3, 1.5, 0], color: color, intensity: 25)
            pivot.addChild(SceneGraph.Node(shape: .sphere(radius: 0.1), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color)), transform: .init(translation: [3, 1.5, 0])))
        }
    }

    private func actionsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        hopCubes = (0..<4).map { _ in
            slide.addChild(SceneGraph.Node(shape: .box(width: 0.8, height: 0.8, length: 0.8), material: BlinnPhongSceneMaterial.plastic([0.4, 0.7, 1], shininess: 32)))
        }
        startHops()
    }

    // The same hop with each timing mode, started one after another.
    private func startHops() {
        let modes: [SceneGraph.Action.TimingMode] = [.linear, .easeIn, .easeOut, .easeInEaseOut]
        for (index, (cube, mode)) in zip(hopCubes, modes).enumerated() {
            cube.removeAllActions()
            cube.transform = .init(translation: [Float(index) * 2 - 3, 0.4, 0])
            var up = SceneGraph.Action.move(by: [0, 2, 0], duration: 0.6)
            up.timingMode = mode
            var down = SceneGraph.Action.move(by: [0, -2, 0], duration: 0.6)
            down.timingMode = mode
            cube.run(.sequence([.wait(duration: Float(index) * 0.25), .repeatForever(.sequence([.group([up, .rotate(by: .pi, around: [0, 1, 0], duration: 0.6)]), down, .wait(duration: 0.8)]))]))
        }
    }

    private func constraintsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let pivot = slide.addChild(SceneGraph.Node(label: "Ball Orbit", transform: .init(translation: [0, 1.5, 0])))
        pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6)))
        let ball = pivot.addChild(SceneGraph.Node(shape: .sphere(radius: 0.35), material: BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([1, 0.85, 0.2])), transform: .init(translation: [3, 0, 0])))
        // Cones that always point their tips (+Y) at the ball.
        for index in 0..<5 {
            let cone = slide.addChild(SceneGraph.Node(shape: .cone(bottomRadius: 0.3, height: 0.9), material: BlinnPhongSceneMaterial.plastic([0.5, 0.9, 0.9], shininess: 32), transform: .init(translation: [Float(index) * 2 - 4, 0, 2])))
            let constraint = SceneGraph.Constraint.lookAt(target: ball, localFront: [0, 1, 0])
            cone.constraints = [constraint]
            lookAtCones.append((cone, constraint))
        }
    }

    private func fadesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        // Each sphere fades out and back in, a little after the one before it. Blinn-Phong and PBR both fade.
        for index in 0..<6 {
            let material: any SceneMaterial = index.isMultiple(of: 2)
                ? BlinnPhongSceneMaterial.plastic([0.95, 0.4, 0.6], shininess: 48)
                : PBRSceneMaterial(baseColor: [0.4, 0.6, 1], metallic: 0, roughness: 0.3)
            fadeSpheres.append(slide.addChild(SceneGraph.Node(shape: .sphere(radius: 0.6), material: material, transform: .init(translation: [Float(index) * 1.6 - 4, 1.2, 0]))))
        }
        startFades()
    }

    private func startFades() {
        for (index, sphere) in fadeSpheres.enumerated() {
            sphere.removeAllActions()
            sphere.opacity = 1
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
        let wall = slide.addChild(SceneGraph.Node(label: "Stripes", transform: .init(translation: [0, 1.6, -0.6])))
        for (index, color) in stripes.enumerated() {
            wall.addChild(SceneGraph.Node(shape: .plane(width: 1.35, height: 2.8), material: glow(color), transform: .init(translation: [Float(index) * 1.35 - 4.725, 0, 0])))
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
            let disc = slide.addChild(SceneGraph.Node(label: "Blend \(name)", shape: .cylinder(radius: 0.6, height: 0.02), material: material, transform: .init(translation: [x, 1.6, 0], rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))))
            if mode == .alpha {
                alphaDisc = disc
            }
            let label = addTitle(".\(name)", size: 0.3, y: 0, color: [0.85, 0.85, 0.9], to: slide)
            label.transform.translation.x = x
        }
    }

    // PBR glass in front of turning Blinn-Phong and PBR shapes, which show through it refracted (#123, #129).
    private func glassSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 5, 6], intensity: 80)
        // A checkered Blinn-Phong wall, so the glass always has something to bend.
        let light = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.55, 0.57, 0.62]))
        let dark = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.12, 0.13, 0.16]))
        // One mesh for every tile, so Blinn-Phong draws them as two instanced batches.
        let tile = SceneGraph.Shape.box(width: 0.6, height: 0.6, length: 0.05).metalMesh()
        for row in 0..<6 {
            for column in 0..<14 {
                let material = (row + column).isMultiple(of: 2) ? light : dark
                slide.addChild(SceneGraph.Node(transform: .init(translation: [Float(column) * 0.6 - 3.9, Float(row) * 0.6 + 0.1, -4.5]), content: .mesh(tile, material: material)))
            }
        }
        let colors: [SIMD3<Float>] = [[0.95, 0.3, 0.25], [0.95, 0.8, 0.2], [0.3, 0.8, 0.4], [0.25, 0.5, 1], [0.8, 0.35, 0.9]]
        for (index, color) in colors.enumerated() {
            let x = Float(index) * 1.6 - 3.2
            let material: any SceneMaterial = index.isMultiple(of: 2)
                ? BlinnPhongSceneMaterial.plastic(color, shininess: 32)
                : PBRSceneMaterial(baseColor: color, metallic: 0, roughness: 0.4)
            let bar = slide.addChild(SceneGraph.Node(shape: .box(width: 0.5, height: 3, length: 0.5), material: material, transform: .init(translation: [x, 1.6, -2.5])))
            bar.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 6 + Float(index))))
        }
        let shapes: [(SceneGraph.Shape, Float, Float)] = [
            (.sphere(radius: 0.9), -2.6, 0),
            (.box(width: 1.6, height: 1.6, length: 0.4), 0, 0.15),
            (.torus(ringRadius: 0.75, pipeRadius: 0.3), 2.6, 0.05)
        ]
        for (shape, x, roughness) in shapes {
            let glass = PBRSceneMaterial(baseColor: [1, 1, 1], metallic: 0, roughness: roughness)
            glass.pbrMaterial.uniforms.transmissionFactor = 1
            glass.pbrMaterial.uniforms.thicknessFactor = 0.6
            glassMaterials.append((glass, roughness))
            let node = slide.addChild(SceneGraph.Node(shape: shape, material: glass, transform: .init(translation: [x, 1.6, 1])))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0]), duration: 10)))
        }
    }

    private func shadowsSlide(_ slide: SceneGraph.Node) {
        // Tilted toward the camera so the shadows on the floor show.
        let stage = slide.addChild(SceneGraph.Node(label: "Stage", transform: .init(translation: [0, 0.8, -2.5], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0]))))
        let slide = stage
        shadowSun = slide.addChild(SceneGraph.Node(label: "Sun", transform: Transform3D(position: [3, 6, 4], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 1.5))))
        slide.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.7, 0.7, 0.75], shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        let torus = slide.addChild(SceneGraph.Node(shape: .torus(ringRadius: 0.8, pipeRadius: 0.25), material: BlinnPhongSceneMaterial.plastic([0.95, 0.75, 0.3], shininess: 48), transform: .init(translation: [0, 1.8, 0])))
        torus.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.5, 0]), duration: 6)))
        slide.addChild(SceneGraph.Node(shape: .box(width: 1, height: 1, length: 1), material: BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.3]), transform: .init(translation: [-3, 0.5, 0])))
        slide.addChild(SceneGraph.Node(shape: .cylinder(radius: 0.35, height: 2), material: BlinnPhongSceneMaterial.plastic([0.4, 0.8, 0.5]), transform: .init(translation: [3, 1, 0])))
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
                let holder = slide.addChild(SceneGraph.Node(label: "Letter \(character)"))
                let letter = holder.addChild(SceneGraph.Node(shape: .text(String(character), fontName: "Helvetica-Bold", fontSize: spec.size, extrusionDepth: spec.size * 0.15), material: material))
                guard let bounds = letter.meshBounds else {
                    continue
                }
                let center = (bounds.min + bounds.max) / 2
                // The holder sits at the letter's center, so the letter spins about its middle.
                letter.transform.translation = -center
                holder.transform.translation = [advance(prefix) - width / 2 + center.x, spec.y + center.y, center.z]
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
            letter.node.transform.translation += letter.velocity * deltaTime
            letter.node.transform.rotation = Rotation3D(simd_quatf(angle: letter.spinRate * deltaTime, axis: letter.spinAxis) * letter.node.transform.rotation.quaternion)
        }
        // Out of frame: no need to keep them.
        let fallen = tumblingLetters.filter { $0.node.transform.translation.y < -10 }
        if !fallen.isEmpty {
            fallen.forEach { $0.node.removeFromParent() }
            tumblingLetters.removeAll { $0.node.transform.translation.y < -10 }
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
        let finale = slide.addChild(SceneGraph.Node(label: "Finale"))
        finale.isVisible = false
        self.finale = finale
        let colors: [SIMD3<Float>] = [[1, 0.3, 0.4], [0.3, 1, 0.5], [0.4, 0.5, 1]]
        for (index, color) in colors.enumerated() {
            let pivot = finale.addChild(SceneGraph.Node(label: "Light Orbit", transform: .init(translation: [0, 1.5, 0], rotation: simd_quatf(angle: Float(index) * 2 * .pi / 3, axis: [0, 1, 0]))))
            pivot.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 3 + Float(index))))
            addLight(to: pivot, at: [4, 1, 2], color: color, intensity: 60)
        }
        // A tilted ring of candy-colored spheres around the title. Glass over a black background reads as black.
        let ring = finale.addChild(SceneGraph.Node(label: "Candy Ring", transform: .init(translation: [0, 1.5, 0], rotation: simd_quatf(angle: 0.35, axis: [1, 0, 0]))))
        ring.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)))
        for index in 0..<6 {
            let candy = PBRSceneMaterial(baseColor: colors[index % 3], metallic: 0.8, roughness: 0.2)
            candy.pbrMaterial.uniforms.clearcoatFactor = 1
            candy.pbrMaterial.uniforms.clearcoatRoughnessFactor = 0.03
            let angle = Float(index) * 2 * .pi / 6
            ring.addChild(SceneGraph.Node(shape: .sphere(radius: 0.45), material: candy, transform: .init(translation: [cos(angle) * 4.6, 0, sin(angle) * 2])))
        }
        // Big glass shapes and polished metal spinning on either side.
        let props: [(SceneGraph.Shape, SIMD3<Float>, Bool)] = [
            (.torus(ringRadius: 0.7, pipeRadius: 0.28), [-5.2, 3.2, -1.5], true),
            (.teapot(diameter: 1.8), [5.2, 3.2, -1.5], true),
            (.box(width: 0.9, height: 0.9, length: 0.9), [-5.4, -0.4, -1], false),
            (.capsule(capRadius: 0.35, height: 1.2), [5.4, -0.4, -1], false)
        ]
        for (index, (shape, position, isGlass)) in props.enumerated() {
            let material = PBRSceneMaterial(baseColor: isGlass ? [1, 1, 1] : [1, 0.8, 0.4], metallic: isGlass ? 0 : 1, roughness: isGlass ? 0 : 0.15)
            if isGlass {
                material.pbrMaterial.uniforms.transmissionFactor = 1
                material.pbrMaterial.uniforms.thicknessFactor = 0.6
            }
            let node = finale.addChild(SceneGraph.Node(shape: shape, material: material, transform: .init(translation: position)))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.4, 1, 0.3]), duration: 3 + Float(index))))
        }
        let emitters: [(SIMD3<Float>, ParticleSystem)] = [
            ([-3.5, 0, -4], .fireworks), ([3.5, 0, -4], .fireworks), ([0, 5, 0], .confetti),
            ([0, -0.4, -1.5], .ringOfFire), ([0, 1.5, -8], .galaxy)
        ]
        finaleEmitters = emitters.map { position, system in
            (finale.addChild(SceneGraph.Node(label: "Finale Emitter", transform: .init(translation: position))), system)
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
        finaleTitle?.transform.scale = [1, 1, 1]
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
        slide.addChild(SceneGraph.Node(label: "Moon", transform: Transform3D(position: [2, 5, 6], lookingAt: .zero), content: .light(Light(type: .directional, color: [0.8, 0.85, 1], intensity: 1.2))))
        // Two rows of pillars running away from the camera, fading into the fog.
        for row in 0..<8 {
            for side in [-1, 1] as [Float] {
                let pillar = slide.addChild(SceneGraph.Node(shape: .cylinder(radius: 0.3, height: 3), material: BlinnPhongSceneMaterial.plastic([0.85, 0.8, 0.7], shininess: 16), transform: .init(translation: [side * 2.5, 1.5, -Float(row) * 4])))
                pillar.label = "Pillar"
            }
        }
        slide.addChild(SceneGraph.Node(label: "Ground", shape: .box(width: 8, height: 0.1, length: 36), material: BlinnPhongSceneMaterial.plastic([0.4, 0.4, 0.45], shininess: 4), transform: .init(translation: [0, -0.05, -14])))
    }

    private func implicitAnimationSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        let colors: [SIMD3<Float>] = [[1, 0.4, 0.3], [1, 0.8, 0.3], [0.4, 0.9, 0.4], [0.3, 0.8, 1], [0.6, 0.5, 1], [1, 0.5, 0.8]]
        shuffleCubes = colors.enumerated().map { index, color in
            slide.addChild(SceneGraph.Node(shape: .box(width: 0.8, height: 0.8, length: 0.8), material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), transform: .init(translation: [Float(index) * 1.4 - 3.5, 1.2, 0])))
        }
    }

    // Plain property changes inside a transaction animate instead of jumping.
    private func shuffle() {
        sinceShuffle = 0
        SceneGraph.Transaction.animate(duration: self[value: "Shuffle Duration"], timingMode: .easeInEaseOut) {
            for cube in shuffleCubes {
                cube.transform.translation = [Float.random(in: -4...4), Float.random(in: 0.4...3), Float.random(in: -1...1)]
                cube.transform.rotation = Rotation3D(simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: simd_normalize(SIMD3<Float>.random(in: -1...1) + [0, 0.01, 0])))
            }
        }
    }

    private func animationBlendingSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 70)
        slide.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 8, height: 0.1, length: 4), material: BlinnPhongSceneMaterial.plastic([0.6, 0.6, 0.65], shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        let body = slide.addChild(SceneGraph.Node(label: "Body", shape: .box(width: 1, height: 1, length: 1), material: BlinnPhongSceneMaterial.plastic([0.9, 0.5, 0.2]), transform: .init(translation: [0, 0.5, 0])))
        let head = body.addChild(SceneGraph.Node(label: "Head", shape: .sphere(radius: 0.35), material: BlinnPhongSceneMaterial.plastic([0.95, 0.85, 0.7]), transform: .init(translation: [0, 0.9, 0])))
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
        slide.addChild(SceneGraph.Node(label: "Sun", transform: Transform3D(position: [2, 4, 3], lookingAt: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 2))))
        addLight(to: slide, at: [-3, 3, 5], color: [0.6, 0.7, 1], intensity: 30)
        // The plant is about 0.6 units tall and the pedestal 1 wide (its top at y = 0); the holder scales both up.
        let holder = slide.addChild(SceneGraph.Node(label: "Imported", transform: .init(translation: [0, 0.3, -1], scale: [1.4, 1.4, 1.4])))
        do {
            if let url = Bundle.module.url(forResource: "DiffuseTransmissionPlant", withExtension: "glb", subdirectory: "DemoAssets") {
                let plant = try ModelFile.load(url)
                let plantHolder = holder.addChild(SceneGraph.Node(label: "Plant", transform: .init(scale: [3, 3, 3])))
                for child in plant.node.children {
                    plantHolder.addChild(child)
                }
                // The asset has chase cameras behind its fireflies; the keynote flies its own camera.
                removeCameras(under: plantHolder)
                // The fireflies are tiny with very dim lights; give them a glow, a light and a trail so they read on stage.
                for firefly in descendants(of: plantHolder).filter({ ["firefly1", "firefly2"].contains($0.label) }) {
                    let glow = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.8, 1, 0.45]))
                    firefly.addChild(SceneGraph.Node(label: "Glow", shape: .sphere(radius: 0.025), material: glow))
                    var light = Light(type: .point, color: [0.8, 1, 0.5], intensity: 6)
                    light.range = 3
                    firefly.addChild(SceneGraph.Node(label: "Glow Light", content: .light(light)))
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
                    let system = SceneParticleSystem(trail, seed: 3)
                    firefly.particleSystems = [system]
                    fireflyTrails.append((firefly, system))
                }
                importedPlayer = plant.animations.first.map { SceneGraph.AnimationPlayer(clip: $0) }
            }
            if let url = Bundle.module.url(forResource: "Pedestal", withExtension: "obj", subdirectory: "DemoAssets") {
                let pedestal = try ModelFile.load(url)
                pedestal.node.label = "Pedestal"
                holder.addChild(pedestal.node)
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
            let node = slide.addChild(SceneGraph.Node(shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), transform: .init(translation: [Float(index) * 2.2 - 3.3, 1.2, 0])))
            hitTargets.insert(ObjectIdentifier(node))
        }
        addTitle("Click a shape", size: 0.35, y: 2.8, color: [0.6, 0.65, 0.75], to: slide)
    }

    // DiceDemo's wooden tray and dice, tilted toward the camera so the dice show from the slides' usual eye height.
    private static let trayTilt = simd_quatf(angle: 0.5, axis: [1, 0, 0])

    private func physicsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 80)
        let tray = slide.addChild(SceneGraph.Node(label: "Dice Tray", transform: .init(translation: [0, 0.8, 0], rotation: Self.trayTilt)))
        DiceDemo.buildTray(in: tray)
        physicsDice = tray.addChild(SceneGraph.Node(label: "Dice"))
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
            die.transform = .init(translation: position, rotation: rotation, scale: SIMD3(repeating: DiceDemo.dieScale))
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
        let materials: [any SceneMaterial] = [
            ShaderMaterial.normals(),
            ShaderMaterial.rim(color: [0.3, 0.8, 1]),
            ShaderMaterial.rim(color: [1, 0.4, 0.7])
        ].compactMap { $0 }
        let shapes: [SceneGraph.Shape] = [.torus(ringRadius: 0.7, pipeRadius: 0.28), .sphere(radius: 0.9), .capsule(capRadius: 0.5, height: 1.8)]
        for (index, (shape, material)) in zip(shapes, materials).enumerated() {
            let node = slide.addChild(SceneGraph.Node(shape: shape, material: material, transform: .init(translation: [Float(index) * 3 - 3, 1.4, 0])))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.4, 1, 0.2]), duration: 7 + Float(index))))
            if index > 0 {
                rimNodes.append(node)
            }
        }
    }

    // A screen and a spinning cube, both showing the same video as emission.
    private func videoTexturesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 40)
        guard let url = Bundle.module.url(forResource: "AppleEventVideo", withExtension: "mp4", subdirectory: "DemoAssets") else {
            return
        }
        let player = AVPlayer(url: url)
        player.isMuted = true
        player.actionAtItemEnd = .none
        videoLoopObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: player.currentItem, queue: .main) { _ in
            player.seek(to: .zero)
        }
        // The asset is 512 × 512.
        guard let video = try? VideoTexture(player: player, width: 512, height: 512) else {
            return
        }
        videoTexture = video
        let material = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0.2), shininess: 32, emission: .texture(video.texture))
        slide.addChild(SceneGraph.Node(shape: .box(width: 3.4, height: 3.4, length: 0.1), material: material, transform: .init(translation: [-1.8, 1.5, 0])))
        let cube = slide.addChild(SceneGraph.Node(shape: .box(width: 1.8, height: 1.8, length: 1.8), material: material, transform: .init(translation: [2.6, 1.5, 0])))
        cube.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 9)))
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
        // The pearl is shared by two pieces; its controls should change it once.
        for material in [pieces[0].1, pieces[1].1, pieces[2].1] {
            pbrExtensionMaterials.append((material, material.pbrMaterial.uniforms))
        }
        for (mesh, material, position) in pieces {
            let node = slide.addChild(SceneGraph.Node(label: material.pbrMaterial.name, transform: .init(translation: position), content: .mesh(mesh, material: material)))
            let axis = simd_normalize(SIMD3<Float>(.random(in: -1...1, using: &generator), .random(in: -1...1, using: &generator), .random(in: -1...1, using: &generator)))
            pbrExtensionPieces.append((node, axis, .random(in: 0.2...0.5, using: &generator)))
        }
    }

    // The animated glTF Fox with particles born on its skinned surface: flames, then sparks, in turn.
    private func meshEmittersSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [-3, 5, 4], color: [0.5, 0.6, 1], intensity: 12)
        slide.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 10, height: 0.1, length: 4), material: BlinnPhongSceneMaterial.plastic([0.12, 0.12, 0.14], shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        guard let fox = try? BurningFox(scale: 2) else {
            return
        }
        // Side on to the camera.
        fox.node.transform = .init(rotation: simd_quatf(angle: .pi / 2, axis: [0, 1, 0]))
        slide.addChild(fox.node)
        burningFox = fox
    }

    // MetalSprocketsParticles sample presets: a campfire on real logs, a geyser, and fireworks over the slide. Presets
    // bring their own colliders (the ground plane, the logs), which follow the node they are on.
    private func particlesSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [-4, 6, 6], color: [0.45, 0.55, 0.9], intensity: 25)
        slide.addChild(SceneGraph.Node(label: "Ground", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.16, 0.15, 0.15], shininess: 6), transform: .init(translation: [0, -0.05, -1])))

        let campfire = slide.addChild(SceneGraph.Node(label: "Campfire", transform: .init(translation: [-2.6, 0, 0.8])))
        campfire.particleSystems = [SceneParticleSystem(.campfire, seed: 1)]
        slideEmitters["Campfire"] = (campfire, campfire.particleSystems[0])
        // Logs where the preset's capsule colliders are, so embers land on wood.
        let bark = BlinnPhongSceneMaterial.plastic([0.3, 0.18, 0.1], shininess: 4)
        for (start, end) in [(SIMD3<Float>(-0.5, 0.08, -0.2), SIMD3<Float>(0.5, 0.08, 0.2)), ([-0.4, 0.08, 0.35], [0.4, 0.08, -0.35])] {
            let axis = end - start
            campfire.addChild(SceneGraph.Node(label: "Log", shape: .capsule(capRadius: 0.08, height: simd_length(axis) + 0.16), material: bark, transform: .init(translation: (start + end) / 2, rotation: simd_quatf(from: [0, 1, 0], to: simd_normalize(axis)))))
        }
        var firelight = Light(type: .point, color: [1, 0.55, 0.2], intensity: 6)
        firelight.range = 6
        campfireLight = campfire.addChild(SceneGraph.Node(label: "Firelight", transform: .init(translation: [0, 0.6, 0]), content: .light(firelight)))

        let geyser = slide.addChild(SceneGraph.Node(label: "Geyser", transform: .init(translation: [2.8, 0, -0.5])))
        geyser.particleSystems = [SceneParticleSystem(.geyser, seed: 2)]
        slideEmitters["Geyser"] = (geyser, geyser.particleSystems[0])
        // Far back, so the bursts open above the title.
        let fireworks = slide.addChild(SceneGraph.Node(label: "Fireworks", transform: .init(translation: [0, 0, -9])))
        fireworks.particleSystems = [SceneParticleSystem(.fireworks, seed: 3)]
        slideEmitters["Fireworks"] = (fireworks, fireworks.particleSystems[0])
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
            let node = slide.addChild(SceneGraph.Node(label: "Detail \(index + 1)", transform: .init(translation: [Float(index - 1) * 3.2, 0.9, -6], scale: SIMD3(repeating: 1.3)), content: .mesh(high, material: BlinnPhongSceneMaterial.plastic(color, shininess: 24))))
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
        let blobMaterial = PBRSceneMaterial(baseColor: [0.3, 0.8, 0.5], metallic: 0.1, roughness: 0.3)
        let blob = slide.addChild(SceneGraph.Node(label: "Blob", transform: .init(translation: [-2.5, 1.5, 0]), content: .mesh(mesh, material: blobMaterial)))
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
        let skeleton = slide.addChild(SceneGraph.Node(label: "Skeleton", transform: .init(translation: [2.5, 0, 0])))
        var joints = [skeleton.addChild(SceneGraph.Node(label: "Joint 0"))]
        for index in 1..<Self.tubeJointCount {
            joints.append(joints[index - 1].addChild(SceneGraph.Node(label: "Joint \(index)", transform: .init(translation: [0, jointSpacing, 0]))))
        }
        bendingJoints += joints.dropFirst()
        // Skinned vertices end up in world space, so the tube node's own transform does not matter.
        let skeletonInverse = skeleton.worldTransform.inverse
        let inverseBind = joints.map { (skeletonInverse * $0.worldTransform).inverse }
        let tubeMaterial = PBRSceneMaterial(baseColor: [0.9, 0.6, 0.2], metallic: 0, roughness: 0.4)
        let skinned = slide.addChild(SceneGraph.Node(label: "Tube", content: .mesh(tube, material: tubeMaterial)))
        skinned.skin = SceneGraph.Skin(joints: joints, inverseBindMatrices: inverseBind)
        skinned.skinVertices = skinVertices
    }

    private func performanceSlide(_ slide: SceneGraph.Node) {
        slide.addChild(SceneGraph.Node(label: "Sun", transform: Transform3D(position: [2, 6, 4], lookingAt: .zero), content: .light(Light(type: .directional, intensity: 1))))
        addLight(to: slide, at: [0, 4, 6], color: [0.5, 0.6, 0.9], intensity: 30)
        let box = MetalMesh(mesh: .box(), device: demoDevice)
        let materials = [[0.8, 0.5, 0.2], [0.6, 0.3, 0.15], [0.7, 0.6, 0.3]].map { BlinnPhongSceneMaterial.plastic($0, shininess: 16) }
        let grid = slide.addChild(SceneGraph.Node(label: "Grid", transform: .init(translation: [0, 0.5, -3])))
        crateGrid = grid
        let size = Self.crateGridSize
        let spacing: Float = 12 / Float(size)
        for row in 0..<size {
            for column in 0..<size {
                let trs = Transform3D(translation: [(Float(column) - Float(size - 1) / 2) * spacing, 0, (Float(row) - Float(size - 1) / 2) * spacing], scale: SIMD3(repeating: spacing * 0.8))
                crates.append(grid.addChild(SceneGraph.Node(label: "Crate", transform: trs, content: .mesh(box, material: materials[(row + column) % materials.count]))))
            }
        }
        crateCountLabel = slide.addChild(SceneGraph.Node(label: "Crate Count"))
        setCrateCount(size)
    }

    private func waveCrates(time: Float) {
        for crate in crates {
            let position = crate.transform.translation
            crate.transform.translation.y = sin(time * 2 + (position.x + position.z) * 0.8) * 0.4
        }
    }

    private func postProcessingSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 6, 6], intensity: 80)
        slide.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 12, height: 0.1, length: 6), material: BlinnPhongSceneMaterial.plastic([0.8, 0.8, 0.82], shininess: 8), transform: .init(translation: [0, -0.05, 0])))
        let colors: [SIMD3<Float>] = [[1, 0.35, 0.3], [1, 0.8, 0.3], [0.4, 0.85, 0.45], [0.3, 0.6, 1], [0.75, 0.45, 1]]
        for (index, color) in colors.enumerated() {
            let height = 0.6 + Float(index % 3) * 0.5
            slide.addChild(SceneGraph.Node(shape: .box(width: 0.9, height: height, length: 0.9), material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), transform: .init(translation: [Float(index) * 1.4 - 2.8, height / 2, 0])))
        }
        let torus = slide.addChild(SceneGraph.Node(shape: .torus(ringRadius: 0.5, pipeRadius: 0.18), material: BlinnPhongSceneMaterial.plastic([0.95, 0.95, 0.95], shininess: 64), transform: .init(translation: [0, 2.3, 0])))
        torus.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.5, 0]), duration: 6)))
        gradeLabels = Self.grades.map { grade in
            let label = slide.addChild(SceneGraph.Node(label: "Grade \(grade.name)"))
            addTitle(grade.name, size: 0.4, y: 3.1, color: [0.85, 0.85, 0.9], to: label)
            label.isVisible = false
            return label
        }
        gradeLabels.first?.isVisible = true
    }

    // nil shows the materials; the debug views replace them for the whole view, title and code panel included.
    private static let debugModes: [DebugMode?] = [nil, .normals, .textureCoordinates, .uvChecker, .worldPosition, .wireframe]

    // A selected box with its outline and the transform gizmo, which cycles through its modes.
    private func gizmosSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 60)
        slide.addChild(SceneGraph.Node(shape: .sphere(radius: 0.6), material: BlinnPhongSceneMaterial.plastic([0.4, 0.75, 0.45], shininess: 32), transform: .init(translation: [-3.2, 0.9, 0])))
        slide.addChild(SceneGraph.Node(shape: .cone(topRadius: 0, bottomRadius: 0.6, height: 1.3), material: BlinnPhongSceneMaterial.plastic([0.4, 0.55, 0.95], shininess: 32), transform: .init(translation: [3.2, 0.9, 0])))
        gizmoTarget = slide.addChild(SceneGraph.Node(label: "Box", shape: .box(width: 1.2, height: 1.2, length: 1.2), material: BlinnPhongSceneMaterial.plastic([0.95, 0.55, 0.3], shininess: 32), transform: .init(translation: [0, 0.9, 0], rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0]))))
    }

    private func debugViewsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 60)
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.sphere(radius: 0.7), [0.9, 0.4, 0.3]),
            (.torus(ringRadius: 0.6, pipeRadius: 0.22), [0.4, 0.75, 0.45]),
            (.box(width: 1.1, height: 1.1, length: 1.1), [0.4, 0.55, 0.95])
        ]
        for (index, (shape, color)) in shapes.enumerated() {
            let node = slide.addChild(SceneGraph.Node(shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), transform: .init(translation: [Float(index) * 2.4 - 3.6, 1.1, 0])))
            node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 7)))
        }
        if let die = DiceDemo.makeDie(.d20, style: .classicIvory) {
            die.physicsBody = nil
            die.transform = .init(translation: [3.6, 1.1, 0], scale: SIMD3(repeating: DiceDemo.dieScale * 2.2))
            slide.addChild(die)
            die.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([1, 0.6, 0.2]), duration: 9)))
        }
        debugLabels = Self.debugModes.map { mode in
            let name = mode?.name ?? "Materials"
            let label = slide.addChild(SceneGraph.Node(label: "Debug \(name)"))
            addTitle(name, size: 0.4, y: 3.1, color: [0.85, 0.85, 0.9], to: label)
            label.isVisible = false
            return label
        }
        debugLabels.first?.isVisible = true
    }

    private func updateDebugView(deltaTime: Float) {
        let picked = Int(self[value: "Debug View"])
        if picked > 0 {
            debugIndex = min(picked - 1, Self.debugModes.count - 1)
            sinceDebugMode = 0
        } else {
            sinceDebugMode += deltaTime
            if sinceDebugMode >= 2 {
                sinceDebugMode = 0
                debugIndex = (debugIndex + 1) % Self.debugModes.count
            }
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
        let picked = Int(self[value: "Grade"])
        if picked > 0 {
            let custom = SceneGraph.PostProcessing(
                exposure: self[value: "Exposure"],
                contrast: self[value: "Contrast"],
                saturation: self[value: "Saturation"],
                vignetteIntensity: self[value: "Vignette"]
            )
            let index = picked - 1
            sceneGraph.postProcessing = Self.grades.indices.contains(index) ? Self.grades[index].settings : custom
            for (labelIndex, label) in gradeLabels.enumerated() where label.isVisible != (labelIndex == index) {
                label.isVisible = labelIndex == index
            }
            return
        }
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
        let window = slide.addChild(SceneGraph.Node(label: "Window", transform: .init(translation: [0, 1.4, -0.5])))
        for (size, position) in [([6.1, 0.05], [0, 1.7]), ([6.1, 0.05], [0, -1.7]), ([0.05, 3.4], [-3.05, 0]), ([0.05, 3.4], [3.05, 0])] as [(SIMD2<Float>, SIMD2<Float>)] {
            window.addChild(SceneGraph.Node(shape: .box(width: size.x, height: size.y, length: 0.05), material: frame, transform: .init(translation: [position.x, position.y, 0])))
        }
        let turntable = slide.addChild(SceneGraph.Node(label: "Turntable", transform: .init(translation: [0, 1.2, 0])))
        turntable.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 8)))
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [(.box(width: 0.7, height: 0.7, length: 0.7), [1, 0.4, 0.3]), (.sphere(radius: 0.4), [0.3, 0.8, 1]), (.cone(bottomRadius: 0.4, height: 0.8), [0.5, 0.9, 0.4])]
        for (index, (shape, color)) in shapes.enumerated() {
            let angle = Float(index) * 2 * .pi / 3
            turntable.addChild(SceneGraph.Node(shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 48), transform: .init(translation: [cos(angle) * 1.4, 0, sin(angle) * 1.4])))
        }
    }
}
