import GeometryLite3D
import SceneSprockets
import simd
import SwiftUI

extension EditorModel {
    // World-space bounds of every selected node, combined (#226). Nil when none has bounds (empty, light, camera,
    // hidden). Reads transformRevision, so it follows drags.
    var selectionWorldBounds: BoundingBox3D? {
        _ = transformRevision
        return selectedNodes.compactMap(sceneGraph.worldBounds(of:)).reduce(nil) { combined, bounds in
            guard let combined else {
                return bounds
            }
            return BoundingBox3D(min: simd.min(combined.min, bounds.min), max: simd.max(combined.max, bounds.max))
        }
    }
}

// Read-only world bounds of the selection. Its own view, so only it re-runs while dragging (#223).
struct BoundsSectionView: View {
    var model: EditorModel

    var body: some View {
        Section("Bounds") {
            if let bounds = model.selectionWorldBounds {
                LabeledContent("Min", value: Self.format(bounds.min))
                LabeledContent("Max", value: Self.format(bounds.max))
                LabeledContent("Size", value: Self.format(bounds.max - bounds.min))
                LabeledContent("Center", value: Self.format((bounds.min + bounds.max) / 2))
            } else {
                LabeledContent("Bounds", value: "None")
            }
        }
        .monospacedDigit()
    }

    private static func format(_ value: SIMD3<Float>) -> String {
        [value.x, value.y, value.z].map { $0.formatted(.number.precision(.fractionLength(3))) }.joined(separator: ", ")
    }
}
