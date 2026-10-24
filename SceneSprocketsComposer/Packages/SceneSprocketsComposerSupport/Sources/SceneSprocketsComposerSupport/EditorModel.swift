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
        didSet { updateGizmoTarget() }
    }
    // Locked nodes and their descendants cannot be picked in the viewport, moved or edited (#192). Editor state, saved
    // in editor.json.
    private(set) var lockedNodes: Set<SceneGraph.Node.ID> = [] {
        didSet { updateGizmoTarget() }
    }
    public var gizmoMode = TransformGizmo.Mode.translate {
        didSet { gizmo.mode = gizmoMode }
    }
    public var gizmoSpace = TransformGizmo.Space.world {
        didSet { gizmo.space = gizmoSpace }
    }
    var camera = EditorCamera()
    var renderSettings = RenderSettings()
    var isInspectorPresented = true
    // From the app's Gizmo Size setting (#189).
    var gizmoSize = GizmoSize.small {
        didSet { gizmo.worldSize = baseGizmoWorldSize * gizmoSize.scale }
    }
    @ObservationIgnored private var baseGizmoWorldSize: Float = 1
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
        // Scales with the camera like the scene (#171), sized from the scene so it suits small and large scenes.
        baseGizmoWorldSize = sceneGraph.bounds.map { max(simd_distance($0.min, $0.max) * 0.15, 0.01) } ?? 1
        gizmo.worldSize = baseGizmoWorldSize
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

    // The root cannot be deleted.
    var canDeleteSelection: Bool {
        guard let node = selectedNode else {
            return false
        }
        return node.parent != nil && !isLocked(node)
    }

    // Locked itself or through an ancestor.
    func isLocked(_ node: SceneGraph.Node) -> Bool {
        var current: SceneGraph.Node? = node
        while let candidate = current {
            if lockedNodes.contains(candidate.id) {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    func setLocked(_ isLocked: Bool, _ node: SceneGraph.Node) {
        guard lockedNodes.contains(node.id) != isLocked else {
            return
        }
        if isLocked {
            lockedNodes.insert(node.id)
        } else {
            lockedNodes.remove(node.id)
        }
        undoManager?.registerUndo(withTarget: self) { model in
            model.setLocked(!isLocked, node)
        }
        undoManager?.setActionName(isLocked ? "Lock" : "Unlock")
    }

    // From editor.json; not undoable.
    func restoreLockedNodes(_ ids: Set<SceneGraph.Node.ID>) {
        lockedNodes = ids
    }

    // Viewport picks skip locked nodes, which leaves nothing selected.
    func pick(_ node: SceneGraph.Node?) {
        selection = node.flatMap { isLocked($0) ? nil : $0.id }
    }

    private func updateGizmoTarget() {
        gizmo.target = selectedNode.flatMap { isLocked($0) ? nil : $0 }
    }

    func deleteSelection() {
        guard canDeleteSelection, let node = selectedNode else {
            return
        }
        delete(node)
    }

    func delete(_ node: SceneGraph.Node) {
        guard let parent = node.parent, let index = parent.children.firstIndex(where: { $0 === node }) else {
            return
        }
        node.removeFromParent()
        if selection == node.id {
            selection = nil
        }
        undoManager?.registerUndo(withTarget: self) { model in
            model.insert(node, into: parent, at: index, actionName: "Delete")
        }
        undoManager?.setActionName("Delete")
    }

    private func insert(_ node: SceneGraph.Node, into parent: SceneGraph.Node, at index: Int, actionName: String) {
        parent.insertChild(node, at: min(index, parent.children.count))
        selection = node.id
        undoManager?.registerUndo(withTarget: self) { model in
            model.delete(node)
        }
        undoManager?.setActionName(actionName)
    }

    // Adds under the root and selects it.
    func addShape(_ shape: SceneGraph.Shape, label: String) {
        let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.8), specular: .color(0.5), shininess: 32)
        let node = SceneGraph.Node(parent: nil, label: label, shape: shape, material: material, device: systemDefaultDevice())
        insert(node, into: sceneGraph.root, at: sceneGraph.root.children.count, actionName: "Add \(label)")
    }

    // Directional and spot lights shine along -Z, so they start above and aimed at the origin.
    func addLight(_ type: Light.LightType) {
        let label = Self.label(for: type)
        var transform = LookAt(position: [3, 5, 3], target: .zero, up: [0, 1, 0]).cameraMatrix
        if type == .point {
            transform = matrix_identity_float4x4
            transform.columns.3 = [0, 3, 0, 1]
        }
        let range: Float = type == .point ? 10 : .infinity
        let node = SceneGraph.Node(label: label, transform: transform, content: .light(Light(type: type, range: range)))
        insert(node, into: sceneGraph.root, at: sceneGraph.root.children.count, actionName: "Add \(label)")
    }

    // Placed at the editor camera, so it sees what the user sees.
    func addCamera() {
        let node = SceneGraph.Node(label: "Camera", transform: camera.matrix, content: .camera(renderSettings.camera))
        insert(node, into: sceneGraph.root, at: sceneGraph.root.children.count, actionName: "Add Camera")
    }

    static func label(for type: Light.LightType) -> String {
        "\(type.rawValue.prefix(1).uppercased())\(type.rawValue.dropFirst()) Light"
    }

    func setLabel(_ label: String?, of node: SceneGraph.Node) {
        let previous = node.label
        guard label != previous else {
            return
        }
        node.label = label
        undoManager?.registerUndo(withTarget: self) { model in
            model.setLabel(previous, of: node)
        }
        undoManager?.setActionName("Rename")
    }

    func setLight(_ light: Light, of node: SceneGraph.Node) {
        guard case .light(let previous) = node.content else {
            return
        }
        node.content = .light(light)
        transformRevision += 1
        undoManager?.registerUndo(withTarget: self) { model in
            model.setLight(previous, of: node)
        }
        undoManager?.setActionName("Light")
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
    static func empty() -> SceneGraph {
        SceneGraph(root: Self.Node(label: "Root"))
    }
}
