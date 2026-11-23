import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd
import SwiftUI

/// Handles on the control points of a node's ``SceneGraph/Node/path``, which move the points (#619).
///
/// Each point is a small square, the same size on screen at any distance. Dragging a point moves it in the plane that
/// faces the camera through it, and writes a new path to the node. Pass the gizmo to `SceneView`'s
/// `sceneManipulator(_:)`, as with ``TransformGizmo``.
@MainActor
public final class PathPointGizmo: ViewManipulator {
    /// The node whose path the handles edit.
    public var target: SceneGraph.Node?
    /// The size of a point's square, in view points.
    public var handleSize: Float = 10
    /// How close a click must be to a point to pick it, in view points.
    public var hitDistance: Float = 10
    /// The point under the pointer, if any.
    public private(set) var hoveredIndex: Int?
    /// The point that the user drags now, if any.
    public private(set) var activeIndex: Int?
    /// Called with the target when a drag starts, for example to record an undo step.
    public var onBegin: ((SceneGraph.Node) -> Void)?
    /// Called with the target after each change during a drag.
    public var onChange: ((SceneGraph.Node) -> Void)?
    /// Called with the target when a drag ends.
    public var onEnd: ((SceneGraph.Node) -> Void)?

    // The dragged point, the camera-facing plane through it, and where the drag started on that plane, in world space.
    private var drag: (index: Int, normal: SIMD3<Float>, startPoint: SIMD3<Float>, startHit: SIMD3<Float>)?

    /// Creates the gizmo.
    ///
    /// - Parameter target: The node whose path to edit.
    public init(target: SceneGraph.Node? = nil) {
        self.target = target
    }

    // The path's points in world space; empty without a target or path.
    func worldPoints() -> [SIMD3<Float>] {
        guard let target, let path = target.path else {
            return []
        }
        let world = target.worldTransform
        return path.points.map { (world * SIMD4($0, 1)).xyz }
    }

    // The nearest point within `hitDistance` of a view point.
    func index(at point: SIMD2<Float>, viewport: Viewport) -> Int? {
        var best: (index: Int, distance: Float)?
        for (index, world) in worldPoints().enumerated() {
            guard let projected = viewport.project(world) else {
                continue
            }
            let distance = simd_distance(SIMD2(projected.x, projected.y), point)
            if distance <= hitDistance, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    public func hitTest(_ point: SIMD2<Float>, viewport: Viewport) -> Bool {
        hoveredIndex = index(at: point, viewport: viewport)
        return hoveredIndex != nil
    }

    public func beginDrag(at point: SIMD2<Float>, viewport: Viewport) {
        guard let target, let index = index(at: point, viewport: viewport) else {
            return
        }
        let start = worldPoints()[index]
        let normal = -simd_normalize(viewport.cameraMatrix.columns.2.xyz)
        guard let hit = TransformGizmo.intersect(viewport.ray(through: point), planeOrigin: start, normal: normal) else {
            return
        }
        drag = (index, normal, start, hit)
        activeIndex = index
        onBegin?(target)
    }

    public func drag(to point: SIMD2<Float>, viewport: Viewport) {
        guard let target, let drag, let path = target.path, path.points.indices.contains(drag.index),
              let hit = TransformGizmo.intersect(viewport.ray(through: point), planeOrigin: drag.startPoint, normal: drag.normal)
        else {
            return
        }
        let world = drag.startPoint + (hit - drag.startHit)
        var points = path.points
        points[drag.index] = (target.worldTransform.inverse * SIMD4(world, 1)).xyz
        target.path = SceneGraph.Spline(points: points, isClosed: path.isClosed)
        onChange?(target)
    }

    public func endDrag() {
        if let target, drag != nil {
            onEnd?(target)
        }
        drag = nil
        activeIndex = nil
    }

    // swiftlint:disable:next unneeded_throws_rethrows
    public func overlay(viewport: Viewport) throws -> AnyElement? {
        let points = worldPoints()
        guard !points.isEmpty else {
            return nil
        }
        let cameraPosition = viewport.cameraMatrix.columns.3.xyz
        let right = simd_normalize(viewport.cameraMatrix.columns.0.xyz)
        let up = simd_normalize(viewport.cameraMatrix.columns.1.xyz)
        let highlighted = activeIndex ?? hoveredIndex
        var context = GraphicsContext3D()
        for (index, point) in points.enumerated() {
            // Drawn camera-relative, like TransformGizmo, for precision far from the origin.
            let center = point - cameraPosition
            let half = handleSize * 0.5 * viewport.worldSizeOfPoint(at: point)
            let square = Path3D { path in
                path.move(to: center - (right + up) * half)
                path.addLine(to: center + (right - up) * half)
                path.addLine(to: center + (right + up) * half)
                path.addLine(to: center + (up - right) * half)
                path.closeSubpath()
            }
            context.fill(square, with: index == highlighted ? .yellow : .white)
            context.stroke(square, with: .black.opacity(0.6), lineWidth: 1)
        }
        return GraphicsContext3DRenderPipeline(context: context, viewProjection: viewport.projectionMatrix * viewport.rotationOnlyViewMatrix, viewport: viewport.drawableSize, depthCompareFunction: .always, writesDepth: false).eraseToAnyElement()
    }
}
