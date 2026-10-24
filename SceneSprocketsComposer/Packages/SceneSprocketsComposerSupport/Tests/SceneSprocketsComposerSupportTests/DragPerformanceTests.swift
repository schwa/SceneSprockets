import Foundation
import Observation
import GeometryLite3D
import SceneSprockets
@testable import SceneSprocketsComposerSupport
import simd
import Testing

// #223: tree rows (name, eye, lock, dimming) and the Default Lighting row must not depend on drag steps, or every row
// re-renders on every frame of a drag.
@MainActor
@Test func treeRowStateIgnoresDrags() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    model.addShape(.box(), label: "Box")
    let node = try #require(model.selectedNode)
    nonisolated(unsafe) var changed = false
    withObservationTracking {
        _ = model.isHidden(node)
        _ = model.isVisible(node)
        _ = model.isActive(node)
        _ = model.isLocked(node)
        _ = model.isDefaultLightingActive
        _ = model.treeSelection
    } onChange: {
        changed = true
    }
    model.beginGizmoDrag(node)
    node.localTransform = .trs(.init(translation: [1, 0, 0]))
    model.continueGizmoDrag(node)
    model.endGizmoDrag(node)
    #expect(!changed)

    // Visibility changes still reach the rows.
    withObservationTracking {
        _ = model.isHidden(node)
    } onChange: {
        changed = true
    }
    model.setVisible(false, node)
    #expect(changed)
}

// #215: what a gizmo drag costs on the main thread each frame, outside SwiftUI. Reports milliseconds per call so the
// expensive parts stand out; the bound is generous and only catches regressions.
@MainActor
@Test func dragFrameCosts() throws {
    let model = EditorModel(sceneGraph: SceneGraph.empty())
    let tools = SceneTools(model: model)
    let ids = try tools.create(kind: "box", count: 500, label: nil, parent: nil, translation: nil, translations: (0..<500).map { [Double($0 % 25), 0, Double($0 / 25)] }, rotationDegrees: nil, scale: nil, color: nil).components(separatedBy: ", ")
    let nodes = try ids.map { try tools.node(id: $0) }
    model.select([nodes[0].id, nodes[1].id, nodes[2].id], primary: nodes[0].id)
    let viewport = SceneViewport(
        cameraMatrix: LookAt(position: [0, 10, 30], target: .zero, up: [0, 1, 0]).cameraMatrix,
        projectionMatrix: PerspectiveProjection(verticalAngleOfView: .degrees(60)).projectionMatrix(aspectRatio: 1.5),
        viewSize: [1200, 800],
        drawableSize: [2400, 1600]
    )

    func milliseconds(_ iterations: Int = 60, _ work: () -> Void) -> Double {
        let start = ContinuousClock.now
        for _ in 0..<iterations {
            work()
        }
        let elapsed = ContinuousClock.now - start
        return (Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18) * 1_000 / Double(iterations)
    }

    model.beginGizmoDrag(nodes[0])
    var step: Float = 0
    let costs: [(String, Double)] = [
        ("continueGizmoDrag", milliseconds {
            step += 0.01
            nodes[0].localTransform = .trs(.init(translation: [step, 0, 0]))
            model.continueGizmoDrag(nodes[0])
        }),
        ("editorState", milliseconds { _ = model.editorState }),
        ("selectedNodes", milliseconds { _ = model.selectedNodes }),
        ("isHidden x500", milliseconds { nodes.forEach { _ = model.isHidden($0) } }),
        ("DebugShapes.shapes", milliseconds { _ = DebugShapes.shapes(sceneGraph: model.sceneGraph, viewport: viewport) }),
        ("BoundingBoxes all", milliseconds { _ = BoundingBoxes.nodes(mode: .all, sceneGraph: model.sceneGraph, selected: model.selectedIDs).compactMap { model.sceneGraph.worldBounds(of: $0.node) } }),
        ("statistics", milliseconds { _ = model.sceneGraph.statistics }),
    ]
    model.endGizmoDrag(nodes[0])
    let report = costs.map { "\($0.0): \($0.1.formatted(.number.precision(.fractionLength(3)))) ms" }.joined(separator: ", ")
    print("DRAG COSTS \(report)")
    // A frame is 8 ms at 120 Hz. Anything here near that is the problem.
    for (name, cost) in costs {
        #expect(cost < 8, "\(name) \(cost) ms; \(report)")
    }
}
