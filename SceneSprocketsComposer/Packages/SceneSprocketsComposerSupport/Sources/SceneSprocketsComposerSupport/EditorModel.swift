import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsPBR
import Observation
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsGizmos
import SceneSprocketsPBR
import simd

@MainActor
@Observable
public final class EditorModel {
    public let sceneGraph: SceneGraph
    public var selection: SceneGraph.Node.ID? {
        didSet { gizmo.target = selectedNode }
    }
    public var gizmoMode = TransformGizmo.Mode.translate {
        didSet { gizmo.mode = gizmoMode }
    }
    public var gizmoSpace = TransformGizmo.Space.world {
        didSet { gizmo.space = gizmoSpace }
    }
    var camera = OrbitCamera()
    var renderSettings = RenderSettings()
    // Bumped while the gizmo drags, so views that show transforms refresh. Nodes are not observable (SceneSprockets #155).
    public private(set) var transformRevision = 0
    // Set by the view from the document's environment; registering undo marks the document edited.
    @ObservationIgnored public weak var undoManager: UndoManager?
    // PBRMaterialRenderer caches GPU state, so keep one instance per editor.
    @ObservationIgnored public let renderers: [any SceneGraphMaterialRenderer]
    @ObservationIgnored public let gizmo = TransformGizmo()
    // Keeps its textures between frames.
    @ObservationIgnored let selectionOutline = SelectionOutline()
    @ObservationIgnored private var transformBeforeDrag: SceneGraph.LocalTransform?

    public init(sceneGraph: SceneGraph, device: (any MTLDevice)? = nil) {
        self.sceneGraph = sceneGraph
        renderers = [BlinnPhongMaterialRenderer(), PBRMaterialRenderer(device: device ?? systemDefaultDevice())]
        frameAll()
        gizmo.onBegin = { [weak self] node in
            self?.transformBeforeDrag = node.localTransform
        }
        gizmo.onChange = { [weak self] _ in
            self?.transformRevision += 1
        }
        gizmo.onEnd = { [weak self] node in
            guard let self, let before = transformBeforeDrag else {
                return
            }
            transformBeforeDrag = nil
            setTransform(node.localTransform, of: node, undoTo: before)
        }
    }

    func frameAll() {
        if let bounds = sceneGraph.bounds {
            camera.frame(bounds, fieldOfView: renderSettings.fieldOfView)
        }
    }

    func frameSelection() {
        guard let node = selectedNode, let bounds = sceneGraph.worldBounds(of: node) else {
            frameAll()
            return
        }
        camera.frame(bounds, fieldOfView: renderSettings.fieldOfView)
    }

    // The scene graph is not observable, so views read the environment through here.
    var environment: SceneGraph.Environment {
        _ = environmentRevision
        return sceneGraph.environment
    }
    private var environmentRevision = 0

    // `actionName` groups undo: consecutive changes with the same name (a slider drag) still undo one by one.
    func setEnvironment(_ environment: SceneGraph.Environment, actionName: String) {
        let previous = sceneGraph.environment
        sceneGraph.environment = environment
        environmentRevision += 1
        undoManager?.registerUndo(withTarget: self) { model in
            model.setEnvironment(previous, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
    }

    func importEnvironmentImage(from url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var updated = sceneGraph.environment
        updated.map = try PBREnvironment(source: .equirectangular(url))
        if case .none = updated.background {
            updated.background = .environment()
        }
        setEnvironment(updated, actionName: "Environment Image")
    }

    // Reads `transformRevision`, so callers refresh while the gizmo drags.
    func localTRS(of node: SceneGraph.Node) -> Transform3D {
        _ = transformRevision
        return node.localTransform.trs
    }

    func setTransform(_ transform: SceneGraph.LocalTransform, of node: SceneGraph.Node, undoTo previous: SceneGraph.LocalTransform) {
        node.localTransform = transform
        transformRevision += 1
        undoManager?.registerUndo(withTarget: self) { model in
            model.setTransform(previous, of: node, undoTo: transform)
        }
        undoManager?.setActionName("Transform")
    }

    public var selectedNode: SceneGraph.Node? {
        guard let selection else {
            return nil
        }
        return sceneGraph.nodesWithWorldTransforms(includeHidden: true).first { $0.node.id == selection }?.node
    }
}

extension SceneGraph {
    // Content for new documents.
    static func starter(device: any MTLDevice) -> SceneGraph {
        let root = Self.Node(label: "Root")
        let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.8, 0.4, 0.3]), specular: .color(0.5), shininess: 32)
        let floorMaterial = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.6), specular: .color(0.1), shininess: 8)
        _ = Self.Node(parent: root, label: "Floor", shape: .box(width: 10, height: 0.1, length: 10), material: floorMaterial, device: device, trs: .init(translation: [0, -0.05, 0]))
        _ = Self.Node(parent: root, label: "Box", shape: .box(), material: material, device: device, trs: .init(translation: [0, 0.5, 0]))
        _ = Self.Node(parent: root, label: "Sun", trs: .init(rotation: simd_quatf(from: [0, 0, -1], to: simd_normalize([-3, -5, -4]))), content: .light(Light(type: .directional, intensity: 2)))
        return SceneGraph(root: root)
    }
}
