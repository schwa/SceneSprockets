import Foundation
import GeometryLite3D
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsGLTF
import MetalSprocketsPBR
import MetalSprocketsSceneGraph
import MetalSprocketsSceneGraphGLTF
import MetalSprocketsSceneGraphModelIO
import MetalSprocketsSceneGraphPBR
import MetalSprocketsSceneGraphRenderer
import SwiftMesh
import simd

// An animated glTF fox (MetalSprocketsSceneGraphGLTF) on an OBJ pedestal (MetalSprocketsSceneGraphModelIO), lit and
// backed by the scene environment. Click to pick: the hit node is selected and a marker shows the hit point.
final class ImportedAssetsDemo: DemoScene {
    private static let backgrounds = ["Environment", "Blurred Environment", "Color"]
    private let clipNames: [String]
    private let clips: [SceneGraph.AnimationClip]
    private var player: SceneGraph.AnimationPlayer?
    private var playingClip = -1
    private let marker: SceneGraph.Node
    private let shadowRenderer = SceneGraphShadows()

    init() {
        let root = SceneGraph.Node(label: "Root")
        root.addChild(.camera(eye: [0, 2, 6], target: [0, 0.8, 0]))
        _ = SceneGraph.Node(parent: root, label: "Sun", transform: .camera(eye: [2, 4, 3], target: .zero), content: .light(Light(type: .directional, color: [1, 0.95, 0.9], intensity: 2)))

        var clipNames: [String] = []
        var clips: [SceneGraph.AnimationClip] = []
        do {
            let foxURL = try Self.resource("Fox", extension: "glb")
            let asset = try GLTFAsset(url: foxURL, device: demoDevice)
            let fox = try asset.makeSceneGraph(device: demoDevice)
            // The fox is about 100 units long.
            let holder = SceneGraph.Node(parent: root, label: "Fox", trs: .init(scale: [0.02, 0.02, 0.02]))
            for child in fox.sceneGraph.root.children {
                holder.addChild(child)
            }
            clips = fox.animations
            clipNames = fox.animations.enumerated().map { $1.name ?? "Clip \($0)" }

            let pedestal = try ModelIOSceneGraph(url: try Self.resource("Pedestal", extension: "obj"), device: demoDevice)
            pedestal.sceneGraph.root.label = "Pedestal"
            root.addChild(pedestal.sceneGraph.root)
        } catch {
            // The demo shows whatever loaded; a missing asset leaves an emptier scene.
        }
        self.clipNames = clipNames
        self.clips = clips

        let sphere = MetalMesh(mesh: .sphere(), device: demoDevice)
        let markerMaterial = (try? PBRSceneMaterial(device: demoDevice, baseColor: [1, 0.8, 0.1, 1], metallic: 0, roughness: 0.3)).map { $0 as any MetalSprocketsSceneGraph.Material } ?? BlinnPhongMaterial.plastic([1, 0.8, 0.1])
        marker = SceneGraph.Node(parent: root, label: "Pick Marker", trs: .init(scale: [0.05, 0.05, 0.05]), content: .mesh(sphere, material: markerMaterial))
        marker.isVisible = false

        let sceneGraph = SceneGraph(root: root)
        sceneGraph.environment = SceneGraph.Environment(background: .environment(), map: PBREnvironment.studio)
        super.init(
            sceneGraph: sceneGraph,
            renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer(device: demoDevice)],
            cameraMatrix: .camera(eye: [0, 2, 6], target: [0, 0.8, 0]),
            parameters: [
                .choice("Animation", clipNames.isEmpty ? ["None"] : clipNames, default: min(1, max(clipNames.count - 1, 0))),
                .slider("Speed", 0...2, default: 1),
                .choice("Background", Self.backgrounds),
                .slider("Environment Intensity", 0...3, default: 1),
                .slider("Environment Rotation", 0...(2 * .pi), default: 0),
                .toggle("Shadows", default: true),
                .slider("Shadow Intensity", 0...1, default: 0.6),
            ]
        )
    }

    private static func resource(_ name: String, extension fileExtension: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: fileExtension, subdirectory: "Resources") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).\(fileExtension)"])
        }
        return url
    }

    override func update(time: Float, deltaTime: Float) {
        let clipIndex = Int(self[value: "Animation"])
        if clipIndex != playingClip, clips.indices.contains(clipIndex) {
            playingClip = clipIndex
            player = SceneGraph.AnimationPlayer(clip: clips[clipIndex])
        }
        player?.speed = self[value: "Speed"]
        player?.advance(by: deltaTime)

        switch Int(self[value: "Background"]) {
        case 0: sceneGraph.environment.background = .environment()
        case 1: sceneGraph.environment.background = .environment(blur: 0.6)
        default: sceneGraph.environment.background = .color([0.08, 0.09, 0.12, 1])
        }
        sceneGraph.environment.intensity = self[value: "Environment Intensity"]
        sceneGraph.environment.rotation = self[value: "Environment Rotation"]
        if self[flag: "Shadows"] != (shadows != nil) {
            shadows = self[flag: "Shadows"] ? shadowRenderer : nil
        }
        shadows?.intensity = self[value: "Shadow Intensity"]
    }

    override func didPick(_ hit: SceneGraph.Hit?) {
        guard let hit else {
            marker.isVisible = false
            return
        }
        marker.trs.translation = hit.position + hit.normal * 0.02
        marker.isVisible = true
    }
}
