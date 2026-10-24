import CollaborationKit
import Foundation
import GeometryLite3D
import Interaction3D
import MetalSprocketsPBR
import SceneSprockets
import SceneSprocketsBlinnPhong
import SceneSprocketsPBR
import simd

// The assistant's tools for the open scene (#191, #202): query, select, create, update and delete, which the model
// combines for align, distribute, recolor and so on. Nodes have short ids ("n1", "n2", ...) that stay the same for
// the session while other nodes come and go; "root" is the root. Every edit goes through EditorModel, so it is
// undoable (one step per turn, #203) and the UI updates. Locked nodes are refused. Results are JSON strings.
@MainActor
@CollaborationTools
final class SceneTools {
    private weak var model: EditorModel?
    private var idsByNode: [ObjectIdentifier: String] = [:]
    private var nodesByID: [String: WeakNode] = [:]
    private var nextID = 1

    private struct WeakNode {
        weak var node: SceneGraph.Node?
    }

    init(model: EditorModel) {
        self.model = model
    }

    struct NodeInfo: Encodable {
        var id: String
        var parent: String?
        var label: String
        var kind: String
        var shape: String?
        var light: String?
        var isVisible: Bool
        var isActive: Bool
        var isLocked: Bool
        var translation: [Float]
        var rotationDegrees: [Float]
        var scale: [Float]
        var color: [Float]?
        var worldBoundsMin: [Float]?
        var worldBoundsMax: [Float]?
    }

    struct Scene: Encodable {
        var selection: [String]
        var nodes: [NodeInfo]
        var environment: EnvironmentInfo
    }

    struct EnvironmentInfo: Encodable {
        // none, color or environment.
        var background: String
        var backgroundColor: [Float]?
        var backgroundBlur: Float?
        // default, studio or custom (an image the user chose).
        var map: String
        var intensity: Float
        var rotationDegrees: Float
    }

    /// Read the whole scene: every node depth first with id, parent id, label, kind (Empty, Mesh, Light, Camera), shape, light, visibility, active, lock, local transform (translation, rotation as pitch/yaw/roll degrees, scale), main material color and world bounds; plus the ids of the selected nodes. +Y is up; units are meters.
    @CollaborationTool
    func query() throws -> String {
        let model = try requireModel()
        var nodes: [NodeInfo] = []
        func visit(_ node: SceneGraph.Node) {
            nodes.append(info(for: node, model: model))
            node.children.forEach(visit)
        }
        visit(model.sceneGraph.root)
        let selection = model.selectedNodes.map { id(for: $0) }
        return try Self.json(Scene(selection: selection, nodes: nodes, environment: Self.environmentInfo(model.environment)))
    }

    /// Select nodes by id in the editor; an empty list clears the selection. The last id becomes the primary selection, which the inspector shows and the gizmo moves. Requests like "align the selected objects" act on query's `selection`.
    @CollaborationTool
    func select(ids: [String]) throws -> String {
        let model = try requireModel()
        guard !ids.isEmpty else {
            model.selection = nil
            return "Cleared the selection."
        }
        model.select(try ids.map { try node(id: $0).id })
        return "Selected \(ids.joined(separator: ", "))."
    }

