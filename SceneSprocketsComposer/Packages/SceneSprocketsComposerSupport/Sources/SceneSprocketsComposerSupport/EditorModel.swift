import Foundation
import GeometryLite3D
import Metal
import MetalSprocketsPBR
import Observation
import SwiftUI
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsGizmos
import SceneSprocketsPBR
import simd

@MainActor
@Observable
public final class EditorModel {
    public let sceneGraph: SceneGraph
    // The primary selected node: the inspector shows it and the gizmo moves it. Setting it selects only that node.
    public var selection: SceneGraph.Node.ID? {
        didSet {
            if !isSettingSelection {
                selectedIDs = selection.map { [$0] } ?? []
            }
            if selection != nil {
                editorItem = nil
            }
            updateGizmoTarget()
        }
    }
    // A selected editor row (#207): the default camera or default lighting, which are not scene nodes. Selecting one
    // clears the node selection, and selecting a node clears it.
    var editorItem: EditorItem? {
        didSet {
            if editorItem != nil, selection != nil {
                selection = nil
            }
        }
    }

    // Whether the default light is on and in effect: SceneView adds it only when the scene has no lights.
    var isDefaultLightingActive: Bool {
        _ = transformRevision
        return renderSettings.usesDefaultLighting && sceneGraph.lightNodes().isEmpty
    }
    // Every selected node, including `selection` (#201). Change it with select(_:primary:).
    public private(set) var selectedIDs: Set<SceneGraph.Node.ID> = []
    @ObservationIgnored private var isSettingSelection = false

    // Selects `ids`; `primary` (default: the last id) becomes `selection`.
    func select(_ ids: [SceneGraph.Node.ID], primary: SceneGraph.Node.ID? = nil) {
        isSettingSelection = true
        selectedIDs = Set(ids)
        selection = primary.flatMap { ids.contains($0) ? $0 : nil } ?? ids.last
        isSettingSelection = false
    }

    // Adds or removes one node, keeping the rest, as shift-click does.
    func toggleSelection(_ id: SceneGraph.Node.ID) {
        var ids = Array(selectedIDs)
        if let index = ids.firstIndex(of: id) {
            ids.remove(at: index)
            select(ids, primary: selection == id ? ids.last : selection)
        } else {
            ids.append(id)
            select(ids, primary: id)
        }
    }

