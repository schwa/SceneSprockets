import Foundation
import SceneSprockets
import SceneSprocketsGizmos
import simd

// Editor state saved as editor.json next to scene.json, so readers of the scene can ignore it. Every field is
// optional when read, so older or partial files still load.
struct EditorState: Equatable {
    static let fileName = "editor.json"

    var cameraMatrix = EditorCamera().matrix
    var cameraTarget = EditorCamera().target
    var renderSettings = RenderSettings()
    var gizmoMode = TransformGizmo.Mode.translate
    var gizmoSpace = TransformGizmo.Space.world
    // Child indices from the root; node ids do not survive a reload.
    var selectionPath: [Int]?
    // Every selected node's path, the primary (`selectionPath`) last (#205). Empty in files from before multiple
    // selection, which then restore just `selectionPath`.
    var selectedPaths: [[Int]] = []
    var isInspectorPresented = true
    // Child-index paths of locked nodes (#192).
    var lockedPaths: [[Int]] = []

    static func read(fromBundleAt url: URL) -> Self? {
        guard let data = try? Data(contentsOf: url.appendingPathComponent(fileName)) else {
            return nil
        }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func write(toBundleAt url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url.appendingPathComponent(Self.fileName))
    }
}

extension EditorState: Codable {
    enum CodingKeys: String, CodingKey {
        case cameraMatrix, cameraTarget, renderSettings, gizmoMode, gizmoSpace, selectionPath, selectedPaths, isInspectorPresented, lockedPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self()
        let columns = try container.decodeIfPresent([SIMD4<Float>].self, forKey: .cameraMatrix)
        cameraMatrix = columns.flatMap { $0.count == 4 ? simd_float4x4($0) : nil } ?? defaults.cameraMatrix
        cameraTarget = try container.decodeIfPresent(SIMD3<Float>.self, forKey: .cameraTarget) ?? defaults.cameraTarget
        renderSettings = try container.decodeIfPresent(RenderSettings.self, forKey: .renderSettings) ?? defaults.renderSettings
        gizmoMode = try container.decodeIfPresent(String.self, forKey: .gizmoMode).flatMap(TransformGizmo.Mode.init(rawValue:)) ?? defaults.gizmoMode
        gizmoSpace = try container.decodeIfPresent(String.self, forKey: .gizmoSpace).flatMap(TransformGizmo.Space.init(rawValue:)) ?? defaults.gizmoSpace
        selectionPath = try container.decodeIfPresent([Int].self, forKey: .selectionPath)
        selectedPaths = try container.decodeIfPresent([[Int]].self, forKey: .selectedPaths) ?? []
        isInspectorPresented = try container.decodeIfPresent(Bool.self, forKey: .isInspectorPresented) ?? defaults.isInspectorPresented
        lockedPaths = try container.decodeIfPresent([[Int]].self, forKey: .lockedPaths) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode([cameraMatrix.columns.0, cameraMatrix.columns.1, cameraMatrix.columns.2, cameraMatrix.columns.3], forKey: .cameraMatrix)
        try container.encode(cameraTarget, forKey: .cameraTarget)
        try container.encode(renderSettings, forKey: .renderSettings)
        try container.encode(gizmoMode.rawValue, forKey: .gizmoMode)
        try container.encode(gizmoSpace.rawValue, forKey: .gizmoSpace)
        try container.encodeIfPresent(selectionPath, forKey: .selectionPath)
        if !selectedPaths.isEmpty {
            try container.encode(selectedPaths, forKey: .selectedPaths)
        }
        try container.encode(isInspectorPresented, forKey: .isInspectorPresented)
        if !lockedPaths.isEmpty {
            try container.encode(lockedPaths, forKey: .lockedPaths)
        }
    }
}