    /// Use one call for repeated work: never call create several times for nodes of the same kind. Creates one or more nodes and returns their ids, comma separated. `kind` is a shape (box, sphere, plane, cylinder, cone, capsule, torus, tube, pyramid, floor, star), a light (directional, point, spot) or camera. For several at once give `count`, or per-node arrays (`translations` [[x, y, z], ...], `labels`, `colors` [[r, g, b], ...]), all the same length; count defaults to their length. Without `labels`, several nodes get numbered labels. Values for every node: label, parent id (default root), translation [x, y, z], rotationDegrees [pitch, yaw, roll], scale [x, y, z], color [r, g, b] in linear 0 to 1 (shapes only). Shapes are about 1 unit across, centered on their origin; spread several out with `translations`.
    @CollaborationTool
    func create(kind: String, count: Int?, label: String?, parent: String?, translation: [Double]?, translations: [[Double]]?, rotationDegrees: [Double]?, scale: [Double]?, color: [Double]?, labels: [String]? = nil, colors: [[Double]]? = nil) throws -> String {
        let total = count ?? translations?.count ?? labels?.count ?? colors?.count ?? 1
        guard (1 ... Self.maximumBatch).contains(total) else {
            throw ToolError("count must be from 1 to \(Self.maximumBatch).")
        }
        try Self.checkLength(translations, "translations", total)
        try Self.checkLength(labels, "labels", total)
        try Self.checkLength(colors, "colors", total)
        var ids: [String] = []
        for index in 0..<total {
            let numberedLabel = labels?[index] ?? (total > 1 ? label.map { "\($0) \(index + 1)" } : label)
            ids.append(try createOne(kind: kind, label: numberedLabel, parent: parent, translation: translations?[index] ?? translation, rotationDegrees: rotationDegrees, scale: scale, color: colors?[index] ?? color))
        }
        return ids.joined(separator: ", ")
    }

    private static func checkLength<Element>(_ values: [Element]?, _ name: String, _ count: Int) throws {
        if let values, values.count != count {
            throw ToolError("\(name) has \(values.count) entries for \(count) nodes.")
        }
    }

    static let maximumBatch = 1_000

    private func createOne(kind: String, label: String?, parent: String?, translation: [Double]?, rotationDegrees: [Double]?, scale: [Double]?, color: [Double]?) throws -> String {
        let model = try requireModel()
        let parentNode = try parent.map { try editableNode(id: $0) }
        let lowered = kind.lowercased()
        if let shapeKind = ShapeKind.allCases.first(where: { $0.label.lowercased() == lowered }) {
            model.addShape(shapeKind.shape, label: label ?? shapeKind.label)
        } else if let lightType = Light.LightType(rawValue: lowered.replacingOccurrences(of: " light", with: "")) {
            model.addLight(lightType)
        } else if lowered == "camera" {
            model.addCamera()
        } else {
            throw ToolError("Unknown kind \(kind). Use a shape (\(ShapeKind.allCases.map { $0.label.lowercased() }.joined(separator: ", "))), directional, point, spot or camera.")
        }
        guard let node = model.selectedNode else {
            throw ToolError("The new node could not be found.")
        }
        if let label {
            model.setLabel(label, of: node)
        }
        if let parentNode {
            model.reparent(node, to: parentNode)
        }
        try apply(to: node, model: model, translation: translation, rotationDegrees: rotationDegrees, scale: scale, color: color, metallic: nil, roughness: nil)
        return id(for: node)
    }

    /// Use one call for repeated work: give every id at once instead of calling update per node. Changes one or more nodes; omitted fields are kept. Same value for every id: label, parent (id; keeps the local transform), translation [x, y, z], rotationDegrees [pitch, yaw, roll], scale [x, y, z], color [r, g, b] linear 0 to 1, metallic and roughness 0 to 1 (PBR), isVisible, isActive (inactive also stops animation). Different value per id, in the same order as ids: `translations` (align, distribute, arrange), `labels`, `colors`.
    @CollaborationTool
    func update(ids: [String], label: String?, parent: String?, translation: [Double]?, translations: [[Double]]?, rotationDegrees: [Double]?, scale: [Double]?, color: [Double]?, metallic: Double?, roughness: Double?, isVisible: Bool?, isActive: Bool?, labels: [String]? = nil, colors: [[Double]]? = nil) throws -> String {
        let model = try requireModel()
        let nodes = try ids.map { try editableNode(id: $0) }
        let parentNode = try parent.map { try node(id: $0) }
        try Self.checkLength(translations, "translations", ids.count)
        try Self.checkLength(labels, "labels", ids.count)
        try Self.checkLength(colors, "colors", ids.count)
        for (index, node) in nodes.enumerated() {
            let translation = translations?[index] ?? translation
            let color = colors?[index] ?? color
            if let label = labels?[index] ?? label {
                model.setLabel(label.isEmpty ? nil : label, of: node)
            }
            if let parentNode, !model.reparent(node, to: parentNode) {
                throw ToolError("\(id(for: node)) cannot move under \(parent ?? "") (it is the root, or that would make a cycle).")
            }
            try apply(to: node, model: model, translation: translation, rotationDegrees: rotationDegrees, scale: scale, color: color, metallic: metallic, roughness: roughness)
            if let isVisible {
                model.setVisible(isVisible, node)
            }
            if let isActive {
                model.setActive(isActive, node)
            }
        }
        return "Updated \(ids.joined(separator: ", "))."
    }

