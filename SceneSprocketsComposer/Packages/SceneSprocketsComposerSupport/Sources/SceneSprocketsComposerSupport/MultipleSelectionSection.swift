import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd
import SwiftUI

// Shared fields for every selected node (#205), above the primary node's own sections. A toggle shows on when all
// nodes have it on; setting it sets all of them, as one undo step. Locked nodes are left alone.
struct MultipleSelectionSection: View {
    var model: EditorModel

    var body: some View {
        let nodes = model.selectedNodes
        Section("\(nodes.count) Nodes Selected") {
            Toggle("Visible", isOn: Binding(get: { nodes.allSatisfy { model.isVisible($0) } }, set: { value in
                model.editSelection("Visibility") { model, node in model.setVisible(value, node) }
            }))
            Toggle("Active", isOn: Binding(get: { nodes.allSatisfy { model.isActive($0) } }, set: { value in
                model.editSelection("Active") { model, node in model.setActive(value, node) }
            }))
            Toggle("Locked", isOn: Binding(get: { nodes.allSatisfy { model.lockedNodes.contains($0.id) } }, set: { value in
                model.editSelection("Lock", includesLocked: true) { model, node in model.setLocked(value, node) }
            }))
            if nodes.contains(where: { !model.materials(of: $0).isEmpty }) {
                ColorPicker("Color", selection: Binding(get: {
                    let color = nodes.lazy.compactMap { model.materials(of: $0).first }.first.map(EditorModel.baseColor(of:)) ?? .one
                    return Color(.sRGBLinear, red: Double(color.x), green: Double(color.y), blue: Double(color.z))
                }, set: { newColor in
                    let resolved = newColor.resolve(in: EnvironmentValues())
                    let color = SIMD3<Float>(resolved.linearRed, resolved.linearGreen, resolved.linearBlue)
                    model.editSelection("Color") { model, node in model.setBaseColor(color, of: node) }
                }), supportsOpacity: false)
            }
        }
    }
}

extension EditorModel {
    // Runs `edit` for each selected node (unlocked ones unless `includesLocked`) as one undo step.
    func editSelection(_ actionName: String, includesLocked: Bool = false, _ edit: (EditorModel, SceneGraph.Node) -> Void) {
        undoManager?.beginUndoGrouping()
        for node in selectedNodes where includesLocked || !isLocked(node) {
            edit(self, node)
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName(actionName)
    }

    // The main color of each of the node's materials: Blinn-Phong diffuse or PBR base color. Textured channels keep
    // their texture.
    func setBaseColor(_ color: SIMD3<Float>, of node: SceneGraph.Node) {
        for (index, material) in materials(of: node).enumerated() {
            switch material {
            case var blinnPhong as BlinnPhongSceneMaterial:
                guard case .color = blinnPhong.diffuse else {
                    continue
                }
                blinnPhong.diffuse = .color(color)
                setMaterial(blinnPhong, at: index, of: node, actionName: "Color")
            case let pbr as PBRSceneMaterial:
                if let edited = try? EditorModel.editedPBR(pbr, device: systemDefaultDevice(), { $0.baseColorFactor = SIMD4(color, $0.baseColorFactor.w) }) {
                    setMaterial(edited, at: index, of: node, actionName: "Color")
                }
            default:
                continue
            }
        }
    }
}
