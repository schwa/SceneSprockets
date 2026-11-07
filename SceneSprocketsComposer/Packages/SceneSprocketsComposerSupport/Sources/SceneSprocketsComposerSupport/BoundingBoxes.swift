import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd
import SwiftUI

// World-space bounding boxes drawn as wireframes in the scene pass (#211), like DebugShapes (#188). Hidden and
// inactive nodes have no bounds, so they draw nothing.
enum BoundingBoxes {
    enum Mode: String, CaseIterable, Identifiable, Codable {
        case none = "None"
        case selected = "Selected"
        case all = "All Meshes"

        var id: Self { self }
    }

    // The nodes to box: the selected ones, plus every mesh node for `.all`.
    @MainActor
    static func nodes(mode: Mode, sceneGraph: SceneGraph, selected: Set<SceneGraph.Node.ID>) -> [(node: SceneGraph.Node, isSelected: Bool)] {
        guard mode != .none else {
            return []
        }
        return sceneGraph.nodesWithWorldTransforms().map(\.node).compactMap { node in
            let isSelected = selected.contains(node.id)
            var isMesh = false
            if case .mesh = node.content {
                isMesh = true
            }
            guard isSelected || (mode == .all && isMesh), node.parent != nil else {
                return nil
            }
            return (node, isSelected)
        }
    }

    // The 12 edges of `bounds`.
    static func edges(_ bounds: BoundingBox3D) -> [(SIMD3<Float>, SIMD3<Float>)] {
        let (low, high) = (bounds.min, bounds.max)
        let corners: [SIMD3<Float>] = (0..<8).map { index in
            [index & 1 == 0 ? low.x : high.x, index & 2 == 0 ? low.y : high.y, index & 4 == 0 ? low.z : high.z]
        }
        // Pairs of corners that differ in exactly one axis.
        return (0..<8).flatMap { a in
            [1, 2, 4].compactMap { bit in a & bit == 0 ? (corners[a], corners[a | bit]) : nil }
        }
    }

    @MainActor
    static func element(mode: Mode, sceneGraph: SceneGraph, selected: Set<SceneGraph.Node.ID>, selectedColor: SwiftUI.Color, viewProjection: simd_float4x4, drawableSize: SIMD2<Float>) -> AnyElement? {
        let boxes = nodes(mode: mode, sceneGraph: sceneGraph, selected: selected).compactMap { entry in
            sceneGraph.worldBounds(of: entry.node).map { ($0, entry.isSelected) }
        }
        guard !boxes.isEmpty else {
            return nil
        }
        var context = GraphicsContext3D()
        for (bounds, isSelected) in boxes {
            let path = Path3D { path in
                for (start, end) in edges(bounds) {
                    path.move(to: start)
                    path.addLine(to: end)
                }
            }
            context.stroke(path, with: isSelected ? selectedColor : SwiftUI.Color.white.opacity(0.35), lineWidth: isSelected ? 2 : 1)
        }
        return GraphicsContext3DRenderPipeline(context: context, viewProjection: viewProjection, viewport: drawableSize, depthCompareFunction: .always, writesDepth: false).eraseToAnyElement()
    }
}
