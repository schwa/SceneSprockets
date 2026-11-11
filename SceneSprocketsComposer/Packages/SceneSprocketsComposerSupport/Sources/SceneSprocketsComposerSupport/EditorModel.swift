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
import SwiftUI

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
        observe([.visibility, .structure, .content])
        return renderSettings.usesDefaultLighting && !Self.containsShownLight(sceneGraph.root)
    }

    // Like !sceneGraph.lightNodes().isEmpty without computing world transforms, so observing it does not depend on
    // every node's transform (#223).
    private static func containsShownLight(_ node: SceneGraph.Node) -> Bool {
        guard node.isShown else {
            return false
        }
        if case .light = node.content {
            return true
        }
        return node.children.contains(where: containsShownLight)
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
    // Nodes are not observable (SceneSprockets #155), and every edit goes through perform (#236), so the model tracks
    // scene changes itself: one revision per aspect, read by observe(_:) and bumped by notify(_:) only (#237). A view
    // that observes .visibility does not re-run while the gizmo drags (#223).
    private var transformRevision = 0
    private var visibilityRevision = 0
    private var labelRevision = 0
    private var contentRevision = 0
    private var structureRevision = 0
    private var environmentRevision = 0

    // Makes the current Observation tracking (a view body, withObservationTracking) depend on `aspects`.
    func observe(_ aspects: SceneAspects) {
        if aspects.contains(.transform) { _ = transformRevision }
        if aspects.contains(.visibility) { _ = visibilityRevision }
        if aspects.contains(.label) { _ = labelRevision }
        if aspects.contains(.content) { _ = contentRevision }
        if aspects.contains(.structure) { _ = structureRevision }
        if aspects.contains(.environment) { _ = environmentRevision }
    }

    // Tells observers of `aspects` that they changed.
    func notify(_ aspects: SceneAspects) {
        if aspects.contains(.transform) { transformRevision += 1 }
        if aspects.contains(.visibility) { visibilityRevision += 1 }
        if aspects.contains(.label) { labelRevision += 1 }
        if aspects.contains(.content) { contentRevision += 1 }
        if aspects.contains(.structure) { structureRevision += 1 }
        if aspects.contains(.environment) { environmentRevision += 1 }
    }

    // The scene tree's top level; observing it refreshes the tree when nodes are added, removed or moved.
    var outlineRoots: [SceneGraph.Node] {
        observe(.structure)
        return [sceneGraph.root]
    }

    func displayName(of node: SceneGraph.Node) -> String {
        observe(.label)
        return node.displayName
    }

    // The one way to change the scene undoably (#236). Runs `change`, notifies readers of `aspects`, and registers
    // `revert` as the undo step named `actionName`; redo runs `change` again. Both get the model and must not
    // register undo themselves.
    func perform(_ actionName: String, affecting aspects: SceneAspects, _ change: @escaping (EditorModel) -> Void, revert: @escaping (EditorModel) -> Void) {
        change(self)
        notify(aspects)
        undoManager?.registerUndo(withTarget: self) { model in
            model.perform(actionName, affecting: aspects, revert, revert: change)
        }
        undoManager?.setActionName(actionName)
    }

    // Runs several changes as one undo step named `actionName`.
    func transaction(_ actionName: String, _ body: () -> Void) {
        undoManager?.beginUndoGrouping()
        body()
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(actionName)
    }
    // Set by the view from the document's environment; registering undo marks the document edited.
    @ObservationIgnored public weak var undoManager: UndoManager?
    // PBRMaterialRenderer caches GPU state, so keep one instance per editor.
    @ObservationIgnored public let renderers: [any SceneGraphMaterialRenderer]
    @ObservationIgnored public let gizmo = TransformGizmo()
    // Keeps its textures between frames.
    @ObservationIgnored let selectionOutline = SelectionOutline()
    // One instance, so it keeps its GPU state and SceneView sees the same shadows between updates (#235).
    @ObservationIgnored let shadows = SceneGraphShadows()
    // Observable itself; for the frame rate cap.
    @ObservationIgnored let display = DisplayFrameRate()

    // The preview's frame rate: the cap in the render settings, or the display's maximum.
    var previewFramesPerSecond: Int {
        renderSettings.maximumFramesPerSecond ?? display.maximumFramesPerSecond
    }
    @ObservationIgnored private var transformBeforeDrag: Transform3D?
    // The other selected nodes the gizmo carries along (#205), with their world and local transforms at drag start.
    @ObservationIgnored private var draggedCompanions: [(node: SceneGraph.Node, world: simd_float4x4, local: Transform3D)] = []
    @ObservationIgnored private var primaryWorldBeforeDrag = matrix_identity_float4x4

    // The gizmo moves the primary node; the other selected, unlocked nodes follow with the same world-space change,
    // so several nodes move, rotate and scale together around the primary one. Nodes under another dragged node are
    // skipped, because they follow their parent anyway.
    func beginGizmoDrag(_ node: SceneGraph.Node) {
        transformBeforeDrag = node.transform
        primaryWorldBeforeDrag = node.worldTransform
        let others = selectedNodes.filter { $0 !== node && $0.parent != nil && !isLocked($0) }
        let dragged = others + [node]
        draggedCompanions = others
            .filter { other in !dragged.contains { $0 !== other && $0.isAncestor(of: other) } }
            .map { ($0, $0.worldTransform, $0.transform) }
    }

    func continueGizmoDrag(_ node: SceneGraph.Node) {
        let change = node.worldTransform * primaryWorldBeforeDrag.inverse
        for companion in draggedCompanions {
            companion.node.worldTransform = change * companion.world
        }
        // Live feedback; the undo step is registered when the drag ends.
        notify(.transform)
    }

    // One undo step for the whole drag.
    func endGizmoDrag(_ node: SceneGraph.Node) {
        guard let before = transformBeforeDrag else {
            return
        }
        transformBeforeDrag = nil
        let companions = draggedCompanions
        draggedCompanions = []
        transaction("Transform") {
            setTransform(node.transform, of: node, undoTo: before)
            for companion in companions {
                setTransform(companion.node.transform, of: companion.node, undoTo: companion.local)
            }
        }
    }

    public init(sceneGraph: SceneGraph) {
        self.sceneGraph = sceneGraph
        renderers = [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()]
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
        observe(.environment)
        return sceneGraph.environment
    }
    func setEnvironment(_ environment: SceneGraph.Environment, actionName: String) {
        let previous = sceneGraph.environment
        perform(actionName, affecting: .environment, { $0.sceneGraph.environment = environment }, revert: { $0.sceneGraph.environment = previous })
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

    // Observes transforms, so callers refresh while the gizmo drags.
    func localTransform(of node: SceneGraph.Node) -> Transform3D {
        observe(.transform)
        return node.transform
    }

    func setTransform(_ transform: Transform3D, of node: SceneGraph.Node, undoTo previous: Transform3D) {
        perform("Transform", affecting: .transform, { _ in node.transform = transform }, revert: { _ in node.transform = previous })
    }

    // The root cannot be deleted.
    var canDeleteSelection: Bool {
        selectedNodes.contains { $0.parent != nil && !isLocked($0) }
    }

    // Locked itself or through an ancestor. Nodes inside an imported model are locked too: the document stores the
    // model's file, so edits inside it would be lost. Move the model as a whole (#157), or explode it to edit (#183).
    func isLocked(_ node: SceneGraph.Node) -> Bool {
        if modelRoot(containing: node) !== node, modelRoot(containing: node) != nil {
            return true
        }
        var current: SceneGraph.Node? = node
        while let candidate = current {
            if lockedNodes.contains(candidate.id) {
                return true
            }
            current = candidate.parent
        }
        return false
    }

    // Not locked and not part of an imported model, whose saved file would not include new children (#157).
    func canAddChildren(to node: SceneGraph.Node) -> Bool {
        !isLocked(node) && modelRoot(containing: node) == nil
    }

    // The outermost imported model `node` is part of (itself if it is one), or nil.
    func modelRoot(containing node: SceneGraph.Node) -> SceneGraph.Node? {
        var result: SceneGraph.Node?
        var current: SceneGraph.Node? = node
        while let candidate = current {
            if candidate.modelSource != nil {
                result = candidate
            }
            current = candidate.parent
        }
        return result
    }

    func setLocked(_ isLocked: Bool, _ node: SceneGraph.Node) {
        guard lockedNodes.contains(node.id) != isLocked else {
            return
        }
        let id = node.id
        // lockedNodes is observed directly.
        perform(isLocked ? "Lock" : "Unlock", affecting: [], { model in
            if isLocked {
                model.lockedNodes.insert(id)
            } else {
                model.lockedNodes.remove(id)
            }
        }, revert: { model in
            if isLocked {
                model.lockedNodes.remove(id)
            } else {
                model.lockedNodes.insert(id)
            }
        })
    }

    // Scene data (Node.isVisible, saved in scene.json). A hidden node and its subtree are not drawn, lit by, hit or
    // counted in bounds (#193).
    func setVisible(_ isVisible: Bool, _ node: SceneGraph.Node) {
        guard node.isVisible != isVisible else {
            return
        }
        perform(isVisible ? "Show" : "Hide", affecting: .visibility, { _ in node.isVisible = isVisible }, revert: { _ in node.isVisible = !isVisible })
    }

    // The node's own flag, observed.
    func isVisible(_ node: SceneGraph.Node) -> Bool {
        observe(.visibility)
        return node.isVisible
    }

    // Scene data (Node.isActive). Inactive also stops actions, constraints, particles and physics (#196).
    func setActive(_ isActive: Bool, _ node: SceneGraph.Node) {
        guard node.isActive != isActive else {
            return
        }
        perform(isActive ? "Activate" : "Deactivate", affecting: .visibility, { _ in node.isActive = isActive }, revert: { _ in node.isActive = !isActive })
    }

    func isActive(_ node: SceneGraph.Node) -> Bool {
        observe(.visibility)
        return node.isActive
    }

    // Hidden or inactive, itself or through an ancestor.
    func isHidden(_ node: SceneGraph.Node) -> Bool {
        // Moving a node under a hidden parent hides it too.
        observe([.visibility, .structure])
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
        // A click inside an imported model picks the model (#157).
        let node = node.map { modelRoot(containing: $0) ?? $0 }
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
        perform("Delete", affecting: .structure, { model in
            node.removeFromParent()
            model.deselect(node)
        }, revert: { model in
            parent.insertChild(node, at: min(index, parent.children.count))
            model.selection = node.id
        })
    }

    private func insert(_ node: SceneGraph.Node, into parent: SceneGraph.Node, at index: Int, actionName: String) {
        perform(actionName, affecting: .structure, { model in
            parent.insertChild(node, at: min(index, parent.children.count))
            model.selection = node.id
        }, revert: { model in
            node.removeFromParent()
            model.deselect(node)
        })
    }

    private func deselect(_ node: SceneGraph.Node) {
        if selectedIDs.contains(node.id) {
            select(selectedIDs.filter { $0 != node.id }.map(\.self), primary: selection == node.id ? nil : selection)
        }
    }

    // Moves `node` under `newParent` at `index` and keeps where it is in the world. Undoable (#221).
    @discardableResult
    func reparentKeepingWorldTransform(_ node: SceneGraph.Node, to newParent: SceneGraph.Node, at index: Int? = nil) -> Bool {
        let world = node.worldTransform
        let previous = node.transform
        guard reparent(node, to: newParent, at: index) else {
            return false
        }
        node.worldTransform = world
        let moved = node.transform
        node.transform = previous
        setTransform(moved, of: node, undoTo: previous)
        return true
    }

    // The node being dragged in the scene tree. Drag payloads are strings, so the node itself stays here.
    @ObservationIgnored weak var draggedNode: SceneGraph.Node?

    // A tree drop on `target` (#222): into it when it is a group (an empty node with children), otherwise just before
    // it.
    @discardableResult
    func drop(_ node: SceneGraph.Node, onto target: SceneGraph.Node) -> Bool {
        if case .empty = target.content, !target.children.isEmpty || target.parent == nil {
            return move(node, into: target)
        }
        return move(node, before: target)
    }

    // Moves `node` just before `target`, under `target`'s parent, keeping its world transform (#222). False for the
    // root, locked nodes, or a move that would put a node inside itself.
    @discardableResult
    func move(_ node: SceneGraph.Node, before target: SceneGraph.Node) -> Bool {
        guard node !== target, let parent = target.parent, !isLocked(node), let index = parent.children.firstIndex(where: { $0 === target }) else {
            return false
        }
        return reparentKeepingWorldTransform(node, to: parent, at: index)
    }

    // Moves `node` to the end of `group`'s children, keeping its world transform.
    @discardableResult
    func move(_ node: SceneGraph.Node, into group: SceneGraph.Node) -> Bool {
        guard node !== group, !isLocked(node) else {
            return false
        }
        return reparentKeepingWorldTransform(node, to: group)
    }

    // Moves the primary selection `offset` places among its siblings (negative is up), clamped to the ends.
    func moveSelection(by offset: Int) {
        guard let node = selectedNode, let parent = node.parent, !isLocked(node), let index = parent.children.firstIndex(where: { $0 === node }) else {
            return
        }
        let destination = min(max(index + offset, 0), parent.children.count - 1)
        guard destination != index else {
            return
        }
        // insertChild inserts before the node currently at an index, so moving down needs one past the target slot.
        transaction(offset < 0 ? "Move Up" : "Move Down") {
            reparent(node, to: parent, at: destination > index ? destination + 1 : destination)
        }
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
        // Placed before it is inserted, so the change needs no undo of its own.
        if let bounds {
            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4((bounds.min + bounds.max) / 2, 1)
            group.transform = Transform3D(storing: parent.worldTransform.inverse * transform)
        }
        transaction("Group") {
            insert(group, into: parent, at: index, actionName: "Group")
            for node in nodes {
                reparentKeepingWorldTransform(node, to: group)
            }
            selection = group.id
        }
    }

    // The selection is part of an unlocked imported model.
    var canExplodeSelection: Bool {
        guard let node = selectedNode, let root = modelRoot(containing: node) else {
            return false
        }
        return !isLocked(root)
    }

    // Turns the imported model holding the selection into plain nodes (#183): it then saves as scene nodes with
    // generated meshes (#158) instead of its file, and its nodes can be edited and take children. Undoable.
    func explodeSelection() {
        guard canExplodeSelection, let node = selectedNode, let root = modelRoot(containing: node), let source = root.modelSource else {
            return
        }
        perform("Explode", affecting: [.structure], { _ in
            root.modelSource = nil
        }, revert: { _ in
            root.modelSource = source
        })
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
        transaction("Ungroup") {
            for (offset, child) in children.enumerated() {
                reparentKeepingWorldTransform(child, to: parent, at: index + offset)
            }
            delete(group)
            select(children.map(\.id))
        }
    }

    // Moves `node` under `newParent`, keeping its local transform. False when that would make a cycle or `node` is
    // the root. Undoable.
    @discardableResult
    func reparent(_ node: SceneGraph.Node, to newParent: SceneGraph.Node, at index: Int? = nil) -> Bool {
        // Within one parent (reordering) is fine; moving into an imported model is not.
        guard let oldParent = node.parent, let oldIndex = oldParent.children.firstIndex(where: { $0 === node }), newParent.canAddChild(node), newParent === oldParent || modelRoot(containing: newParent) == nil else {
            return false
        }
        perform("Move", affecting: [.transform, .structure], { _ in
            newParent.insertChild(node, at: min(index ?? newParent.children.count, newParent.children.count))
        }, revert: { _ in
            // insertChild inserts before the node at an index after taking this one out; to land back at oldIndex
            // when the node now sits earlier in the same parent, pass one more (#222).
            let current = oldParent.children.firstIndex { $0 === node }
            let index = current.map { $0 < oldIndex ? oldIndex + 1 : oldIndex } ?? oldIndex
            oldParent.insertChild(node, at: min(index, oldParent.children.count))
        })
        return true
    }

    // Adds under the root and selects it.
    func addShape(_ shape: SceneGraph.Shape, label: String) {
        let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color(0.8), specular: .color(0.5), shininess: 32)
        let node = SceneGraph.Node(label: label, shape: shape, material: material)
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
        let node = SceneGraph.Node(label: label, transform: Transform3D(storing: transform), content: .light(Light(type: type, range: range)))
        insert(node, into: sceneGraph.root, at: sceneGraph.root.children.count, actionName: "Add \(label)")
    }

    // Placed at the editor camera, so it sees what the user sees.
    func addCamera() {
        let node = SceneGraph.Node(label: "Camera", transform: Transform3D(storing: camera.matrix), content: .camera(renderSettings.camera))
        insert(node, into: sceneGraph.root, at: sceneGraph.root.children.count, actionName: "Add Camera")
    }

    static func label(for type: Light.LightType) -> String {
        "\(type.rawValue.prefix(1).uppercased())\(type.rawValue.dropFirst()) Light"
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
        let (node, warnings) = try ModelFile.load(url)
        let parent = selectedNode.flatMap { canAddChildren(to: $0) ? $0 : nil } ?? sceneGraph.root
        insert(node, into: parent, at: parent.children.count, actionName: "Insert \(node.displayName)")
        frameSelection()
        return warnings
    }

    func setLabel(_ label: String?, of node: SceneGraph.Node) {
        let previous = node.label
        guard label != previous else {
            return
        }
        perform("Rename", affecting: .label, { _ in node.label = label }, revert: { _ in node.label = previous })
    }

    func setLight(_ light: Light, of node: SceneGraph.Node) {
        guard case .light(let previous) = node.content else {
            return
        }
        perform("Light", affecting: .content, { _ in node.content = .light(light) }, revert: { _ in node.content = .light(previous) })
    }

    public var selectedNode: SceneGraph.Node? {
        guard let selection else {
            return nil
        }
        return sceneGraph.nodesWithWorldTransforms(includeHidden: true).first { $0.node.id == selection }?.node
    }
}

