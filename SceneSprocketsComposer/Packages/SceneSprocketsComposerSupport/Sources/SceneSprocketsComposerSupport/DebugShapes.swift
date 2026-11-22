import MetalSprockets
import SceneSprockets
import SceneSprocketsGizmos
import simd

// Line drawings for lights and cameras, which have no geometry of their own, so they can be seen and clicked (#188).
// Drawn by SceneSprocketsGizmos' EditorGizmos (#406); sizes are in view points, so they stay the same size on screen.
enum DebugShapes {
    struct Shape {
        var node: SceneGraph.Node
        // World-space polylines.
        var lines: [[SIMD3<Float>]]
    }

    @MainActor
    static func shapes(sceneGraph: SceneGraph, viewport: Viewport) -> [Shape] {
        EditorGizmos.shapes(sceneGraph: sceneGraph, viewport: viewport, options: .lightsAndCameras).compactMap { shape in
            shape.node.map { Shape(node: $0, lines: shape.lines) }
        }
    }

    @MainActor
    static func element(sceneGraph: SceneGraph, selected: Set<SceneGraph.Node.ID>, viewport: Viewport) -> AnyElement? {
        try? EditorGizmos.element(sceneGraph: sceneGraph, viewport: viewport, options: .lightsAndCameras, selected: selected)
    }

    // The node whose shape passes within EditorGizmos.hitDistance points of `point`, nearest first.
    @MainActor
    static func hitTest(_ point: SIMD2<Float>, sceneGraph: SceneGraph, viewport: Viewport) -> SceneGraph.Node? {
        EditorGizmos.hitTest(point, sceneGraph: sceneGraph, viewport: viewport)
    }
}