    /// Change the scene's environment; omitted fields are kept. background: none, color or environment (draws the environment map behind the scene). backgroundColor [r, g, b] linear 0 to 1 (sets background to color). backgroundBlur 0 (sharp) to 1. map: default or studio, the image-based lighting source (images can only be chosen by the user). intensity: image-based lighting strength, 1 is normal. rotationDegrees: turns the environment about +Y.
    @CollaborationTool
    func setEnvironment(background: String?, backgroundColor: [Double]?, backgroundBlur: Double?, map: String?, intensity: Double?, rotationDegrees: Double?) throws -> String {
        let model = try requireModel()
        var environment = model.environment
        if let backgroundColor {
            let color = try Self.vector(backgroundColor, name: "backgroundColor")
            environment.background = .color(SIMD4(color, 1))
        } else if let background {
            switch background.lowercased() {
            case "none":
                environment.background = .none
            case "color":
                if case .color = environment.background {
                    break
                }
                environment.background = .color([0.2, 0.2, 0.22, 1])
            case "environment":
                environment.background = .environment(blur: Float(backgroundBlur ?? 0))
            default:
                throw ToolError("Unknown background \(background). Use none, color or environment.")
            }
        }
        if let backgroundBlur {
            guard case .environment = environment.background else {
                throw ToolError("backgroundBlur needs the environment background.")
            }
            environment.background = .environment(blur: Float(min(max(backgroundBlur, 0), 1)))
        }
        if let map {
            switch map.lowercased() {
            case "default":
                environment.map = nil
            case "studio":
                environment.map = PBREnvironment.studio
            default:
                throw ToolError("Unknown map \(map). Use default or studio; the user can choose an image in the scene inspector.")
            }
        }
        if let intensity {
            environment.intensity = Float(max(intensity, 0))
        }
        if let rotationDegrees {
            environment.rotation = Float(rotationDegrees) * .pi / 180
        }
        model.setEnvironment(environment, actionName: "Environment")
        return try Self.json(Self.environmentInfo(environment))
    }

    private static func environmentInfo(_ environment: SceneGraph.Environment) -> EnvironmentInfo {
        var info = EnvironmentInfo(background: "none", map: "custom", intensity: environment.intensity, rotationDegrees: environment.rotation * 180 / .pi)
        switch environment.background {
        case .none:
            break
        case let .color(color):
            info.background = "color"
            info.backgroundColor = [color.x, color.y, color.z]
        case let .environment(blur):
            info.background = "environment"
            info.backgroundBlur = blur
        }
        if environment.map == nil {
            info.map = "default"
        } else if let map = environment.map as? PBREnvironment, map === PBREnvironment.studio {
            info.map = "studio"
        }
        return info
    }

    /// Move nodes straight up or down so the bottom of each one's world bounds rests at y = 0 (the floor), keeping x and z. Nodes without bounds (empty, lights, cameras) are left alone.
    @CollaborationTool
    func dropToFloor(ids: [String]) throws -> String {
        let model = try requireModel()
        let nodes = try ids.map { try editableNode(id: $0) }
        let dropped = nodes.filter { model.dropToFloor($0) }.map { id(for: $0) }
        return dropped.isEmpty ? "Nothing to move." : "Dropped \(dropped.joined(separator: ", "))."
    }

