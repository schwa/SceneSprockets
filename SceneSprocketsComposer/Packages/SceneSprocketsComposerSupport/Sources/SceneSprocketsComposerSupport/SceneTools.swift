import CollaborationKit
import Foundation
import GeometryLite3D
import Interaction3D
import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd

// Tools the assistant uses to read and edit the open scene (#191). Nodes are addressed by path: child indices from
// the root joined by "/", with "" for the root, so paths change when nodes are added or removed above them. Every
// edit goes through EditorModel, so it is undoable and the UI updates. Results are JSON strings.
@MainActor
@CollaborationTools
final class SceneTools {
    private weak var model: EditorModel?

    init(model: EditorModel) {
        self.model = model
    }

    struct NodeSummary: Encodable {
        var path: String
        var label: String
        var kind: String
        var isVisible: Bool
        var isLocked: Bool
        var childCount: Int
    }

    struct NodeDetails: Encodable {
        var path: String
        var label: String
        var kind: String
        var translation: [Float]
        var rotationDegrees: [Float]
        var scale: [Float]
        var shape: String?
        var light: String?
        var materials: [String]
        var worldBoundsMin: [Float]?
        var worldBoundsMax: [Float]?
    }

    /// List every node in the scene, depth first, with its path, label, kind (Empty, Mesh, Light, Camera), visibility, lock and child count. Call this first to learn the paths.
    @CollaborationTool
    func listNodes() throws -> String {
        let model = try requireModel()
        var result: [NodeSummary] = []
        func visit(_ node: SceneGraph.Node, path: [Int]) {
            result.append(NodeSummary(path: Self.string(path), label: node.displayName, kind: node.kindName, isVisible: node.isVisible, isLocked: model.isLocked(node), childCount: node.children.count))
            for (index, child) in node.children.enumerated() {
                visit(child, path: path + [index])
            }
        }
        visit(model.sceneGraph.root, path: [])
        return try Self.json(result)
    }

    /// Get one node's details: transform (translation, rotation as pitch/yaw/roll degrees, scale), shape, light, materials and world bounds.
    @CollaborationTool
    func getNode(path: String) throws -> String {
        let model = try requireModel()
        let node = try node(at: path)
        let trs = model.localTRS(of: node)
        var light: String?
        if case let .light(value) = node.content {
            light = "\(value.type.rawValue), intensity \(value.intensity), color \(value.color.x), \(value.color.y), \(value.color.z)"
        }
        let bounds = model.sceneGraph.worldBounds(of: node)
        let details = NodeDetails(
            path: path,
            label: node.displayName,
            kind: node.kindName,
            translation: Self.array(trs.translation),
            rotationDegrees: Self.array(Self.eulerDegrees(trs.rotation)),
            scale: Self.array(trs.scale),
            shape: node.shape.map { String(describing: $0) },
            light: light,
            materials: model.materials(of: node).map { material in
                let color = EditorModel.baseColor(of: material)
                return "\(MaterialKind(material)?.rawValue ?? String(describing: type(of: material))), color \(color.x), \(color.y), \(color.z)"
            },
            worldBoundsMin: bounds.map { Self.array($0.min) },
            worldBoundsMax: bounds.map { Self.array($0.max) }
        )
        return try Self.json(details)
    }

    /// Get the path of the selected node, or an empty result when nothing is selected.
    @CollaborationTool
    func getSelection() throws -> String {
        let model = try requireModel()
        return model.selectedNode.flatMap(Self.path(to:)).map(Self.string) ?? ""
    }

    /// Select the node at `path` in the editor.
    @CollaborationTool
    func select(path: String) throws -> String {
        let model = try requireModel()
        model.selection = try node(at: path).id
        return "Selected \(path)."
    }

    /// Add a shape under the root and select it. `kind` is one of: box, sphere, plane, cylinder, cone, capsule, torus, tube, pyramid, floor, star. Returns the new node's path.
    @CollaborationTool
    func addShape(kind: String, label: String?) throws -> String {
        let model = try requireModel()
        guard let shapeKind = ShapeKind.allCases.first(where: { $0.label.lowercased() == kind.lowercased() }) else {
            throw ToolError("Unknown shape \(kind). Use one of: \(ShapeKind.allCases.map { $0.label.lowercased() }.joined(separator: ", ")).")
        }
        model.addShape(shapeKind.shape, label: label ?? shapeKind.label)
        return try selectedPath(model)
    }

    /// Add a light under the root, aimed down, and select it. `type` is directional, point or spot. Returns the new node's path.
    @CollaborationTool
    func addLight(type: String) throws -> String {
        let model = try requireModel()
        guard let lightType = Light.LightType(rawValue: type.lowercased()) else {
            throw ToolError("Unknown light type \(type). Use directional, point or spot.")
        }
        model.addLight(lightType)
        return try selectedPath(model)
    }

    /// Add a camera at the editor's current view and select it. Returns the new node's path.
    @CollaborationTool
    func addCamera() throws -> String {
        let model = try requireModel()
        model.addCamera()
        return try selectedPath(model)
    }

    /// Delete the node at `path` and its children. Paths of later siblings change afterwards; call listNodes again.
    @CollaborationTool
    func deleteNode(path: String) throws -> String {
        let model = try requireModel()
        let node = try editableNode(at: path)
        guard node.parent != nil else {
            throw ToolError("The root cannot be deleted.")
        }
        model.delete(node)
        return "Deleted \(path)."
    }

