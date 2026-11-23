import AVFoundation
import Foundation
import GeometryLite3D
import Metal
import MetalKit
import MetalSprocketsGLTF
import MetalSprocketsParticles
import MetalSprocketsParticlesSamples
import MetalSprocketsPBR
import MetalSprocketsPBRShaders
import SceneSprockets
import SceneSprocketsAddOns
import SceneSprocketsBlinnPhong
import SceneSprocketsGizmos
import SceneSprocketsMaterialX
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
        "SceneSprockets", "SceneView", "Scene Graph", "Shapes", "Materials", "Lights", "Many Lights",
        "Shadows", "Shadow Settings", "Fog", "Decals", "Mirrors", "Opacity & Fades", "Blend Modes", "Stochastic", "Glass", "PBR Extensions", "Subsurface", "Custom Shaders", "Video Textures", "glTF & Model I/O", "MaterialX",
        "Actions", "Implicit Animation", "Constraints", "Paths", "Animation Blending", "Deformation",
        "Particles", "Mesh Emitters",
        "Physics", "More Physics", "Post-Processing", "Bloom", "Level of Detail", "Performance", "SwiftECS World",
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
    // Decals read the scene's depth, which the view keeps readable when shadows are on (#644).
    private static let shadowedTitles: Set<String> = ["Shadows", "Shadow Settings", "Fog", "Decals", "Metaballs", "Voxels", "Toon"]
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
    // The More Physics slide (#610): static parts are built once, moving bodies on each arrival.
    private var morePhysicsBodies: SceneGraph.Node?
    private var tankRegion: BoundingBox3D?
    private var walker: SceneGraph.Node?
    private var walkerController: CharacterController?
    private var walkerRange: ClosedRange<Float> = 0...0
    private var triggerRing: SceneGraph.Node?
    private var impactStep: SceneGraph.Node?
    private var bouncingBall: SceneGraph.Node?
    private var triggerGlow: Float = 0
    private var impactGlow: Float = 0
    private let impactForFullGlow: Float = 100
    private var sinceMorePhysicsReset: Float = 0
    private var sinceBallDrop: Float = 0
    private var physicsDebugNode: SceneGraph.Node?
    // The Many Lights slide's swarm (#611): every light is built once; the count slider hides the rest.
    private var swarmLights: [(node: SceneGraph.Node, phase: Float, radius: Float, speed: Float)] = []
    // The Decals slide (#644): the decal that slides over the step, and its material, whose angle limit the slider sets.
    private var movingDecal: SceneGraph.Node?
    // The Mirrors slide (#645): shapes that orbit above the mirror floor, and the floor's PBR material.
    private var mirrorShapes: [SceneGraph.Node] = []
    private var mirrorFloor: SceneGraph.Node?
    // The Subsurface slide (#646): the light that circles the pair, and the materials whose scattering the sliders set.
    private var subsurfaceLight: SceneGraph.Node?
    // The Stochastic slide (#647): the two card clusters that spin, and their materials, whose opacity the slider sets.
    private var cardClusters: [SceneGraph.Node] = []
    // The Shadow Settings slide (#648): the sun, whose shadow settings the controls set.
    private var cascadeSun: SceneGraph.Node?
    // The Bloom slide (#649): the glowing shapes that turn.
    private var neonShapes: SceneGraph.Node?
    private var cardMaterials: [PBRSceneMaterial] = []
    private var subsurfaceMaterials: [PBRSceneMaterial] = []
    private static let maximumSwarmLights = 400
    private let debugDrawMaterial = ShaderMaterial.vertexColors()
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
    // Gizmos slide: one object per transform gizmo mode, with where it started, and the one selected (#626).
    private var gizmoObjects: [(node: SceneGraph.Node, mode: TransformGizmo.Mode, rest: Transform3D)] = []
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
    // Each node with the material it was built with, which the slide's controls copy and change.
    private var glassPieces: [(node: SceneGraph.Node, base: PBRMaterial)] = []
    private var pbrExtensionBases: [(node: SceneGraph.Node, base: PBRMaterial)] = []
    private var rimNodes: [SceneGraph.Node] = []
    private var fireflyTrails: [(node: SceneGraph.Node, system: SceneParticleSystem)] = []
    private var hopCubes: [SceneGraph.Node] = []
    private var fadeSpheres: [SceneGraph.Node] = []
    private var lookAtCones: [(node: SceneGraph.Node, constraint: SceneGraph.Constraint)] = []
    // The Paths slide (#612).
    private var trackNode: SceneGraph.Node?
    private var cars: [(node: SceneGraph.Node, fraction: Float)] = []
    private var slideEmitters: [String: (node: SceneGraph.Node, system: SceneParticleSystem)] = [:]
    private var crateCountLabel: SceneGraph.Node?
    private var crateGrid: SceneGraph.Node?
    // The Lights slide's ambient light node (#616).
    private var ambientLight: SceneGraph.Node?
    // Explicit instancing on the Performance slide (#614): one instancedMesh node per material, with the indices of
    // its crates in `crates`.
    private var instancedCrateGroups: [(node: SceneGraph.Node, mesh: MetalMesh, material: any SceneMaterial, crateIndices: [Int])] = []
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
            renderers: [BlinnPhongMaterialRenderer(ambientLightColor: [0.05, 0.05, 0.07]), pbr, ShaderMaterialRenderer(), PointCloudRenderer(), TerrainRenderer(), SignedDistanceRenderer(ambientLightColor: [0.05, 0.05, 0.07], pbr: pbr), VoxelRenderer(ambientLightColor: [0.15, 0.15, 0.18], pbr: pbr), ToonRenderer(), DecalRenderer()],
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
        physics?.contactHandler = { [weak self] contact in self?.morePhysicsContact(contact) }
        physicsDebugNode = sceneGraph.root.addChild(SceneGraph.Node(label: "Physics Debug"))
        physicsDebugNode?.opacity = 0.45
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
        // Taps do not select: only the Gizmos slide shows a selection, always one of its shapes (#328). Clicking a
        // shape there selects it (#626).
        if currentTitle == "Gizmos", let hit, let object = gizmoObjects.first(where: { $0.node === hit.node || $0.node.isAncestor(of: hit.node) }) {
            selectGizmoObject(object.node)
            return
        }
        selectGizmoObject(gizmoTarget)
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
        • Right: a flat tile with a brick height map. Parallax occlusion mapping makes the bricks look deep,
          with no extra geometry and no tangents.
        """,
        "Lights": """
        • Point, spot and directional lights are nodes like everything else.
        • These three colored point lights orbit because their parent node spins.
        • Range limits how far each light reaches.
        • An ambient light node adds even light everywhere, so the sides away from the lights are not black.
        """,
        "Many Lights": """
        • Hundreds of short-range point lights, with no special setup.
        • From 16 lights on, a compute pass sorts lights into a grid of view clusters.
        • Each pixel then shades only the lights in its cluster, not every light.
        • Blinn-Phong and PBR both use the clusters; the result matches shading every light.
        """,
        "Shadows": """
        • Shadow maps from a directional sun light.
        • Turn them on in SceneView with Shadows; softness and intensity are settings.
        """,
        "Fog": """
        • Fog is one property on the scene graph: sceneGraph.fog.
        • Volumetric fog scatters the moonlight in the air; the pillars' shadows cut shafts through it.
        • It marches each pixel's ray through the shadow map, so it needs shadows on.
        • Distance fog (start and end distances) is also available, alone or with it.
        """,
        "Bloom": """
        • Bloom makes bright light glow past its edges, like neon signs and the sun through a lens.
        • One setting: sceneGraph.postProcessing.bloom, with a threshold, intensity and radius.
        • With bloom on, the scene is drawn in floating point (HDR), so these tubes can be far brighter than white.
        • Bloom, exposure and tone mapping then run as post passes over the whole frame.
        """,
        "Shadow Settings": """
        • Each light can override the scene's shadow settings: Light.shadowSettings.
        • Cascades split a sun's shadow map by distance from the camera: sharp shadows near, coarser far away.
        • Turn Cascades off: one map has to cover the whole long street, and the near posts' shadows go blurry.
        • Resolution scale and bias are per light too, to spend shadow memory where it matters.
        """,
        "Stochastic": """
        • Crossed, see-through cards, like foliage or hair, cut through each other, so no draw order is right.
        • Left: sorted alpha blending. Whole cards pop in front of each other as they turn.
        • Right: stochastic transparency. Each pixel is covered or not at random, by alpha, and depth sorts it.
        • No sorting at all. Noisy with one sample; it looks best with 4x MSAA.
        """,
        "Subsurface": """
        • Skin, wax and marble let light in and scatter it under the surface, so their shadow edge glows softly.
        • Left: plain PBR. Right: the same material with subsurface scattering, tinted red like skin.
        • It wraps the diffuse light past the terminator; strength and radius are two material values.
        • An approximation that costs almost nothing; thin surfaces like leaves use diffuse transmission instead.
        """,
        "Mirrors": """
        • A node with planarReflector becomes a mirror: its plane shows the scene reflected in it.
        • Each frame the scene is drawn once more from the camera mirrored in the plane, into a texture.
        • PBR materials on the node use it instead of the environment's reflections; rougher surfaces blur it.
        • Like a polished floor or still water. One mirror per frame.
        """,
        "Decals": """
        • A decal projects an image onto whatever surfaces are inside a box: road markings, footprints, bullet holes.
        • It is a DecalMaterial on a box-shaped node; the node's transform places and sizes the projector.
        • The moving arrow wraps over the step and fades on the steep side, past the maximum angle.
        • Decals draw after the scene from its depth, so they need no changes to the meshes they land on.
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
        "MaterialX": """
        • An add-on: import SceneSprocketsMaterialX and load a .mtlx file.
        • Each material becomes a PBR material: gold is standard_surface, the car paint is open_pbr_surface,
          the jade is gltf_pbr.
        • The car paint's color comes from a small node graph; math on constants is worked out at load.
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
        "Paths": """
        • A node's path is a smooth curve (Catmull-Rom) through points, in the node's own space.
        • The followPath constraint keeps each car at a fraction along it, facing the way it goes.
        • The whole track turns and tilts; the path, and the cars on it, move with its node.
        • The ball runs an Action.follow along a curve given in code.
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
        "More Physics": """
        • Joints: a chain of ball joints hangs from the world and swings.
        • Buoyancy: crates float in a fluid region. One crate is locked to move only up and down (axis locks).
        • Triggers: the ring above the tank only detects crates passing through it, and glows.
        • Contacts report impact strength: the step flashes brighter the harder the ball hits.
        • A character controller walks back and forth and climbs the step.
        • Physics Debug draws Jolt's own view of the bodies.
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
        • Explicit Instancing swaps the crate nodes for three instancedMesh nodes, one per color: one node holds
          every copy's transform, so there is no node per crate to update.
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
        • Transform gizmos move, rotate and scale nodes: the sphere moves, the box rotates, the cone scales.
        • Click a shape to select it; the selection outline shows which one, and its gizmo is the one to drag.
        • Both come from SceneSprocketsGizmos and plug into SceneView.
        • Editor gizmos draw what has no geometry: a ground grid, axes, line icons for lights and the selection's bounds.
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
                .toggle("Red Light", default: true), .toggle("Green Light", default: true), .toggle("Blue Light", default: true),
                .slider("Ambient Light", 0...1, default: 0.15)
            ]
        case "Shadows":
            [.toggle("Cast Shadows", default: true), .slider("Sun Angle", -90...90, default: 0), .slider("Shadow Spin", 0...3, default: 1)]
        case "Fog":
            [
                .toggle("Fog", default: true), .slider("Fog Density", 0...0.2, default: 0.06)
            ]
        case "Decals":
            [.toggle("Move Decal", default: true), .slider("Maximum Angle", 10...90, default: 60)]
        case "Bloom":
            [.toggle("Bloom", default: true), .slider("Bloom Threshold", 0.5...4, default: 1), .slider("Bloom Intensity", 0...2, default: 0.6), .slider("Bloom Radius", 1...8, default: 6), .slider("Neon Spin", 0...3, default: 1)]
        case "Shadow Settings":
            [.toggle("Cascades", default: true), .slider("Cascade Count", 2...4, default: 4), .slider("Sun Resolution", 0.25...1, default: 1)]
        case "Stochastic":
            [.slider("Card Opacity", 0.1...0.9, default: 0.5), .slider("Card Spin", 0...3, default: 1)]
        case "Subsurface":
            [.slider("Subsurface Strength", 0...2, default: 1), .slider("Subsurface Radius", 0...1, default: 0.6), .slider("Subsurface Light Speed", 0...3, default: 1)]
        case "Mirrors":
            [.toggle("Reflect", default: true), .slider("Floor Roughness", 0...0.6, default: 0.05), .slider("Mirror Orbit Speed", 0...3, default: 1)]
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
        case "Paths":
            [.slider("Car Speed", 0...3, default: 1), .slider("Track Spin", 0...3, default: 1)]
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
            [.toggle("Wave", default: true), .slider("Crate Grid", 1...Float(crateGridSize), default: Float(crateGridSize)), .toggle("Explicit Instancing", default: false)]
        case "SwiftECS World":
            [.slider("Cohesion", 0...2, default: 0.6), .slider("Alignment", 0...2, default: 0.8), .slider("Separation", 0...1, default: 0.35)]
        case "Gizmos":
            [.toggle("Editor Gizmos", default: true)]
        case "Debug Views":
            [.choice("Debug View", ["Cycle"] + debugModes.map { $0?.name ?? "Materials" })]
        case "Point Clouds":
            [.slider("Galaxy Speed", 0...5, default: 1), .slider("Point Size", 1...8, default: 2)]
        case "Terrain":
            [.slider("Terrain Speed", 0...5, default: 1), .slider("Height Exaggeration", 0...8, default: 3), .choice("Terrain Style", terrainStyles.map(\.name), default: 3)]
        case "Many Lights":
            [.slider("Swarm Size", 1...Float(maximumSwarmLights), default: 300), .slider("Swarm Range", 0.5...4, default: 1.6), .slider("Swarm Speed", 0...3, default: 1)]
        case "Physics":
            [.toggle("Auto-roll", default: true)]
        case "More Physics":
            [.toggle("Physics Debug", default: false), .slider("Walk Speed", 0...4, default: 1.5)]
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
            [action("Reset Shapes", "arrow.counterclockwise") { $0.resetGizmoObjects() }]
        case "Physics":
            [action("Roll Dice", "dice") { $0.resetPhysics() }]
        case "More Physics":
            [action("Restart Physics", "arrow.counterclockwise") { $0.resetMorePhysics() }]
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
        // Volumetric fog only (#540, #613, #627): the moon's light scatters in the air, with shafts where the pillars
        // shadow it. A zero alpha turns the distance fog off; the two together looked wrong. The density eases in and
        // out with the transition.
        let scattering = SceneGraph.Fog.Scattering(density: self[value: "Fog Density"] * fogAmount, intensity: 0.5, anisotropy: 0.6, stepCount: 48, maximumDistance: 30)
        sceneGraph.fog = SceneGraph.Fog(color: [0.05, 0.06, 0.1, 0], scattering: scattering)
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
            if self[flag: "Explicit Instancing"] {
                updateInstancedCrates(time: self[flag: "Wave"] ? time : nil)
            } else if self[flag: "Wave"] {
                waveCrates(time: time)
            }
        case "Post-Processing":
            updateGrade(deltaTime: deltaTime)
        case "Debug Views":
            updateDebugView(deltaTime: deltaTime)
        case "SwiftECS World":
            boids?.step(deltaTime: deltaTime)
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
        case "More Physics":
            updateMorePhysics(deltaTime: deltaTime)
        case "Many Lights":
            updateSwarm(time: time)
        case "Paths":
            updateCars(deltaTime: deltaTime)
        case "Decals":
            updateDecals(time: time)
        case "Mirrors":
            updateMirrors(time: time)
        case "Subsurface":
            updateSubsurface(time: time)
        case "Stochastic":
            updateCards(time: time)
        case "Shadow Settings":
            updateCascadeSun()
        case "Bloom":
            neonShapes?.transform = .init(translation: [0, 1.8, 0], rotation: simd_quatf(angle: time * 0.3 * self[value: "Neon Spin"], axis: [0, 1, 0]))
            updateBloom()
        default:
            break
        }
    }

    // Shadows and fog apply to the whole scene, so they are switched on only for their slides.
    private func applySceneSettings() {
        let castsShadows = currentTitle != "Shadows" || self[flag: "Cast Shadows"]
        shadows = Self.shadowedTitles.contains(currentTitle) && castsShadows ? shadowRenderer : nil
        // The Gizmos slide selects one of its shapes; other slides show no selection.
        showsSelectionOutline = currentTitle == "Gizmos"
        selectGizmoObject(gizmoTarget)
        applyEditorGizmos()
        // The Subsurface slide dims the environment, so its one side light shows the soft shadow edge (#646).
        sceneGraph.environment.intensity = currentTitle == "Subsurface" ? 0.15 : 1
        // A debug view replaces every material in the view, so it is on only for its slide.
        debugIndex = 0
        sinceDebugMode = 0
        debugMode = nil
        if currentTitle != "Video Textures" {
            videoTexture?.player.pause()
        }
        if currentTitle != "More Physics" {
            removeWalker()
            physicsDebugNode?.content = .empty
        }
        if currentTitle == "Post-Processing" {
            gradeIndex = 0
            sinceGrade = 0
        } else if currentTitle == "Bloom" {
            updateBloom()
        } else {
            sceneGraph.postProcessing = nil
        }
    }

    // Editor gizmos on the Gizmos slide (#406, #617), with the grid and axes at the slide's origin.
    private func applyEditorGizmos() {
        let shows = currentTitle == "Gizmos" && self[flag: "Editor Gizmos"]
        editorGizmos = shows ? [.grid, .axes, .lightsAndCameras, .bounds] : []
        if shows, let index = Self.titles.firstIndex(of: "Gizmos"), slides.indices.contains(index) {
            // Half size and set back, so the grid stays behind the code panel's line of sight.
            editorGridTransform = slides[index].worldTransform * Transform3D(translation: [0, 0, -3], scale: [0.5, 0.5, 0.5]).matrix
        }
    }

    // `visibleAfter` is how long until the slide has faded in.
    private func resetCurrentSlide(visibleAfter: Float) {
        if currentTitle == "Thank You" {
            startFinale(after: visibleAfter + 0.5)
        }
        if currentTitle == "Physics" {
            physics?.gravity = Self.trayTilt.act([0, -9.81, 0])
            resetPhysics()
        }
        if currentTitle == "More Physics" {
            resetMorePhysics()
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
        case "Gizmos":
            if changed("Editor Gizmos") {
                applyEditorGizmos()
            }
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
            if changed("Ambient Light"), let ambientLight, case var .light(light) = ambientLight.content {
                light.intensity = self[value: "Ambient Light"]
                ambientLight.content = .light(light)
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
                for (node, base) in glassPieces {
                    setMaterial(of: node, from: base) { uniforms in
                        uniforms.roughnessFactor = min(uniforms.roughnessFactor + self[value: "Frosting"], 1)
                        uniforms.thicknessFactor = self[value: "Thickness"]
                        uniforms.transmissionFactor = self[value: "Transmission"]
                    }
                }
            }
        case "PBR Extensions":
            if changed("Sheen", "Diffuse Transmission", "Clearcoat", "Iridescence") {
                for (node, base) in pbrExtensionBases {
                    setMaterial(of: node, from: base) { uniforms in
                        if !self[flag: "Sheen"] {
                            uniforms.sheenColorFactor = .zero
                        }
                        if !self[flag: "Diffuse Transmission"] {
                            uniforms.diffuseTransmissionFactor = 0
                        }
                        if !self[flag: "Clearcoat"] {
                            uniforms.clearcoatFactor = 0
                        }
                        if !self[flag: "Iridescence"] {
                            uniforms.iridescenceFactor = 0
                        }
                    }
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
            if changed("Crate Grid", "Explicit Instancing") {
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

    // Gives the node a copy of `base` with changed uniforms.
    private func setMaterial(of node: SceneGraph.Node, from base: PBRMaterial, _ change: (inout PBRMaterialUniforms) -> Void) {
        guard case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content else {
            return
        }
        var uniforms = base.uniforms
        change(&uniforms)
        node.content = .mesh(mesh, materials: [PBRSceneMaterial(base.with(uniforms: uniforms))], castsShadow: castsShadow, receivesShadow: receivesShadow)
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
        let isInstanced = values["Explicit Instancing"].map { $0 != 0 } ?? false
        for (index, crate) in crates.enumerated() {
            crate.isVisible = !isInstanced && index / full < size && index % full < size
        }
        for group in instancedCrateGroups {
            group.node.isVisible = isInstanced
        }
        if isInstanced {
            updateInstancedCrates(time: nil)
        }
        guard let crateCountLabel else {
            return
        }
        crateCountLabel.removeAllChildren()
        addTitle(isInstanced ? "\(size * size) crates, 3 instanced-mesh nodes" : "\(size * size) crates, 3 draw calls", size: 0.35, y: 3, color: [0.6, 0.65, 0.75], to: crateCountLabel)
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

    private func resetGizmoObjects() {
        for object in gizmoObjects {
            object.node.transform = object.rest
        }
    }

    // On the Gizmos slide, selects `node` (one of the shapes) and gives it its gizmo to drag; the other shapes show
    // theirs for display (#626). Elsewhere, clears the selection and the gizmos.
    private func selectGizmoObject(_ node: SceneGraph.Node?) {
        guard currentTitle == "Gizmos", let node, let selected = gizmoObjects.first(where: { $0.node === node }) else {
            selectedNodeID = nil
            gizmoMode = nil
            displayGizmos = []
            return
        }
        gizmoTarget = node
        selectedNodeID = node.id
        gizmoMode = selected.mode
        displayGizmos = gizmoObjects.filter { $0.node !== node }.map { ($0.node, $0.mode) }
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
            bricks.heightMap = .texture(heights) // parallax occlusion mapping
            """, to: slide)
        case "Lights":
            addTitle(title, y: 4, to: slide)
            lightsSlide(slide)
            addCode("""
            var light = Light(type: .point, color: [1, 0.2, 0.2], intensity: 25)
            light.range = 14
            pivot.addChild(SceneGraph.Node(content: .light(light)))
            slide.addChild(SceneGraph.Node(content: .light(Light(type: .ambient, intensity: 0.15))))
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
        case "Paths":
            addTitle(title, y: 4, to: slide)
            pathsSlide(slide)
            addCode("""
            track.path = SceneGraph.Spline(points: points, isClosed: true)
            car.constraints = [.followPath(track, fraction: 0.25, orientsToPath: true)]
            ball.run(.follow(arc, duration: 3, orientsToPath: false))
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
            glass.uniforms.transmissionFactor = 1
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
            // Or one node for every copy:
            grid.addChild(SceneGraph.Node(content: .instancedMesh(box, material: crate, transforms: matrices)))
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
                .sceneDecorations { context, size in
                    try EditorGizmos.element(sceneGraph: scene, viewport: viewport(context, size), selected: [box.id])
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
        case "Bloom":
            bloomSlide(slide)
            addCode("""
            sceneGraph.postProcessing = SceneGraph.PostProcessing(
                bloom: .init(threshold: 1, intensity: 0.6, radius: 6))
            """, to: slide)
        case "Shadow Settings":
            shadowSettingsSlide(slide)
            addCode("""
            var sun = Light(type: .directional, intensity: 2)
            sun.shadowSettings = Light.ShadowSettings(cascadeCount: 4, resolutionScale: 1)
            """, to: slide)
        case "Stochastic":
            stochasticSlide(slide)
            addCode("""
            let leaf = PBRSceneMaterial(baseColor: [0.3, 0.8, 0.35], opacity: 0.5)
            leaf.renderState = PBRRenderState(blendMode: .stochastic)
            SceneView(scene, renderers: renderers).sceneAntialiasing(sampleCount: 4)
            """, to: slide)
        case "Subsurface":
            subsurfaceSlide(slide)
            addCode("""
            var uniforms = wax.uniforms
            uniforms.subsurfaceColor = [1, 0.35, 0.25]
            uniforms.subsurfaceStrength = 1
            uniforms.subsurfaceRadius = 0.6
            wax.uniforms = uniforms
            """, to: slide)
        case "Mirrors":
            mirrorsSlide(slide)
            addCode("""
            let floor = SceneGraph.Node(shape: .plane(width: 8, height: 5),
                material: PBRSceneMaterial(baseColor: [0.45, 0.47, 0.5], metallic: 0.6, roughness: 0.05))
            floor.planarReflector = SceneGraph.PlanarReflector(resolutionScale: 0.5)
            """, to: slide)
        case "Decals":
            decalsSlide(slide)
            addCode("""
            let arrow = DecalMaterial(texture: arrowTexture, maximumAngle: .pi / 3)
            floor.addChild(SceneGraph.Node(shape: .box(), material: arrow,
                transform: .init(rotation: lookDown, scale: [1.2, 1.2, 1])))
            SceneView(scene, renderers: renderers + [DecalRenderer()])
            """, to: slide)
        case "Fog":
            fogSlide(slide)
            addCode("""
            // Alpha 0: volumetric fog only, no distance fog.
            sceneGraph.fog = SceneGraph.Fog(color: [0.05, 0.06, 0.1, 0],
                                            scattering: .init(density: 0.06, intensity: 0.5, anisotropy: 0.6))
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
        case "MaterialX":
            materialXSlide(slide)
            addCode("""
            import SceneSprocketsMaterialX
            let document = try MaterialXDocument(url: mtlxURL)
            sphere.content = .mesh(mesh, material: document["Gold"]!)
            // document.warnings lists anything not converted
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
        case "Many Lights":
            manyLightsSlide(slide)
            addCode("""
            for color in colors {
                lights.addChild(SceneGraph.Node(content: .light(Light(type: .point, color: color, range: 1.6))))
            }
            SceneGraphElement(...).lightClustering(.automatic) // the default: on from 16 lights
            """, to: slide)
        case "More Physics":
            morePhysicsSlide(slide)
            addCode("""
            physics.addJoint(.ball(anchor: anchor), between: linkA, and: linkB)
            physics.fluids = [.init(region: tank, buoyancy: 1.5)]
            ring.physicsBody = .init(type: .static, shape: .cylinder(height: 0.2, radius: 1), isTrigger: true)
            physics.contactHandler = { contact in flash(contact.impulse) }
            physics.addCharacter(for: walker)?.desiredVelocity = [1.5, 0, 0]
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
            // Left of center, leaving room for the parallax tile on the right.
            let x = Float(column) * 1.5 - 5
            let smoothness = Float(column) / 5
            var materials: [any SceneMaterial] = [BlinnPhongSceneMaterial.plastic(paints[column], shininess: 4 + smoothness * 120)]
            materials.append(PBRSceneMaterial(baseColor: metals[column], metallic: 1, roughness: 0.75 - smoothness * 0.7))
            let plastic = PBRSceneMaterial(baseColor: plastics[column], metallic: 0, roughness: 0.8 - smoothness * 0.7)
            // The glossiest plastics get a clear coat, like car paint.
            if column >= 4 {
                plastic.uniforms.clearcoatFactor = 1
                plastic.uniforms.clearcoatRoughnessFactor = 0.05
            }
            materials.append(plastic)
            for (row, material) in materials.enumerated() {
                let node = slide.addChild(SceneGraph.Node(shape: shapes[(column + row * 2) % shapes.count], material: material, transform: .init(translation: [x, 2.7 - Float(row) * 1.3, 0])))
                node.run(.repeatForever(.rotate(by: .pi * 2, around: simd_normalize([0.3, 1, 0.2]), duration: 8 + Float(column + row))))
            }
        }
        addParallaxTile(to: slide)
    }

    // A thin brick tile with parallax occlusion mapping (#537, #615), swinging so the bricks' depth shows.
    private func addParallaxTile(to slide: SceneGraph.Node) {
        guard let textures = Self.brickTextures(device: demoDevice) else {
            return
        }
        var material = BlinnPhongSceneMaterial(ambient: .color(0.05), diffuse: .texture(textures.color), specular: .color(0.15), shininess: 24)
        material.heightMap = .texture(textures.height)
        material.parallaxDepth = 0.06
        let swing = slide.addChild(SceneGraph.Node(label: "Parallax Swing", transform: .init(translation: [4.6, 1.6, 0])))
        swing.run(.repeatForever(.sequence([
            .rotate(by: 0.9, around: [0, 1, 0], duration: 3).timingMode(.easeInEaseOut),
            .rotate(by: -0.9, around: [0, 1, 0], duration: 3).timingMode(.easeInEaseOut)
        ])))
        swing.addChild(SceneGraph.Node(label: "Parallax Tile", shape: .box(width: 2, height: 2, length: 0.1), material: material, transform: .init(rotation: simd_quatf(angle: -0.45, axis: [0, 1, 0]))))
    }

    // Running-bond bricks: color with mortar lines, and heights 1 on the brick faces, bevelled down to 0 in the mortar.
    private static func brickTextures(device: MTLDevice) -> (color: MTLTexture, height: MTLTexture)? {
        let size = 256
        let rows = 8
        let columns = 4
        let brickHeight = size / rows
        let brickWidth = size / columns
        var color = [UInt8](repeating: 0, count: size * size * 4)
        var height = [UInt8](repeating: 0, count: size * size)
        for y in 0 ..< size {
            let row = y / brickHeight
            let offset = row.isMultiple(of: 2) ? 0 : brickWidth / 2
            for x in 0 ..< size {
                let localX = (x + offset) % brickWidth
                let localY = y % brickHeight
                // Distance in pixels to the nearest mortar line.
                let edge = min(localX, brickWidth - 1 - localX, localY, brickHeight - 1 - localY)
                let level = min(max(Float(edge - 2) / 4, 0), 1)
                height[y * size + x] = UInt8(level * 255)
                // A little variation per brick.
                let brick = (row * 7 + (x + offset) / brickWidth * 13) % 5
                let brickColor: SIMD3<Float> = [0.55 + Float(brick) * 0.04, 0.22 + Float(brick) * 0.02, 0.15]
                let mortar: SIMD3<Float> = [0.6, 0.58, 0.55]
                let rgb = level > 0 ? brickColor : mortar
                let index = (y * size + x) * 4
                color[index] = UInt8(rgb.x * 255)
                color[index + 1] = UInt8(rgb.y * 255)
                color[index + 2] = UInt8(rgb.z * 255)
                color[index + 3] = 255
            }
        }
        func texture(_ format: MTLPixelFormat, _ bytes: [UInt8], bytesPerPixel: Int, label: String) -> MTLTexture? {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: size, height: size, mipmapped: false)
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                return nil
            }
            texture.label = label
            texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: bytes, bytesPerRow: size * bytesPerPixel)
            return texture
        }
        guard let colorTexture = texture(.rgba8Unorm_srgb, color, bytesPerPixel: 4, label: "Bricks"), let heightTexture = texture(.r8Unorm, height, bytesPerPixel: 1, label: "Brick Heights") else {
            return nil
        }
        return (colorTexture, heightTexture)
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
        // A faint blue ambient light node (#602, #616): even light on every surface, so the unlit sides are not black.
        ambientLight = slide.addChild(SceneGraph.Node(label: "Ambient Light", content: .light(Light(type: .ambient, color: [0.4, 0.5, 1], intensity: 0.15))))
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

    // A closed track with cars kept on it by followPath constraints, and a ball on an Action.follow arc (#612).
    private func pathsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 70)
        // Tilted toward the camera so the loop reads as a loop; the inner node turns it about its own up axis.
        let tilt = slide.addChild(SceneGraph.Node(label: "Track Tilt", transform: .init(translation: [0, 1.4, 0], rotation: simd_quatf(angle: 0.5, axis: [1, 0, 0]))))
        let track = tilt.addChild(SceneGraph.Node(label: "Track"))
        let points: [SIMD3<Float>] = [[-4, 0, 0], [-2.5, 0.7, -1.6], [0, 0, -0.6], [2.5, -0.7, -1.6], [4, 0, 0], [2.5, 0.7, 1.6], [0, 0, 0.6], [-2.5, -0.7, 1.6]]
        let spline = SceneGraph.Spline(points: points, isClosed: true)
        track.path = spline
        track.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 24)))
        trackNode = track
        // The path itself draws nothing; dots show it.
        let dot = BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color([0.4, 0.75, 1]))
        for index in 0 ..< 90 {
            track.addChild(SceneGraph.Node(label: "Track Dot", shape: .sphere(radius: 0.04), material: dot, transform: .init(translation: spline.position(at: Float(index) / 90))))
        }
        let colors: [SIMD3<Float>] = [[0.95, 0.35, 0.3], [0.95, 0.8, 0.25], [0.35, 0.85, 0.45], [0.75, 0.45, 0.95]]
        cars = colors.enumerated().map { index, color in
            let car = slide.addChild(SceneGraph.Node(label: "Car"))
            let paint = BlinnPhongSceneMaterial.plastic(color, shininess: 48)
            car.addChild(SceneGraph.Node(shape: .box(width: 0.32, height: 0.22, length: 0.6), material: paint))
            // The nose points along -Z, the direction of travel.
            car.addChild(SceneGraph.Node(shape: .cone(bottomRadius: 0.14, height: 0.3), material: paint, transform: .init(translation: [0, 0, -0.42], rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))))
            let fraction = Float(index) / Float(colors.count)
            car.constraints = [.followPath(track, fraction: fraction, orientsToPath: true)]
            return (car, fraction)
        }
        // An open arc above the track, given in the slide's space.
        let arc = SceneGraph.Spline(points: [[-3, 3, -1], [-1.5, 3.6, -1], [0, 3.2, -1], [1.5, 3.6, -1], [3, 3, -1]])
        let ball = slide.addChild(SceneGraph.Node(label: "Arc Ball", shape: .sphere(radius: 0.18), material: BlinnPhongSceneMaterial.plastic([1, 0.6, 0.2], shininess: 64), transform: .init(translation: [-3, 3, -1])))
        ball.run(.repeatForever(.sequence([.follow(arc, duration: 3), .follow(arc.reversed, duration: 3)])))
    }

    // Moves each car along the track by changing its constraint's fraction.
    private func updateCars(deltaTime: Float) {
        guard let trackNode else {
            return
        }
        trackNode.actionSpeed = self[value: "Track Spin"]
        // About 6 seconds per lap at speed 1.
        let step = deltaTime * self[value: "Car Speed"] / 6
        for index in cars.indices {
            cars[index].fraction = (cars[index].fraction + step).truncatingRemainder(dividingBy: 1)
            cars[index].node.constraints = [.followPath(trackNode, fraction: cars[index].fraction, orientsToPath: true)]
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
            glass.uniforms.transmissionFactor = 1
            glass.uniforms.thicknessFactor = 0.6
            let node = slide.addChild(SceneGraph.Node(shape: shape, material: glass, transform: .init(translation: [x, 1.6, 1])))
            glassPieces.append((node, glass.pbrMaterial))
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
            candy.uniforms.clearcoatFactor = 1
            candy.uniforms.clearcoatRoughnessFactor = 0.03
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
                material.uniforms.transmissionFactor = 1
                material.uniforms.thicknessFactor = 0.6
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

    private func decalsSlide(_ slide: SceneGraph.Node) {
        slide.addChild(SceneGraph.Node(label: "Sun", transform: Transform3D(position: [2, 6, 4], lookingAt: [0, 0, 0]), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 0.9))))
        addLight(to: slide, at: [-3, 3, 5], color: [0.6, 0.7, 1], intensity: 6, castsShadow: false)
        // Matte, so the decals are not washed out by a broad highlight.
        let concrete = BlinnPhongSceneMaterial(ambient: .color(0.3), diffuse: .color([0.45, 0.45, 0.48]), specular: .color(0.02), shininess: 8)
        // Tilted toward the camera, so the ground and the decals on it face the audience.
        let slide = slide.addChild(SceneGraph.Node(label: "Street", transform: .init(translation: [0, 0.8, 0], rotation: simd_quatf(angle: 0.7, axis: [1, 0, 0]), scale: [1.3, 1.3, 1.3])))
        slide.addChild(SceneGraph.Node(label: "Ground", shape: .box(width: 8, height: 0.1, length: 4), material: concrete, transform: .init(translation: [0, -0.05, 0])))
        slide.addChild(SceneGraph.Node(label: "Step", shape: .box(width: 1.6, height: 0.5, length: 4), material: concrete, transform: .init(translation: [0.8, 0.25, 0])))
        slide.addChild(SceneGraph.Node(label: "Barrel", shape: .cylinder(radius: 0.4, height: 1.2), material: BlinnPhongSceneMaterial.plastic([0.7, 0.25, 0.15], shininess: 24), transform: .init(translation: [-2.6, 0.6, -0.6])))
        // Projectors point down (their -Z along -Y); x and y of the box are the decal's width and height.
        let lookDown = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
        let stripes = DecalMaterial(texture: Self.decalTexture(.stripes), color: [1, 0.85, 0.2, 1])
        slide.addChild(SceneGraph.Node(label: "Crossing", shape: .box(), material: stripes, transform: .init(translation: [-1.4, 0, 0.4], rotation: lookDown, scale: [1.8, 1.2, 0.6])))
        let footprints = DecalMaterial(texture: Self.decalTexture(.footprints), color: [0.15, 0.12, 0.1, 0.85])
        slide.addChild(SceneGraph.Node(label: "Footprints", shape: .box(), material: footprints, transform: .init(translation: [-2.6, 0, 0.9], rotation: lookDown * simd_quatf(angle: 0.4, axis: [0, 0, 1]), scale: [1, 1.6, 0.6])))
        // Tall enough to reach both the ground and the top of the step as it slides across the edge.
        let arrow = DecalMaterial(texture: Self.decalTexture(.arrow), color: [1, 1, 1, 1], maximumAngle: .pi / 3)
        movingDecal = slide.addChild(SceneGraph.Node(label: "Arrow", shape: .box(), material: arrow, transform: .init(translation: [0, 0.25, -0.6], rotation: lookDown, scale: [1.2, 1.2, 1.4])))
    }

    private func bloomSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 4, 5], intensity: 8, castsShadow: false)
        slide.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 8, height: 0.1, length: 4), material: BlinnPhongSceneMaterial(ambient: .color(0.05), diffuse: .color([0.15, 0.15, 0.18]), specular: .color(0.3), shininess: 64), transform: .init(translation: [0, -0.05, 0])))
        let neon = slide.addChild(SceneGraph.Node(label: "Neon", transform: .init(translation: [0, 1.8, 0])))
        neonShapes = neon
        // Emission far above 1: the HDR path keeps it, and the threshold picks it out for bloom.
        func glow(_ color: SIMD3<Float>) -> BlinnPhongSceneMaterial {
            BlinnPhongSceneMaterial(ambient: .color(0), diffuse: .color(0), specular: .color(0), shininess: 1, emission: .color(color * 6))
        }
        neon.addChild(SceneGraph.Node(label: "Ring", shape: .torus(ringRadius: 1.1, pipeRadius: 0.06), material: glow([1, 0.2, 0.6]), transform: .init(rotation: simd_quatf(angle: .pi / 2, axis: [1, 0, 0]))))
        neon.addChild(SceneGraph.Node(label: "Ring", shape: .torus(ringRadius: 0.8, pipeRadius: 0.05), material: glow([0.2, 0.7, 1]), transform: .init(rotation: simd_quatf(angle: .pi / 2, axis: [0, 0, 1]))))
        neon.addChild(SceneGraph.Node(label: "Core", shape: .sphere(radius: 0.25), material: glow([1, 0.85, 0.4])))
        // Dim shapes nearby stay below the threshold and do not glow.
        for side: Float in [-1, 1] {
            slide.addChild(SceneGraph.Node(label: "Dim Cube", shape: .box(width: 0.6, height: 0.6, length: 0.6), material: BlinnPhongSceneMaterial.plastic([0.6, 0.6, 0.65]), transform: .init(translation: [side * 2.8, 0.3, 0])))
        }
    }

    private func updateBloom() {
        let bloom = self[flag: "Bloom"] ? SceneGraph.PostProcessing.Bloom(threshold: self[value: "Bloom Threshold"], intensity: self[value: "Bloom Intensity"], radius: Int(self[value: "Bloom Radius"].rounded())) : nil
        let settings = SceneGraph.PostProcessing(bloom: bloom)
        if sceneGraph.postProcessing != settings {
            sceneGraph.postProcessing = settings
        }
    }

    private func shadowSettingsSlide(_ slide: SceneGraph.Node) {
        // A low sun from the side, so every post casts a long shadow across the street.
        cascadeSun = slide.addChild(SceneGraph.Node(label: "Sun", transform: Transform3D(position: [6, 4, 2], lookingAt: [0, 0, -2]), content: .light(Light(type: .directional, color: [1, 0.92, 0.8], intensity: 2))))
        addLight(to: slide, at: [-3, 4, 6], color: [0.45, 0.55, 0.8], intensity: 10, castsShadow: false)
        let ground = BlinnPhongSceneMaterial(ambient: .color(0.25), diffuse: .color([0.55, 0.55, 0.5]), specular: .color(0.02), shininess: 8)
        // A long street running away from the camera: near posts need sharp shadows, far ones cover a lot of ground.
        slide.addChild(SceneGraph.Node(label: "Street", shape: .box(width: 6, height: 0.1, length: 60), material: ground, transform: .init(translation: [0, -0.05, -27])))
        let post = BlinnPhongSceneMaterial.plastic([0.75, 0.35, 0.25], shininess: 16)
        for row in 0..<15 {
            for side: Float in [-1.6, 1.6] {
                slide.addChild(SceneGraph.Node(label: "Post", shape: .box(width: 0.12, height: 1.4, length: 0.12), material: post, transform: .init(translation: [side, 0.7, 2 - Float(row) * 4])))
            }
        }
        // Thin rails, whose shadows show the detail a coarse map loses.
        for side: Float in [-1.6, 1.6] {
            slide.addChild(SceneGraph.Node(label: "Rail", shape: .box(width: 0.05, height: 0.05, length: 60), material: post, transform: .init(translation: [side, 1.2, -27])))
        }
        updateCascadeSun()
    }

    private func updateCascadeSun() {
        guard let cascadeSun, case var .light(light) = cascadeSun.content else {
            return
        }
        let settings = Light.ShadowSettings(cascadeCount: self[flag: "Cascades"] ? Int(self[value: "Cascade Count"].rounded()) : 1, resolutionScale: self[value: "Sun Resolution"])
        if light.shadowSettings != settings {
            light.shadowSettings = settings
            cascadeSun.content = .light(light)
        }
    }

    private func stochasticSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 5, 6], intensity: 60, castsShadow: false)
        cardClusters = []
        cardMaterials = []
        let colors: [SIMD3<Float>] = [[0.95, 0.3, 0.3], [0.3, 0.85, 0.4], [0.3, 0.5, 0.95], [0.95, 0.8, 0.3]]
        for (index, stochastic) in [false, true].enumerated() {
            let x: Float = index == 0 ? -1.8 : 1.8
            let cluster = slide.addChild(SceneGraph.Node(label: stochastic ? "Stochastic Cards" : "Sorted Cards", transform: .init(translation: [x, 1.6, 0])))
            // Four double-sided cards crossing at the middle, every 45 degrees, so each cuts through the others.
            for (card, color) in colors.enumerated() {
                let material = PBRSceneMaterial(baseColor: color, opacity: 0.5, roughness: 0.6)
                // Double-sided, so the cards show from both sides as they turn.
                let base = material.pbrMaterial
                material.pbrMaterial = PBRMaterial(uniforms: base.uniforms, doubleSided: true, renderState: PBRRenderState(blendMode: stochastic ? .stochastic : nil), textureBindings: base.textureBindings)
                cardMaterials.append(material)
                let angle = Float(card) * .pi / 4
                cluster.addChild(SceneGraph.Node(label: "Card", shape: .plane(width: 2, height: 2), material: material, transform: .init(rotation: simd_quatf(angle: angle, axis: [0, 1, 0]))))
            }
            cardClusters.append(cluster)
            addTitle(stochastic ? "Stochastic" : "Sorted", size: 0.35, y: 0.2, to: slide).transform.translation.x = x
        }
        updateCards(time: 0)
    }

    private func updateCards(time: Float) {
        for (index, cluster) in cardClusters.enumerated() {
            let rotation = simd_quatf(angle: 0.3, axis: [1, 0, 0]) * simd_quatf(angle: time * 0.4 * self[value: "Card Spin"] + Float(index) * 0.1, axis: [0, 1, 0])
            cluster.transform = .init(translation: cluster.transform.translation, rotation: rotation)
        }
        let opacity = self[value: "Card Opacity"]
        for material in cardMaterials where material.uniforms.baseColorFactor.w != opacity {
            var uniforms = material.uniforms
            uniforms.baseColorFactor.w = opacity
            material.uniforms = uniforms
        }
    }

    private func subsurfaceSlide(_ slide: SceneGraph.Node) {
        // One light from the side, so half of each head is past the terminator.
        subsurfaceLight = slide.addChild(SceneGraph.Node(label: "Key Light", content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 3, castsShadow: false))))
        subsurfaceMaterials = []
        for (index, scatters) in [false, true].enumerated() {
            let material = PBRSceneMaterial(baseColor: [0.85, 0.65, 0.55], roughness: 0.55)
            if scatters {
                subsurfaceMaterials.append(material)
            }
            let x: Float = index == 0 ? -1.6 : 1.6
            // A simple head: a sphere with a nose and two ears, so the soft edge shows on curved shapes.
            let head = slide.addChild(SceneGraph.Node(label: scatters ? "Subsurface" : "Plain", shape: .sphere(radius: 1), material: material, transform: .init(translation: [x, 1.6, 0])))
            head.addChild(SceneGraph.Node(label: "Nose", shape: .sphere(radius: 0.22), material: material, transform: .init(translation: [0, -0.05, 0.95])))
            for side: Float in [-1, 1] {
                head.addChild(SceneGraph.Node(label: "Ear", shape: .sphere(radius: 0.25), material: material, transform: .init(translation: [side * 0.98, 0, 0], scale: [0.5, 1, 0.8])))
            }
            addTitle(scatters ? "Subsurface" : "Plain", size: 0.35, y: 0.2, to: slide).transform.translation.x = x
        }
        updateSubsurface(time: 0)
    }

    private func updateSubsurface(time: Float) {
        // From the right and a little behind, swinging slowly, so the terminator crosses the faces.
        let angle = -0.35 + 0.45 * sin(time * 0.4 * self[value: "Subsurface Light Speed"])
        subsurfaceLight?.transform = Transform3D(position: [cos(angle) * 6, 1.8, sin(angle) * 6], lookingAt: [0, 1.6, 0])
        for material in subsurfaceMaterials {
            var uniforms = material.uniforms
            let strength = self[value: "Subsurface Strength"]
            let radius = self[value: "Subsurface Radius"]
            guard uniforms.subsurfaceStrength != strength || uniforms.subsurfaceRadius != radius || uniforms.subsurfaceColor != [1, 0.35, 0.25] else {
                continue
            }
            uniforms.subsurfaceColor = [1, 0.35, 0.25]
            uniforms.subsurfaceStrength = strength
            uniforms.subsurfaceRadius = radius
            material.uniforms = uniforms
        }
    }

    private func mirrorsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [3, 5, 4], intensity: 60, castsShadow: false)
        addLight(to: slide, at: [-4, 3, 2], color: [0.5, 0.6, 1], intensity: 25, castsShadow: false)
        // A plane faces +Z; turned to face up, it is the floor. Tilted a little toward the camera.
        let stage = slide.addChild(SceneGraph.Node(label: "Stage", transform: .init(translation: [0, 0.3, 0], rotation: simd_quatf(angle: 0.25, axis: [1, 0, 0]))))
        let floor = stage.addChild(SceneGraph.Node(label: "Mirror Floor", shape: .plane(width: 8, height: 5), material: PBRSceneMaterial(baseColor: [0.45, 0.47, 0.5], metallic: 0.6, roughness: 0.05), transform: .init(rotation: simd_quatf(angle: -.pi / 2, axis: [1, 0, 0]))))
        floor.planarReflector = SceneGraph.PlanarReflector(resolutionScale: 0.5)
        mirrorFloor = floor
        let shapes: [(SceneGraph.Shape, SIMD3<Float>)] = [
            (.sphere(radius: 0.45), [0.95, 0.35, 0.25]), (.box(width: 0.7, height: 0.7, length: 0.7), [0.3, 0.75, 0.4]),
            (.torus(ringRadius: 0.4, pipeRadius: 0.14), [0.95, 0.8, 0.3]), (.cone(bottomRadius: 0.4, height: 0.9), [0.35, 0.5, 0.95])
        ]
        mirrorShapes = shapes.map { shape, color in
            stage.addChild(SceneGraph.Node(label: "Shape", shape: shape, material: PBRSceneMaterial(baseColor: color, roughness: 0.4)))
        }
        updateMirrors(time: 0)
    }

    private func updateMirrors(time: Float) {
        guard let mirrorFloor else {
            return
        }
        for (index, shape) in mirrorShapes.enumerated() {
            let angle = time * 0.5 * self[value: "Mirror Orbit Speed"] + Float(index) * .pi / 2
            shape.transform = .init(translation: [cos(angle) * 2.2, 0.75 + 0.25 * sin(time * 1.3 + Float(index)), sin(angle) * 1.3], rotation: simd_quatf(angle: time + Float(index), axis: simd_normalize([0.3, 1, 0.2])), scale: [1.4, 1.4, 1.4])
        }
        let reflects = self[flag: "Reflect"]
        if (mirrorFloor.planarReflector != nil) != reflects {
            mirrorFloor.planarReflector = reflects ? SceneGraph.PlanarReflector(resolutionScale: 0.5) : nil
        }
        if case let .mesh(mesh, materials, castsShadow, receivesShadow) = mirrorFloor.content, let material = materials.first as? PBRSceneMaterial {
            let roughness = self[value: "Floor Roughness"]
            if material.uniforms.roughnessFactor != roughness {
                var uniforms = material.uniforms
                uniforms.roughnessFactor = roughness
                material.uniforms = uniforms
                mirrorFloor.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        }
    }

    private func updateDecals(time: Float) {
        guard let movingDecal else {
            return
        }
        if self[flag: "Move Decal"] {
            movingDecal.transform.translation.x = sin(time * 0.6) * 1.4
        }
        if case let .mesh(mesh, materials, castsShadow, receivesShadow) = movingDecal.content, var material = materials.first as? DecalMaterial {
            let angle = self[value: "Maximum Angle"] * .pi / 180
            if material.maximumAngle != angle {
                material.maximumAngle = angle
                movingDecal.content = .mesh(mesh, materials: [material], castsShadow: castsShadow, receivesShadow: receivesShadow)
            }
        }
    }

    enum DecalPattern {
        case arrow, stripes, footprints
    }

    // A small white-on-clear image for a decal, drawn once per pattern.
    static func decalTexture(_ pattern: DecalPattern) -> MTLTexture? {
        let size = 256
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        let unit = CGFloat(size)
        switch pattern {
        case .arrow:
            let path = CGMutablePath()
            path.addLines(between: [CGPoint(x: 0.4, y: 0.1), CGPoint(x: 0.6, y: 0.1), CGPoint(x: 0.6, y: 0.55), CGPoint(x: 0.8, y: 0.55), CGPoint(x: 0.5, y: 0.9), CGPoint(x: 0.2, y: 0.55), CGPoint(x: 0.4, y: 0.55)].map { CGPoint(x: $0.x * unit, y: $0.y * unit) })
            path.closeSubpath()
            context.addPath(path)
            context.fillPath()
        case .stripes:
            for stripe in 0..<5 {
                context.fill(CGRect(x: (0.05 + CGFloat(stripe) * 0.19) * unit, y: 0.05 * unit, width: 0.11 * unit, height: 0.9 * unit))
            }
        case .footprints:
            for step in 0..<4 {
                let x = step.isMultiple(of: 2) ? 0.3 : 0.55
                let y = 0.08 + CGFloat(step) * 0.22
                context.fillEllipse(in: CGRect(x: x * unit, y: y * unit, width: 0.15 * unit, height: 0.12 * unit))
                context.fillEllipse(in: CGRect(x: (x + 0.03) * unit, y: (y + 0.13) * unit, width: 0.09 * unit, height: 0.06 * unit))
            }
        }
        guard let image = context.makeImage() else {
            return nil
        }
        return try? MTKTextureLoader(device: demoDevice).newTexture(cgImage: image, options: [.SRGB: true, .generateMipmaps: true, .textureStorageMode: MTLStorageMode.private.rawValue])
    }

    private func fogSlide(_ slide: SceneGraph.Node) {
        // Low and behind the pillars, shining toward the camera, so forward scattering shows the shafts between them.
        slide.addChild(SceneGraph.Node(label: "Moon", transform: Transform3D(position: [-6, 6, -30], lookingAt: [0, 0, -8]), content: .light(Light(type: .directional, color: [0.8, 0.85, 1], intensity: 1.2))))
        // A dim fill from the camera side, so the pillars' near faces are not black. Every light scatters in the
        // volumetric fog, so it stays faint.
        addLight(to: slide, at: [0, 4, 6], color: [0.4, 0.45, 0.6], intensity: 2, castsShadow: false)
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

    static var materialXURL: URL? {
        Bundle.module.url(forResource: "Materials", withExtension: "mtlx", subdirectory: "DemoAssets")
    }

    // A row of spheres with the materials of a MaterialX file, one per shader kind (#618, #622).
    private func materialXSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 5, 6], intensity: 80)
        addLight(to: slide, at: [-6, 2, 4], color: [0.6, 0.7, 1], intensity: 30)
        guard let url = Self.materialXURL,
              let document = try? MaterialXDocument(url: url, device: demoDevice)
        else {
            return
        }
        // Gold, car paint, jade, in the file's order.
        for (index, material) in document.materials.enumerated() {
            let position = SIMD3<Float>(Float(index) * 3 - Float(document.materials.count - 1) * 1.5, 1.4, 0)
            let sphere = slide.addChild(SceneGraph.Node(label: "MaterialX \(material.name)", shape: .sphere(radius: 1), material: material.material, transform: .init(translation: position)))
            sphere.run(.repeatForever(.rotate(by: .pi * 2, around: [0, 1, 0], duration: 9)))
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
        // New dice need the slide's light bit, as in tagMorePhysicsBodies (#624).
        if let index = Self.titles.firstIndex(of: "Physics"), slides.indices.contains(index) {
            Self.isolateLights(of: physicsDice, index: index)
        }
    }

    // A floor of pillars under a swarm of colored point lights (#611), like ManyLightsDemo. The lights stay near the
    // floor and reach only a little way, so clustering lets each pixel shade a handful of them.
    private func manyLightsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 4], color: [0.5, 0.6, 1], intensity: 4)
        // Tilted toward the camera, like the dice tray, so the floor shows from the slides' eye height.
        let stage = slide.addChild(SceneGraph.Node(label: "Stage", transform: .init(translation: [0, 0.4, 0], rotation: simd_quatf(angle: 0.55, axis: [1, 0, 0]))))
        let floorColor: SIMD3<Float> = [0.5, 0.5, 0.55]
        stage.addChild(SceneGraph.Node(label: "Floor", shape: .box(width: 14, height: 0.1, length: 7), material: BlinnPhongSceneMaterial.plastic(floorColor, shininess: 16), transform: .init(translation: [0, -0.05, -1])))
        for x in stride(from: -6, through: 6, by: 1.5) {
            for z in stride(from: -4, through: 2, by: 1.5) {
                stage.addChild(SceneGraph.Node(label: "Pillar", shape: .cylinder(radius: 0.18, height: 1.2), material: BlinnPhongSceneMaterial.plastic([0.85, 0.85, 0.85], shininess: 48), transform: .init(translation: [Float(x), 0.6, Float(z)])))
            }
        }
        let swarm = stage.addChild(SceneGraph.Node(label: "Swarm", transform: .init(translation: [0, 0, -1])))
        swarmLights = (0 ..< Self.maximumSwarmLights).map { index in
            // Spread over an ellipse by the golden angle; hues around the color wheel.
            let fraction = Float(index) / Float(Self.maximumSwarmLights)
            let hue = (Float(index) * 0.618034).truncatingRemainder(dividingBy: 1)
            let color = SIMD3<Float>((0 ..< 3).map { channel in 0.5 + 0.5 * cos(2 * .pi * (hue + Float(channel) / 3)) })
            let node = swarm.addChild(SceneGraph.Node(label: "Swarm Light", content: .light(Light(type: .point, color: color, intensity: 2, range: 1.6))))
            return (node, Float(index) * 2.399963, 0.3 + sqrt(fraction) * 6.5, 0.15 + fraction * 0.35)
        }
    }

    private func updateSwarm(time: Float) {
        let count = Int(self[value: "Swarm Size"].rounded())
        let range = self[value: "Swarm Range"]
        let speed = self[value: "Swarm Speed"]
        for (index, light) in swarmLights.enumerated() {
            let isOn = index < count
            if light.node.isVisible != isOn {
                light.node.isVisible = isOn
            }
            guard isOn else {
                continue
            }
            let angle = light.phase + time * light.speed * speed
            let wobble = sin(time * 1.3 + light.phase) * 0.3
            // An ellipse twice as wide as deep, to fill the floor.
            light.node.transform = Transform3D(translation: [cos(angle) * (light.radius + wobble), 0.35 + 0.25 * sin(time * 2 + light.phase), sin(angle) * (light.radius + wobble) * 0.45])
            if case var .light(settings) = light.node.content, settings.range != range {
                settings.range = range
                light.node.content = .light(settings)
            }
        }
    }

    // A chain on ball joints, crates floating in a tank under a trigger ring, and a character walking over a step that
    // flashes when a ball hits it (#610). Left to right: joints, buoyancy and triggers, contacts and the character.
    private func morePhysicsSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [0, 6, 6], intensity: 80)
        addLight(to: slide, at: [-6, 3, 4], color: [0.6, 0.7, 1], intensity: 25)
        let origin = slide.transform.translation
        let stone = BlinnPhongSceneMaterial.plastic([0.35, 0.36, 0.4], shininess: 8)
        func addStatic(_ label: String, size: SIMD3<Float>, at position: SIMD3<Float>, material: any SceneMaterial = stone) -> SceneGraph.Node {
            let node = slide.addChild(SceneGraph.Node(label: label, shape: .box(width: size.x, height: size.y, length: size.z), material: material, transform: .init(translation: position)))
            node.physicsBody = .init(type: .static, shape: .box(size: size))
            return node
        }
        _ = addStatic("Floor", size: [13, 0.2, 3], at: [0, -0.1, 0])

        // The tank: four glass-like walls around a fluid region.
        let tankCenter: SIMD3<Float> = [-1, 0, 0]
        let tankSize: SIMD3<Float> = [2.4, 1.3, 1.6]
        let wall = BlinnPhongSceneMaterial.plastic([0.6, 0.7, 0.8], shininess: 64)
        for side: Float in [-1, 1] {
            addStatic("Tank Wall", size: [0.1, tankSize.y, tankSize.z], at: tankCenter + [side * tankSize.x / 2, tankSize.y / 2, 0], material: wall).opacity = 0.25
            addStatic("Tank Wall", size: [tankSize.x, tankSize.y, 0.1], at: tankCenter + [0, tankSize.y / 2, side * tankSize.z / 2], material: wall).opacity = 0.25
        }
        let waterHeight: Float = 1
        let water = slide.addChild(SceneGraph.Node(label: "Water", shape: .box(width: tankSize.x - 0.1, height: waterHeight, length: tankSize.z - 0.1), material: BlinnPhongSceneMaterial.plastic([0.15, 0.45, 0.9], shininess: 64), transform: .init(translation: tankCenter + [0, waterHeight / 2, 0])))
        water.opacity = 0.3
        tankRegion = BoundingBox3D(min: origin + tankCenter + [-tankSize.x / 2, 0, -tankSize.z / 2], max: origin + tankCenter + [tankSize.x / 2, waterHeight, tankSize.z / 2])
        let ring = slide.addChild(SceneGraph.Node(label: "Trigger Ring", shape: .torus(ringRadius: 0.9, pipeRadius: 0.05), material: Self.glowMaterial([0.3, 0.9, 0.6], glow: 0), transform: .init(translation: tankCenter + [0, 2.2, 0])))
        ring.physicsBody = .init(type: .static, shape: .cylinder(height: 0.2, radius: 0.9), isTrigger: true)
        triggerRing = ring

        // The step the character climbs and the ball hits.
        let step = addStatic("Impact Step", size: [0.8, 0.3, 1.2], at: [3.5, 0.15, 0], material: Self.glowMaterial([1, 0.55, 0.2], glow: 0))
        impactStep = step
        walkerRange = (origin.x + 2)...(origin.x + 5.5)
        morePhysicsBodies = slide.addChild(SceneGraph.Node(label: "More Physics Bodies"))
    }

    private static func glowMaterial(_ color: SIMD3<Float>, glow: Float) -> BlinnPhongSceneMaterial {
        BlinnPhongSceneMaterial(ambient: .color(color * 0.1), diffuse: .color(color * 0.6), specular: .color(0.3), shininess: 32, emission: .color(color * min(glow, 1.5)))
    }

    private static func setGlow(of node: SceneGraph.Node?, color: SIMD3<Float>, glow: Float) {
        guard let node, case let .mesh(mesh, _, castsShadow, receivesShadow) = node.content else {
            return
        }
        node.content = .mesh(mesh, materials: [glowMaterial(color, glow: glow)], castsShadow: castsShadow, receivesShadow: receivesShadow)
    }

    // Rebuilds the chain, crates, ball and character. Hidden slides drop out of the physics world, so this runs on
    // arrival.
    private func resetMorePhysics() {
        guard let morePhysicsBodies, let physics, let slide = morePhysicsBodies.parent else {
            return
        }
        physics.gravity = [0, -9.81, 0]
        if let tankRegion {
            physics.fluids = [.init(region: tankRegion, buoyancy: 1.6, linearDrag: 0.8, angularDrag: 0.1)]
        }
        sinceMorePhysicsReset = 0
        sinceBallDrop = 0
        morePhysicsBodies.removeAllChildren()
        removeWalker()
        let origin = slide.transform.translation

        // A chain of ball joints, the first held to the world.
        let anchor: SIMD3<Float> = [-4.5, 3.4, 0]
        let linkMaterial = BlinnPhongSceneMaterial.plastic([0.8, 0.8, 0.85], shininess: 96)
        var links: [SceneGraph.Node] = []
        for index in 0..<6 {
            let isBob = index == 5
            let radius: Float = isBob ? 0.3 : 0.14
            let link = morePhysicsBodies.addChild(SceneGraph.Node(label: isBob ? "Chain Bob" : "Chain Link", shape: .sphere(radius: radius), material: isBob ? BlinnPhongSceneMaterial.plastic([0.9, 0.35, 0.3], shininess: 64) : linkMaterial, transform: .init(translation: anchor - [0, Float(index + 1) * 0.4, 0])))
            link.physicsBody = .init(type: .dynamic, shape: .sphere(radius: radius), linearDamping: 0.01, angularDamping: 0.01, collisionBitMask: 0)
            links.append(link)
        }
        physics.sync()
        physics.addJoint(.ball(anchor: origin + anchor), between: nil, and: links[0])
        for (linkA, linkB) in zip(links, links.dropFirst()) {
            let midpoint = (linkA.transform.translation + linkB.transform.translation) / 2
            physics.addJoint(.ball(anchor: origin + midpoint), between: linkA, and: linkB)
        }
        if let bob = links.last {
            physics.setVelocity([5, 0, 1], of: bob)
        }

        // Crates dropped into the tank through the trigger ring. The red one only moves up and down.
        let crateColors: [SIMD3<Float>] = [[0.75, 0.55, 0.3], [0.9, 0.3, 0.25], [0.65, 0.5, 0.3]]
        for (index, color) in crateColors.enumerated() {
            let crate = morePhysicsBodies.addChild(SceneGraph.Node(label: "Crate", shape: .box(width: 0.45, height: 0.45, length: 0.45), material: BlinnPhongSceneMaterial.plastic(color, shininess: 16), transform: .init(translation: [-1.6 + Float(index) * 0.6, 3 + Float(index) * 0.8, Float(index - 1) * 0.2], rotation: simd_quatf(angle: Float(index) * 0.7, axis: simd_normalize([1, 1, 0])))))
            crate.physicsBody = .init(type: .dynamic, shape: .box(size: [0.45, 0.45, 0.45]), mass: 4, allowedMotion: index == 1 ? [.translationY] : .all)
        }
        dropBall()

        // The character: a capsule whose origin is at its feet.
        let walker = morePhysicsBodies.addChild(SceneGraph.Node(label: "Character", transform: .init(translation: [2.2, 0.05, 0.3])))
        walker.addChild(SceneGraph.Node(shape: .capsule(capRadius: 0.3, height: 1.4), material: BlinnPhongSceneMaterial.plastic([0.35, 0.6, 1], shininess: 48), transform: .init(translation: [0, 0.7, 0])))
        walker.addChild(SceneGraph.Node(label: "Visor", shape: .box(width: 0.2, height: 0.12, length: 0.4), material: BlinnPhongSceneMaterial.plastic([0.1, 0.1, 0.12], shininess: 96), transform: .init(translation: [0.24, 1.15, 0])))
        self.walker = walker
        walkerController = physics.addCharacter(for: walker, height: 1.4, radius: 0.3)
        walkerController?.desiredVelocity = [self[value: "Walk Speed"], 0, 0]
        tagMorePhysicsBodies()
    }

    private func dropBall() {
        bouncingBall?.removeFromParent()
        let ball = morePhysicsBodies?.addChild(SceneGraph.Node(label: "Bouncing Ball", shape: .sphere(radius: 0.2), material: BlinnPhongSceneMaterial.plastic([1, 0.85, 0.3], shininess: 96), transform: .init(translation: [3.5, 3.2, -0.3])))
        ball?.physicsBody = .init(type: .dynamic, shape: .sphere(radius: 0.2), restitution: 0.75)
        bouncingBall = ball
        sinceBallDrop = 0
        tagMorePhysicsBodies()
    }

    // New nodes have the default category mask, which the slide's lights (isolated to the slide's bit) do not light,
    // so rebuilt bodies drew black (#624). Gives them the slide's bit.
    private func tagMorePhysicsBodies() {
        guard let morePhysicsBodies, let index = Self.titles.firstIndex(of: "More Physics"), slides.indices.contains(index) else {
            return
        }
        Self.isolateLights(of: morePhysicsBodies, index: index)
    }

    private func removeWalker() {
        if let walkerController {
            physics?.removeCharacter(walkerController)
        }
        walkerController = nil
    }

    private func morePhysicsContact(_ contact: SceneGraphPhysicsWorld.Contact) {
        guard contact.phase == .began else {
            return
        }
        let nodes = [contact.nodeA, contact.nodeB]
        if let triggerRing, nodes.contains(where: { $0 === triggerRing }) {
            triggerGlow = 1.5
        }
        if let impactStep, let bouncingBall, nodes.contains(where: { $0 === impactStep }), nodes.contains(where: { $0 === bouncingBall }) {
            // Harder hits flash brighter.
            impactGlow = max(impactGlow, contact.impulse / impactForFullGlow)
        }
    }

    private func updateMorePhysics(deltaTime: Float) {
        sinceMorePhysicsReset += deltaTime
        sinceBallDrop += deltaTime
        if sinceMorePhysicsReset > 12 {
            resetMorePhysics()
        } else if sinceBallDrop > 3 {
            dropBall()
        }
        // Turns around at the ends of its walk, facing the way it walks.
        if let walker, let walkerController {
            let speed = self[value: "Walk Speed"]
            var direction: Float = walkerController.desiredVelocity.x < 0 ? -1 : 1
            let x = walker.worldTransform.columns.3.x
            if x > walkerRange.upperBound {
                direction = -1
            } else if x < walkerRange.lowerBound {
                direction = 1
            }
            walkerController.desiredVelocity = [direction * speed, 0, 0]
            walker.transform.rotation = Rotation3D(simd_quatf(angle: direction > 0 ? 0 : .pi, axis: [0, 1, 0]))
        }
        physics?.step(deltaTime: min(deltaTime, 1.0 / 30.0), collisionSteps: 2)
        triggerGlow = max(triggerGlow - deltaTime * 2, 0)
        impactGlow = max(impactGlow - deltaTime * 3, 0)
        Self.setGlow(of: triggerRing, color: [0.3, 0.9, 0.6], glow: triggerGlow)
        Self.setGlow(of: impactStep, color: [1, 0.55, 0.2], glow: impactGlow)
        if let physicsDebugNode, let physics {
            if self[flag: "Physics Debug"] {
                physics.updateDebugNode(physicsDebugNode, material: debugDrawMaterial, device: demoDevice)
            } else {
                physicsDebugNode.content = .empty
            }
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
        for (mesh, material, position) in pieces {
            let node = slide.addChild(SceneGraph.Node(label: material.pbrMaterial.name, transform: .init(translation: position), content: .mesh(mesh, material: material)))
            pbrExtensionBases.append((node, material.pbrMaterial))
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
        instancedCrateGroups = materials.indices.map { materialIndex in
            let indices = crates.indices.filter { ($0 / size + $0 % size) % materials.count == materialIndex }
            let node = grid.addChild(SceneGraph.Node(label: "Instanced Crates", content: .instancedMesh(box, material: materials[materialIndex], transforms: indices.map { crates[$0].transform.matrix })))
            node.isVisible = false
            return (node, box, materials[materialIndex], indices)
        }
        crateCountLabel = slide.addChild(SceneGraph.Node(label: "Crate Count"))
        setCrateCount(size)
    }

    // Sets each instanced node's transforms: the crates inside the Crate Grid size, waving at `time` if given. The
    // crate nodes are hidden; their transforms are only the rest positions here.
    private func updateInstancedCrates(time: Float?) {
        let full = Self.crateGridSize
        let size = Int(self[value: "Crate Grid"].rounded())
        for group in instancedCrateGroups {
            let transforms = group.crateIndices.filter { $0 / full < size && $0 % full < size }.map { index in
                var transform = crates[index].transform
                if let time {
                    let position = transform.translation
                    transform.translation.y = sin(time * 2 + (position.x + position.z) * 0.8) * 0.4
                }
                return transform.matrix
            }
            group.node.content = .instancedMesh(group.mesh, materials: [group.material], transforms: transforms)
        }
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

    // Three shapes, each with its own transform gizmo: move the sphere, rotate the box, scale the cone. Clicking a shape
    // selects it, outlines it and makes its gizmo the one to drag.
    private func gizmosSlide(_ slide: SceneGraph.Node) {
        addLight(to: slide, at: [2, 6, 5], intensity: 60)
        // A spot light, so the editor gizmos show a cone icon as well as the point light's.
        slide.addChild(SceneGraph.Node(label: "Spot", transform: Transform3D(position: [-4.5, 3, 1.5], lookingAt: [-3.2, 0.9, 0]), content: .light(.spot(color: [1, 0.9, 0.7], intensity: 15, range: 10))))
        let shapes: [(String, SceneGraph.Shape, SIMD3<Float>, TransformGizmo.Mode, Transform3D)] = [
            ("Sphere", .sphere(radius: 0.6), [0.4, 0.75, 0.45], .translate, .init(translation: [-3.2, 0.9, 0])),
            ("Box", .box(width: 1.2, height: 1.2, length: 1.2), [0.95, 0.55, 0.3], .rotate, .init(translation: [0, 0.9, 0], rotation: simd_quatf(angle: 0.5, axis: [0, 1, 0]))),
            ("Cone", .cone(topRadius: 0, bottomRadius: 0.6, height: 1.3), [0.4, 0.55, 0.95], .scale, .init(translation: [3.2, 0.9, 0]))
        ]
        gizmoObjects = shapes.map { label, shape, color, mode, rest in
            let node = slide.addChild(SceneGraph.Node(label: label, shape: shape, material: BlinnPhongSceneMaterial.plastic(color, shininess: 32), transform: rest))
            return (node, mode, rest)
        }
        gizmoTarget = gizmoObjects[1].node
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