extension RenderSettings: Codable {
    enum CodingKeys: String, CodingKey {
        case showsGrid, showsAxes, showsXAxis, showsYAxis, showsZAxis, usesDefaultLighting, showsShadows, showsStatistics, showsFrameTiming, showsLightsAndCameras, boundingBoxes, outlinesSelection, isFramebufferOnly, fieldOfView, nearClip, farClip, debugMode, materialChannel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        func read<Value: Decodable>(_ keyPath: WritableKeyPath<Self, Value>, _ key: CodingKeys) throws {
            if let value = try container.decodeIfPresent(Value.self, forKey: key) {
                self[keyPath: keyPath] = value
            }
        }
        try read(\.showsGrid, .showsGrid)
        try read(\.showsAxes, .showsAxes)
        try read(\.showsXAxis, .showsXAxis)
        try read(\.showsYAxis, .showsYAxis)
        try read(\.showsZAxis, .showsZAxis)
        try read(\.usesDefaultLighting, .usesDefaultLighting)
        try read(\.showsShadows, .showsShadows)
        try read(\.showsStatistics, .showsStatistics)
        try read(\.showsFrameTiming, .showsFrameTiming)
        try read(\.showsLightsAndCameras, .showsLightsAndCameras)
        try read(\.boundingBoxes, .boundingBoxes)
        try read(\.outlinesSelection, .outlinesSelection)
        try read(\.isFramebufferOnly, .isFramebufferOnly)
        try read(\.fieldOfView, .fieldOfView)
        try read(\.nearClip, .nearClip)
        try read(\.farClip, .farClip)
        debugMode = try container.decodeIfPresent(SceneGraphDebugMode.self, forKey: .debugMode)
        materialChannel = try container.decodeIfPresent(SceneGraphMaterialChannel.self, forKey: .materialChannel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsGrid, forKey: .showsGrid)
        try container.encode(showsAxes, forKey: .showsAxes)
        try container.encode(showsXAxis, forKey: .showsXAxis)
        try container.encode(showsYAxis, forKey: .showsYAxis)
        try container.encode(showsZAxis, forKey: .showsZAxis)
        try container.encode(usesDefaultLighting, forKey: .usesDefaultLighting)
        try container.encode(showsShadows, forKey: .showsShadows)
        try container.encode(showsStatistics, forKey: .showsStatistics)
        try container.encode(showsFrameTiming, forKey: .showsFrameTiming)
        try container.encode(showsLightsAndCameras, forKey: .showsLightsAndCameras)
        try container.encode(boundingBoxes, forKey: .boundingBoxes)
        try container.encode(outlinesSelection, forKey: .outlinesSelection)
        try container.encode(isFramebufferOnly, forKey: .isFramebufferOnly)
        try container.encode(fieldOfView, forKey: .fieldOfView)
        try container.encode(nearClip, forKey: .nearClip)
        try container.encode(farClip, forKey: .farClip)
        try container.encodeIfPresent(debugMode, forKey: .debugMode)
        try container.encodeIfPresent(materialChannel, forKey: .materialChannel)
    }
}

extension EditorModel {
    var editorState: EditorState {
        EditorState(
            cameraMatrix: camera.matrix,
            cameraTarget: camera.target,
            renderSettings: renderSettings,
            gizmoMode: gizmoMode,
            gizmoSpace: gizmoSpace,
            selectionPath: selectedNode.flatMap(Self.path(to:)),
            selectedPaths: (selectedNodes.filter { $0 !== selectedNode } + [selectedNode].compactMap(\.self)).compactMap(Self.path(to:)),
            isInspectorPresented: isInspectorPresented,
            lockedPaths: sceneGraph.nodesWithWorldTransforms(includeHidden: true).map(\.node).filter { lockedNodes.contains($0.id) }.compactMap(Self.path(to:))
        )
    }

    func apply(_ state: EditorState) {
        camera.matrix = state.cameraMatrix
        camera.target = state.cameraTarget
        renderSettings = state.renderSettings
        gizmoMode = state.gizmoMode
        gizmoSpace = state.gizmoSpace
        isInspectorPresented = state.isInspectorPresented
        restoreLockedNodes(Set(state.lockedPaths.compactMap(node(atPath:)).map(\.id)))
        let primary = state.selectionPath.flatMap(node(atPath:))?.id
        let selected = state.selectedPaths.compactMap(node(atPath:)).map(\.id)
        if selected.count > 1 {
            select(selected, primary: primary)
        } else {
            selection = primary
        }
    }

    private static func path(to node: SceneGraph.Node) -> [Int]? {
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

    private func node(atPath path: [Int]) -> SceneGraph.Node? {
        var node = sceneGraph.root
        for index in path {
            guard node.children.indices.contains(index) else {
                return nil
            }
            node = node.children[index]
        }
        return node
    }
}