// A row in the scene tree: Scene, an editor row (#207), or a node.
enum TreeItem: Hashable {
    case scene
    case editor(EditorItem)
    case node(SceneGraph.Node.ID)
}

extension EditorModel {
    // The scene tree's List selection, as a model property so the list gets a key-path binding SwiftUI can compare
    // (#223); a Binding(get:set:) is new every time and re-renders the whole tree.
    // Multiple selection (#201): choosing Scene, or nothing, clears the node selection. The primary node stays primary
    // while it is still selected; otherwise the newly added node becomes primary. An editor row selects alone.
    var treeSelection: Set<TreeItem> {
        get {
            if let editorItem {
                return [.editor(editorItem)]
            }
            return selectedIDs.isEmpty ? [.scene] : Set(selectedIDs.map(TreeItem.node))
        }
        set {
            let ids = newValue.compactMap { item -> SceneGraph.Node.ID? in
                if case let .node(id) = item { id } else { nil }
            }
            guard !ids.isEmpty else {
                let editorItem = newValue.lazy.compactMap { item -> EditorItem? in
                    if case let .editor(editorItem) = item { editorItem } else { nil }
                }.first
                selection = nil
                self.editorItem = editorItem
                return
            }
            let added = ids.first { !selectedIDs.contains($0) }
            select(ids, primary: added ?? selection)
        }
    }

    // The camera matrix as SceneView takes it, for a key-path binding (#223).
    var viewCameraMatrix: simd_float4x4? {
        get { camera.matrix }
        set { camera.matrix = newValue ?? camera.matrix }
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