    // The selected nodes in tree order.
    var selectedNodes: [SceneGraph.Node] {
        guard !selectedIDs.isEmpty else {
            return []
        }
        return sceneGraph.nodesWithWorldTransforms(includeHidden: true).map(\.node).filter { selectedIDs.contains($0.id) }
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
    var sidebarVisibility = NavigationSplitViewVisibility.automatic
    var sidebarTab = SidebarTab.scene
    var inspectorTab = InspectorTab.inspector

    // Shows the tab, opening its panel if hidden. For the View menu's shortcuts.
    func show(_ tab: SidebarTab) {
        sidebarTab = tab
        if sidebarVisibility == .detailOnly {
            sidebarVisibility = .all
        }
    }

    func show(_ tab: InspectorTab) {
        inspectorTab = tab
        isInspectorPresented = true
    }
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
    // The other selected nodes the gizmo carries along (#205), with their world and local transforms at drag start.
    @ObservationIgnored private var draggedCompanions: [(node: SceneGraph.Node, world: simd_float4x4, local: SceneGraph.LocalTransform)] = []
    @ObservationIgnored private var primaryWorldBeforeDrag = matrix_identity_float4x4

    // The gizmo moves the primary node; the other selected, unlocked nodes follow with the same world-space change,
    // so several nodes move, rotate and scale together around the primary one. Nodes under another dragged node are
    // skipped, because they follow their parent anyway.
    func beginGizmoDrag(_ node: SceneGraph.Node) {
        transformBeforeDrag = node.localTransform
        primaryWorldBeforeDrag = node.worldTransform
        let others = selectedNodes.filter { $0 !== node && $0.parent != nil && !isLocked($0) }
        let dragged = others + [node]
        draggedCompanions = others
            .filter { other in !dragged.contains { $0 !== other && $0.isAncestor(of: other) } }
            .map { ($0, $0.worldTransform, $0.localTransform) }
    }

    func continueGizmoDrag(_ node: SceneGraph.Node) {
        let change = node.worldTransform * primaryWorldBeforeDrag.inverse
        for companion in draggedCompanions {
            companion.node.worldTransform = change * companion.world
        }
        transformRevision += 1
    }

    // One undo step for the whole drag.
    func endGizmoDrag(_ node: SceneGraph.Node) {
        guard let before = transformBeforeDrag else {
            return
        }
        transformBeforeDrag = nil
        let companions = draggedCompanions
        draggedCompanions = []
        undoManager?.beginUndoGrouping()
        setTransform(node.localTransform, of: node, undoTo: before)
        for companion in companions {
            setTransform(companion.node.localTransform, of: companion.node, undoTo: companion.local)
        }
        undoManager?.endUndoGrouping()
    }

    public init(sceneGraph: SceneGraph, device: (any MTLDevice)? = nil) {
        self.sceneGraph = sceneGraph
        renderers = [BlinnPhongMaterialRenderer(), PBRMaterialRenderer(device: device ?? systemDefaultDevice())]
        frameAll()
        // Scales with the camera like the scene (#171), sized from the scene so it suits small and large scenes.
        baseGizmoWorldSize = sceneGraph.bounds.map { max(simd_distance($0.min, $0.max) * 0.15, 0.01) } ?? 1
        gizmo.worldSize = baseGizmoWorldSize
        gizmo.onBegin = { [weak self] node in
            self?.beginGizmoDrag(node)
        }
        gizmo.onChange = { [weak self] node in
            self?.continueGizmoDrag(node)
        }
        gizmo.onEnd = { [weak self] node in
            self?.endGizmoDrag(node)
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
        selectedNodes.contains { $0.parent != nil && !isLocked($0) }
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

    // Scene data (Node.isVisible, saved in scene.json). A hidden node and its subtree are not drawn, lit by, hit or
    // counted in bounds (#193).
    func setVisible(_ isVisible: Bool, _ node: SceneGraph.Node) {
        guard node.isVisible != isVisible else {
            return
        }
        node.isVisible = isVisible
        transformRevision += 1
        undoManager?.registerUndo(withTarget: self) { model in
            model.setVisible(!isVisible, node)
        }
        undoManager?.setActionName(isVisible ? "Show" : "Hide")
    }

    // The node's own flag; reads the revision so views refresh. Nodes are not observable (#155).
    func isVisible(_ node: SceneGraph.Node) -> Bool {
        _ = transformRevision
        return node.isVisible
    }

    // Scene data (Node.isActive). Inactive also stops actions, constraints, particles and physics (#196).
    func setActive(_ isActive: Bool, _ node: SceneGraph.Node) {
        guard node.isActive != isActive else {
            return
        }
        node.isActive = isActive
        transformRevision += 1
        undoManager?.registerUndo(withTarget: self) { model in
            model.setActive(!isActive, node)
        }
        undoManager?.setActionName(isActive ? "Activate" : "Deactivate")
    }

    func isActive(_ node: SceneGraph.Node) -> Bool {
        _ = transformRevision
        return node.isActive
    }

    // Hidden or inactive, itself or through an ancestor.
    func isHidden(_ node: SceneGraph.Node) -> Bool {
        _ = transformRevision
        var current: SceneGraph.Node? = node
        while let candidate = current {
            if !candidate.isShown {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    // From editor.json; not undoable.
    func restoreLockedNodes(_ ids: Set<SceneGraph.Node.ID>) {
        lockedNodes = ids
    }

    // Viewport picks skip locked nodes, which leaves nothing selected.
    // `extending` (shift-click) adds or removes the node instead of replacing the selection.
    func pick(_ node: SceneGraph.Node?, extending: Bool = false) {
        let id = node.flatMap { isLocked($0) ? nil : $0.id }
        if extending {
            if let id {
                toggleSelection(id)
            }
        } else {
            selection = id
        }
    }

    private func updateGizmoTarget() {
        gizmo.target = selectedNode.flatMap { isLocked($0) ? nil : $0 }
    }

    // Deletes every selected node that can be; descendants of another selected node go with it.
    func deleteSelection() {
        let nodes = selectedNodes.filter { $0.parent != nil && !isLocked($0) }
        for node in nodes where !nodes.contains(where: { $0 !== node && $0.isAncestor(of: node) }) {
            delete(node)
        }
    }

    func delete(_ node: SceneGraph.Node) {
        guard let parent = node.parent, let index = parent.children.firstIndex(where: { $0 === node }) else {
            return
        }
        node.removeFromParent()
        if selectedIDs.contains(node.id) {
            select(selectedIDs.filter { $0 != node.id }.map(\.self), primary: selection == node.id ? nil : selection)
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

    // Moves `node` under `newParent` at `index` and keeps where it is in the world. Undoable (#221).
    @discardableResult
    func reparentKeepingWorldTransform(_ node: SceneGraph.Node, to newParent: SceneGraph.Node, at index: Int? = nil) -> Bool {
        let world = node.worldTransform
        let previous = node.localTransform
        guard reparent(node, to: newParent, at: index) else {
            return false
        }
        node.worldTransform = world
        let moved = node.localTransform
        node.localTransform = previous
        setTransform(moved, of: node, undoTo: previous)
        return true
    }

    // The selected, unlocked nodes Group would take: not the root, and not under another of them.
    private var groupableNodes: [SceneGraph.Node] {
        let nodes = selectedNodes.filter { $0.parent != nil && !isLocked($0) }
        return nodes.filter { node in !nodes.contains { $0 !== node && $0.isAncestor(of: node) } }
    }

    var canGroupSelection: Bool {
        !groupableNodes.isEmpty
    }

    // Puts the selected nodes into a new empty "Group" node and selects it, as one undo step (#221). The group goes
    // under the nodes' shared parent (the root when they differ), where the first one was, at the center of their
    // bounds; the nodes keep their world transforms.
    func groupSelection() {
        let nodes = groupableNodes
        guard let first = nodes.first, let firstParent = first.parent else {
            return
        }
        let parent = nodes.allSatisfy { $0.parent === firstParent } ? firstParent : sceneGraph.root
        let index = parent === firstParent ? parent.children.firstIndex { $0 === first } ?? parent.children.count : parent.children.count
        let bounds = nodes.compactMap { sceneGraph.worldBounds(of: $0) }.reduce(nil as BoundingBox3D?) { result, bounds in
            result.map { BoundingBox3D(min: simd_min($0.min, bounds.min), max: simd_max($0.max, bounds.max)) } ?? bounds
        }
        let group = SceneGraph.Node(label: "Group")
        undoManager?.beginUndoGrouping()
        insert(group, into: parent, at: index, actionName: "Group")
        if let bounds {
            var world = group.worldTransform
            world.columns.3 = SIMD4((bounds.min + bounds.max) / 2, 1)
            group.worldTransform = world
        }
        for node in nodes {
            reparentKeepingWorldTransform(node, to: group)
        }
        selection = group.id
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Group")
    }

    // A selected, unlocked empty node with children.
    var canUngroupSelection: Bool {
        guard let node = selectedNode, node.parent != nil, !isLocked(node), !node.children.isEmpty, case .empty = node.content else {
            return false
        }
        return true
    }

    // Moves the selected group's children up to its parent where the group was, keeping world transforms, deletes
    // the group and selects the children. One undo step.
    func ungroupSelection() {
        guard canUngroupSelection, let group = selectedNode, let parent = group.parent else {
            return
        }
        let index = parent.children.firstIndex { $0 === group } ?? parent.children.count
        let children = group.children
        undoManager?.beginUndoGrouping()
        for (offset, child) in children.enumerated() {
            reparentKeepingWorldTransform(child, to: parent, at: index + offset)
        }
        delete(group)
        select(children.map(\.id))
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Ungroup")
    }

    // Moves `node` under `newParent`, keeping its local transform. False when that would make a cycle or `node` is
    // the root. Undoable.
    @discardableResult
    func reparent(_ node: SceneGraph.Node, to newParent: SceneGraph.Node, at index: Int? = nil) -> Bool {
        guard let oldParent = node.parent, let oldIndex = oldParent.children.firstIndex(where: { $0 === node }), newParent.canAddChild(node) else {
            return false
        }
        newParent.insertChild(node, at: min(index ?? newParent.children.count, newParent.children.count))
        transformRevision += 1
        undoManager?.registerUndo(withTarget: self) { model in
            model.reparent(node, to: oldParent, at: oldIndex)
        }
        undoManager?.setActionName("Move")
        return true
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

    // For edits outside this file that views showing node data must see.
    func bumpRevision() {
        transformRevision += 1
    }

    // Set by the Insert Model File… commands; ComposerView shows the file importer.
    var isImportingModel = false

    // Adds the file's contents under the selected node (the root when nothing is selected or it is locked), selects
    // it and frames it, as one undo step (#197). Returns the loader's warnings.
    // `scopedURL` is what the user granted: the file itself, or its folder for a .gltf with sibling files (#206).
    @discardableResult
    func insertModel(from url: URL, scopedURL: URL? = nil) throws -> [String] {
        let scopedURL = scopedURL ?? url
        let isAccessing = scopedURL.startAccessingSecurityScopedResource()
        defer {
            if isAccessing {
                scopedURL.stopAccessingSecurityScopedResource()
            }
        }
        let (node, warnings) = try ModelFile.load(url, device: systemDefaultDevice())
        let parent = selectedNode.flatMap { isLocked($0) ? nil : $0 } ?? sceneGraph.root
        insert(node, into: parent, at: parent.children.count, actionName: "Insert \(node.displayName)")
        frameSelection()
        return warnings
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

enum EditorItem: Hashable {
    case defaultCamera
    case defaultLighting
}

enum SidebarTab: Hashable {
    case scene
    case assistant
}

enum InspectorTab: Hashable {
    case inspector
    case render
}

extension SceneGraph {
    // Content for new documents.
    static func empty() -> SceneGraph {
        SceneGraph(root: Self.Node(label: "Root"))
    }
}
