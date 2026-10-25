import GeometryLite3D
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd
import SwiftUI

// Shared fields for every selected node (#205), above the primary node's own sections. A toggle shows on when all
// nodes have it on; setting it sets all of them, as one undo step. Locked nodes are left alone.
struct MultipleSelectionSectionView: View {
    @Bindable var model: EditorModel

    var body: some View {
        let nodes = model.selectedNodes
        Section("\(nodes.count) Nodes Selected") {
            Toggle("Visible", isOn: $model.selectionIsVisible)
            Toggle("Active", isOn: $model.selectionIsActive)
            Toggle("Locked", isOn: $model.selectionIsLocked)
            if nodes.contains(where: { !model.materials(of: $0).isEmpty }) {
                ColorPicker("Color", selection: $model.selectionBaseColor.linearColor, supportsOpacity: false)
            }
        }
    }
}

extension EditorModel {
    // Runs `edit` for each selected node (unlocked ones unless `includesLocked`) as one undo step.
    func editSelection(_ actionName: String, includesLocked: Bool = false, _ edit: (EditorModel, SceneGraph.Node) -> Void) {
        transaction(actionName) {
            for node in selectedNodes where includesLocked || !isLocked(node) {
                edit(self, node)
            }
        }
    }

    // The editor camera's viewport for a preview of `viewSize` points, as SceneView builds it (#240).
    func viewport(viewSize: SIMD2<Float>) -> SceneViewport? {
        guard viewSize.x > 0, viewSize.y > 0 else {
            return nil
        }
        return SceneViewport(cameraMatrix: camera.matrix, camera: renderSettings.camera, viewSize: viewSize, drawableSize: viewSize)
    }

    // The node under a point (view coordinates, origin top-left), as a click picks it: light and camera shapes first
    // when shown, because they are drawn on top, then the nearest mesh the camera can see. Clicks and the context
    // menu both use this (#220, #240).
    func node(at point: SIMD2<Float>, in viewport: SceneViewport) -> SceneGraph.Node? {
        if renderSettings.showsLightsAndCameras, let shape = DebugShapes.hitTest(point, sceneGraph: sceneGraph, viewport: viewport) {
            return shape
        }
        return sceneGraph.hitTest(viewport.ray(through: point), categoryBitMask: renderSettings.camera.categoryBitMask).first?.node
    }

    func node(at point: SIMD2<Float>, viewSize: SIMD2<Float>) -> SceneGraph.Node? {
        viewport(viewSize: viewSize).flatMap { node(at: point, in: $0) }
    }

    // Moves `node` up or down so the bottom of its world bounds is at y = 0, keeping x and z (#210). Works for nested
    // and rotated nodes by changing the world transform. False for nodes without bounds (empty, lights, cameras,
    // hidden). Undoable.
    @discardableResult
    func dropToFloor(_ node: SceneGraph.Node) -> Bool {
        guard node.parent != nil, let bounds = sceneGraph.worldBounds(of: node), abs(bounds.min.y) > 1e-6 else {
            return false
        }
        let previous = node.localTransform
        var world = node.worldTransform
        world.columns.3.y -= bounds.min.y
        node.worldTransform = world
        let dropped = node.localTransform
        node.localTransform = previous
        setTransform(dropped, of: node, undoTo: previous)
        return true
    }

    // Drops every selected, unlocked node as one undo step. A node under another selected node is skipped, because
    // it moves with that node.
    func dropSelectionToFloor() {
        let nodes = selectedNodes.filter { !isLocked($0) }
        transaction("Drop to Floor") {
            for node in nodes where !nodes.contains(where: { $0 !== node && $0.isAncestor(of: node) }) {
                dropToFloor(node)
            }
        }
    }

    var canDropSelectionToFloor: Bool {
        selectedNodes.contains { !isLocked($0) && sceneGraph.worldBounds(of: $0) != nil }
    }

    // The main color of each of the node's materials: Blinn-Phong diffuse or PBR base color. Textured channels keep
    // their texture.
    func setBaseColor(_ color: SIMD3<Float>, of node: SceneGraph.Node) {
        try? editMaterials(of: node, actionName: "Color", [.baseColor(color)])
    }
}

#Preview {
    let model = EditorModel(sceneGraph: ComposerDocument().sceneGraph)
    model.addShape(.box(), label: "A")
    model.addShape(.sphere(), label: "B")
    model.select(model.sceneGraph.root.children.map(\.id), primary: nil)
    return Form {
        MultipleSelectionSectionView(model: model)
    }
    .formStyle(.grouped)
}