    /// Delete nodes and their children by id.
    @CollaborationTool
    func delete(ids: [String]) throws -> String {
        let model = try requireModel()
        let nodes = try ids.map { try editableNode(id: $0) }
        for node in nodes {
            guard node.parent != nil else {
                throw ToolError("The root cannot be deleted.")
            }
            model.delete(node)
        }
        return "Deleted \(ids.joined(separator: ", "))."
    }

    // MARK: - Ids

    func id(for node: SceneGraph.Node) -> String {
        guard node.parent != nil else {
            return "root"
        }
        if let id = idsByNode[ObjectIdentifier(node)] {
            return id
        }
        let id = "n\(nextID)"
        nextID += 1
        idsByNode[ObjectIdentifier(node)] = id
        nodesByID[id] = WeakNode(node: node)
        return id
    }

    func node(id: String) throws -> SceneGraph.Node {
        let model = try requireModel()
        if id == "root" {
            return model.sceneGraph.root
        }
        // Deleted nodes can come back with undo, so check the node is still in the scene.
        guard let node = nodesByID[id]?.node, node.isInSceneGraph(model.sceneGraph) else {
            throw ToolError("No node with id \(id). Call query for current ids.")
        }
        return node
    }

    private func editableNode(id: String) throws -> SceneGraph.Node {
        let node = try node(id: id)
        guard try !requireModel().isLocked(node) else {
            throw ToolError("\(id) is locked. Ask the user to unlock it.")
        }
        return node
    }

    // MARK: - Helpers

    private func requireModel() throws -> EditorModel {
        guard let model else {
            throw ToolError("The document is closed.")
        }
        return model
    }

    private func info(for node: SceneGraph.Node, model: EditorModel) -> NodeInfo {
        let trs = model.localTRS(of: node)
        var light: String?
        if case let .light(value) = node.content {
            light = "\(value.type.rawValue), intensity \(value.intensity)"
        }
        let bounds = model.sceneGraph.worldBounds(of: node)
        let color = model.materials(of: node).first.map { Self.array(EditorModel.baseColor(of: $0)) }
        return NodeInfo(
            id: id(for: node),
            parent: node.parent.map { id(for: $0) },
            label: node.displayName,
            kind: node.kindName,
            shape: node.shape.map { String(describing: $0) },
            light: light,
            isVisible: node.isVisible,
            isActive: node.isActive,
            isLocked: model.isLocked(node),
            translation: Self.array(trs.translation),
            rotationDegrees: Self.array(Self.eulerDegrees(trs.rotation)),
            scale: Self.array(trs.scale),
            color: color,
            worldBoundsMin: bounds.map { Self.array($0.min) },
            worldBoundsMax: bounds.map { Self.array($0.max) }
        )
    }

    private func apply(to node: SceneGraph.Node, model: EditorModel, translation: [Double]?, rotationDegrees: [Double]?, scale: [Double]?, color: [Double]?, metallic: Double?, roughness: Double?) throws {
        if translation != nil || rotationDegrees != nil || scale != nil {
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
        }
        guard color != nil || metallic != nil || roughness != nil else {
            return
        }
        let materials = model.materials(of: node)
        guard !materials.isEmpty else {
            throw ToolError("\(id(for: node)) has no mesh, so it has no material.")
        }
        let newColor = try color.map { try Self.vector($0, name: "color") }
        for (index, material) in materials.enumerated() {
            switch material {
            case var blinnPhong as BlinnPhongSceneMaterial:
                if let newColor {
                    blinnPhong.diffuse = .color(newColor)
                    model.setMaterial(blinnPhong, at: index, of: node)
                }
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

extension SceneGraph.Node {
    // Whether the node is `sceneGraph`'s root or one of its descendants.
    func isInSceneGraph(_ sceneGraph: SceneGraph) -> Bool {
        var current: SceneGraph.Node? = self
        while let node = current {
            if node === sceneGraph.root {
                return true
            }
            current = node.parent
        }
        return false
    }
}