    /// Rename the node at `path`.
    @CollaborationTool
    func renameNode(path: String, label: String) throws -> String {
        let model = try requireModel()
        model.setLabel(label.isEmpty ? nil : label, of: try editableNode(at: path))
        return "Renamed \(path) to \(label)."
    }

    /// Set any of the local transform of the node at `path`: translation [x, y, z], rotationDegrees [pitch, yaw, roll] and scale [x, y, z]. Omitted parts keep their values. +Y is up.
    @CollaborationTool
    func setTransform(path: String, translation: [Double]?, rotationDegrees: [Double]?, scale: [Double]?) throws -> String {
        let model = try requireModel()
        let node = try editableNode(at: path)
        let previous = node.localTransform
        var trs = previous.trs
        if let translation {
            trs.translation = try Self.vector(translation, name: "translation")
        }
        if let rotationDegrees {
            trs.rotation = Self.rotation(eulerDegrees: try Self.vector(rotationDegrees, name: "rotationDegrees"))
        }
        if let scale {
            trs.scale = try Self.vector(scale, name: "scale")
        }
        model.setTransform(.trs(trs), of: node, undoTo: previous)
        return "Updated the transform of \(path)."
    }

    /// Set the main color of the node's materials as linear RGB [r, g, b] from 0 to 1 (Blinn-Phong diffuse or PBR base color). Optional metallic and roughness (0 to 1) apply to PBR materials.
    @CollaborationTool
    func setMaterial(path: String, color: [Double]?, metallic: Double?, roughness: Double?) throws -> String {
        let model = try requireModel()
        let node = try editableNode(at: path)
        let materials = model.materials(of: node)
        guard !materials.isEmpty else {
            throw ToolError("\(path) has no mesh.")
        }
        let newColor = try color.map { try Self.vector($0, name: "color") }
        for (index, material) in materials.enumerated() {
            switch material {
            case var blinnPhong as BlinnPhongSceneMaterial:
                if let newColor {
                    blinnPhong.diffuse = .color(newColor)
                }
                model.setMaterial(blinnPhong, at: index, of: node)
            case let pbr as PBRSceneMaterial:
                let edited = try EditorModel.editedPBR(pbr, device: systemDefaultDevice()) { uniforms in
                    if let newColor {
                        uniforms.baseColorFactor = SIMD4(newColor, uniforms.baseColorFactor.w)
                    }
                    if let metallic {
                        uniforms.metallicFactor = Float(metallic)
                    }
                    if let roughness {
                        uniforms.roughnessFactor = Float(roughness)
                    }
                }
                model.setMaterial(edited, at: index, of: node)
            default:
                continue
            }
        }
        return "Updated the material of \(path)."
    }

    // MARK: - Helpers

    private func requireModel() throws -> EditorModel {
        guard let model else {
            throw ToolError("The document is closed.")
        }
        return model
    }

    private func node(at path: String) throws -> SceneGraph.Node {
        var node = try requireModel().sceneGraph.root
        for part in path.split(separator: "/") {
            guard let index = Int(part), node.children.indices.contains(index) else {
                throw ToolError("No node at path \"\(path)\". Call listNodes for current paths.")
            }
            node = node.children[index]
        }
        return node
    }

    private func editableNode(at path: String) throws -> SceneGraph.Node {
        let node = try node(at: path)
        guard try !requireModel().isLocked(node) else {
            throw ToolError("\(path) is locked. Ask the user to unlock it.")
        }
        return node
    }

    private func selectedPath(_ model: EditorModel) throws -> String {
        guard let node = model.selectedNode, let path = Self.path(to: node) else {
            throw ToolError("The new node could not be found.")
        }
        return Self.string(path)
    }

    static func path(to node: SceneGraph.Node) -> [Int]? {
        var path: [Int] = []
        var current = node
        while let parent = current.parent {
            guard let index = parent.children.firstIndex(where: { $0 === current }) else {
                return nil
            }
            path.insert(index, at: 0)
            current = parent
        }
        return path
    }

    static func string(_ path: [Int]) -> String {
        path.map(String.init).joined(separator: "/")
    }

    private static func vector(_ values: [Double], name: String) throws -> SIMD3<Float> {
        guard values.count == 3 else {
            throw ToolError("\(name) needs exactly 3 numbers.")
        }
        return SIMD3(Float(values[0]), Float(values[1]), Float(values[2]))
    }

    private static func array(_ value: SIMD3<Float>) -> [Float] {
        [value.x, value.y, value.z]
    }

    // Pitch, yaw, roll as the inspector shows them (Interaction3D's CameraPose convention), with asin's input clamped
    // so rounding near ±90° yaw cannot give NaN, which JSON cannot hold. CameraPose does not clamp.
    static func eulerDegrees(_ rotation: simd_quatf) -> SIMD3<Float> {
        let matrix = simd_float4x4(rotation)
        let yaw = asin(min(max(-matrix.columns.0.z, -1), 1))
        let pitch: Float
        let roll: Float
        if abs(cos(yaw)) > 0.0001 {
            pitch = atan2(matrix.columns.1.z, matrix.columns.2.z)
            roll = atan2(matrix.columns.0.y, matrix.columns.0.x)
        } else {
            pitch = atan2(-matrix.columns.2.y, matrix.columns.1.y)
            roll = 0
        }
        return SIMD3(pitch, yaw, roll) * (180 / .pi)
    }

    static func rotation(eulerDegrees: SIMD3<Float>) -> simd_quatf {
        simd_quatf(CameraPose(position: .zero, rotationDegrees: eulerDegrees).matrix)
    }

    private static func json(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
