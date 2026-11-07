import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd
import SwiftUI

/// Handles that move, rotate and scale one node, like three.js `TransformControls`.
///
/// The gizmo draws its handles at a constant size on screen with MetalSprocketsAddOns' `GraphicsContext3D`. Pass it to
/// `SceneView(manipulator:)`. It also responds to pinch and twist gestures.
@MainActor
public final class TransformGizmo: SceneViewManipulator {
    /// The kind of change that the handles make.
    public enum Mode: String, CaseIterable, Sendable {
        /// The handles move the node.
        case translate
        /// The handles rotate the node.
        case rotate
        /// The handles scale the node.
        case scale
    }

    /// The axes that the handles follow.
    public enum Space: String, CaseIterable, Sendable {
        /// The handles follow the world axes.
        case world
        /// The handles follow the node's rotation.
        case local
    }

    /// An axis of the gizmo.
    public enum Axis: Int, CaseIterable, Sendable {
        /// The x axis.
        case x
        /// The y axis.
        case y
        /// The z axis.
        case z

        // The axes after this one, in x, y, z order, wrapping around.
        var next: Self {
            switch self {
            case .x: .y
            case .y: .z
            case .z: .x
            }
        }

        var afterNext: Self {
            next.next
        }

        var vector: SIMD3<Float> {
            switch self {
            case .x: [1, 0, 0]
            case .y: [0, 1, 0]
            case .z: [0, 0, 1]
            }
        }
    }

    /// A part of the gizmo that the user can drag.
    public enum Handle: Equatable, Sendable {
        /// The handle along an axis, or the rotation ring about it.
        case axis(Axis)
        /// The handle for the plane perpendicular to the axis.
        case plane(Axis)
        /// The center handle. It moves the node in the view plane, scales it uniformly, or rotates it freely
        /// (trackball) inside the rings.
        case center
        /// The rotation ring that faces the camera. It rotates about the view direction.
        case view
    }

    /// The step sizes that drags snap to. A `nil` step does not snap.
    public struct Snapping: Sendable {
        /// The step for moves, in world units.
        public var translation: Float?
        /// The step for rotations, in radians.
        public var rotation: Float?
        /// The step for scale factors.
        public var scale: Float?

        /// Creates snapping steps. A `nil` step does not snap.
        public init(translation: Float? = nil, rotation: Float? = nil, scale: Float? = nil) {
            self.translation = translation
            self.rotation = rotation
            self.scale = scale
        }
    }

    /// The node that the gizmo edits. If `nil`, the gizmo is hidden.
    public var target: SceneGraph.Node?
    /// The kind of change that the handles make.
    public var mode: Mode = .translate
    /// The axes that the handles follow.
    public var space: Space = .world
    /// The step sizes that drags snap to.
    public var snapping = Snapping()
    /// The length of the axis handles, in view points.
    public var size: Float = 110
    /// The length of the axis handles in world units, which replaces ``size``.
    ///
    /// When set, the gizmo gets bigger and smaller with the camera distance, like the scene.
    public var worldSize: Float?
    /// The handle under the pointer, if any.
    public private(set) var hoveredHandle: Handle?
    /// The handle that the user drags now, if any.
    public private(set) var activeHandle: Handle?
    /// Called with the target when a drag starts, for example to record an undo step.
    public var onBegin: ((SceneGraph.Node) -> Void)?
    /// Called with the target after each change during a drag.
    public var onChange: ((SceneGraph.Node) -> Void)?
    /// Called with the target when a drag ends.
    public var onEnd: ((SceneGraph.Node) -> Void)?

    private var drag: DragState?
    // The target's scale and world orientation when a pinch or twist started.
    private var twoFingerStart: (scale: SIMD3<Float>, orientation: simd_quatf, cameraForward: SIMD3<Float>)?

    /// Creates a transform gizmo.
    ///
    /// - Parameters:
    ///   - target: The node to edit.
    ///   - mode: The kind of change that the handles make.
    ///   - space: The axes that the handles follow.
    public init(target: SceneGraph.Node? = nil, mode: Mode = .translate, space: Space = .world) {
        self.target = target
        self.mode = mode
        self.space = space
    }

    // MARK: Geometry

    // Where the handles are this frame.
    struct Frame {
        var origin: SIMD3<Float>
        // World directions of the gizmo's x, y and z axes.
        var axes: [SIMD3<Float>]
        // World length of an axis handle.
        var length: Float
        var cameraForward: SIMD3<Float>
        var cameraRight: SIMD3<Float> = [1, 0, 0]
        var cameraUp: SIMD3<Float> = [0, 1, 0]

        func axis(_ axis: Axis) -> SIMD3<Float> {
            axes[axis.rawValue]
        }
    }

    func frame(viewport: SceneViewport) -> Frame? {
        guard let target else {
            return nil
        }
        let world = target.worldTransform
        let origin = world.columns.3.xyz
        let axes: [SIMD3<Float>] = switch space {
        case .world: Axis.allCases.map(\.vector)
        case .local: [world.columns.0.xyz, world.columns.1.xyz, world.columns.2.xyz].map { simd_length($0) > 0 ? simd_normalize($0) : [0, 0, 0] }
        }
        let forward = -simd_normalize(viewport.cameraMatrix.columns.2.xyz)
        return Frame(origin: origin, axes: axes, length: worldSize ?? size * viewport.worldSizeOfPoint(at: origin), cameraForward: forward, cameraRight: simd_normalize(viewport.cameraMatrix.columns.0.xyz), cameraUp: simd_normalize(viewport.cameraMatrix.columns.1.xyz))
    }

    // World polylines for each handle, for drawing and hit testing. Planes are closed quads.
    func outlines(_ frame: Frame) -> [(handle: Handle, points: [SIMD3<Float>])] {
        let o = frame.origin, length = frame.length
        switch mode {
        case .translate, .scale:
            var result: [(Handle, [SIMD3<Float>])] = Axis.allCases.map { axis in (.axis(axis), [o, o + frame.axis(axis) * length]) }
            if mode == .translate {
                for axis in Axis.allCases {
                    let u = frame.axis(axis.next) * length * 0.25
                    let v = frame.axis(axis.afterNext) * length * 0.25
                    let corner = o + (u + v) * 0.6
                    result.append((.plane(axis), [corner, corner + u * 0.8, corner + u * 0.8 + v * 0.8, corner + v * 0.8]))
                }
            }
            return result
        case .rotate:
            var result: [(Handle, [SIMD3<Float>])] = Axis.allCases.map { axis in
                let u = frame.axis(axis.next)
                let v = frame.axis(axis.afterNext)
                return (.axis(axis), Self.circle(center: o, u: u, v: v, radius: length * 0.9))
            }
            result.append((.view, Self.circle(center: o, u: frame.cameraRight, v: frame.cameraUp, radius: length * 1.1)))
            return result
        }
    }

    static func circle(center: SIMD3<Float>, u: SIMD3<Float>, v: SIMD3<Float>, radius: Float) -> [SIMD3<Float>] {
        (0 ... 64).map { index in
            let angle = Float(index) / 64 * 2 * .pi
            return center + (u * cos(angle) + v * sin(angle)) * radius
        }
    }

    // 1 for a handle seen well; fades to 0 for an axis pointing at the camera (it collapses to a dot) and a plane seen
    // edge-on. Rings stay visible: their back halves are dimmed instead (see `ringRuns`).
    func opacity(of handle: Handle, frame: Frame) -> Float {
        let facing: Float
        switch (mode, handle) {
        case (.rotate, _), (_, .center), (_, .view):
            return 1
        case (_, .axis(let axis)):
            facing = 1 - abs(simd_dot(frame.axis(axis), frame.cameraForward))
        case (_, .plane(let axis)):
            facing = abs(simd_dot(frame.axis(axis), frame.cameraForward))
        }
        // Fully faded below 0.05, fully shown above 0.2.
        return simd_clamp((facing - 0.05) / 0.15, 0, 1)
    }

    // A ring split into runs of consecutive points, each in front of the gizmo's center (towards the camera) or
    // behind it.
    static func ringRuns(_ points: [SIMD3<Float>], frame: Frame) -> [(isFront: Bool, points: [SIMD3<Float>])] {
        var runs: [(isFront: Bool, points: [SIMD3<Float>])] = []
        for point in points {
            // A small tolerance keeps a ring facing the camera in one run despite rounding.
            let isFront = simd_dot(point - frame.origin, frame.cameraForward) <= frame.length * 1e-4
            if let last = runs.last, last.isFront == isFront {
                runs[runs.count - 1].points.append(point)
            } else {
                // Share the boundary point so the runs meet.
                var run = [point]
                if let previous = runs.last?.points.last {
                    run.insert(previous, at: 0)
                }
                runs.append((isFront, run))
            }
        }
        return runs
    }

    // The handle under `point` (view points), nearest first; nil when none is within reach.
    func handle(at point: SIMD2<Float>, viewport: SceneViewport) -> Handle? {
        guard let frame = frame(viewport: viewport) else {
            return nil
        }
        let reach: Float = 9
        if let center = viewport.project(frame.origin), simd_distance(center.xy, point) < reach * 1.4, mode != .rotate {
            return .center
        }
        // Rings seen edge-on project to lines through the center; near the center the trackball wins over them.
        if mode == .rotate, let distance = trackballDistance(point, frame: frame, viewport: viewport), distance < 0.6 {
            return .center
        }
        var best: (handle: Handle, score: Float)?
        for (handle, points) in outlines(frame) where opacity(of: handle, frame: frame) > 0 {
            let projected = points.compactMap { viewport.project($0)?.xy }
            guard projected.count == points.count else {
                continue
            }
            let distance: Float
            if case .plane = handle {
                distance = Self.contains(projected, point) ? 0 : .infinity
            } else {
                distance = zip(projected, projected.dropFirst()).map { Self.distance(point, segment: ($0, $1)) }.min() ?? .infinity
            }
            // Rings seen edge-on overlap the others and are hard to drag (their plane hides the pointer), so a ring
            // facing the camera wins a tie.
            var score = distance
            if mode == .rotate, case let .axis(axis) = handle {
                score += (1 - abs(simd_dot(frame.axis(axis), frame.cameraForward))) * reach
            }
            if distance < reach, score < best?.score ?? .infinity {
                best = (handle, score)
            }
        }
        if best == nil, mode == .rotate, let distance = trackballDistance(point, frame: frame, viewport: viewport), distance < 1 {
            return .center
        }
        return best?.handle
    }

    // Distance of `point` from the gizmo's center on screen, as a fraction of the axis rings' radius.
    private func trackballDistance(_ point: SIMD2<Float>, frame: Frame, viewport: SceneViewport) -> Float? {
        guard let center = viewport.project(frame.origin)?.xy, let edge = viewport.project(frame.origin + frame.cameraRight * frame.length * 0.9)?.xy else {
            return nil
        }
        return simd_distance(point, center) / max(simd_distance(edge, center), 1)
    }

    static func distance(_ point: SIMD2<Float>, segment: (SIMD2<Float>, SIMD2<Float>)) -> Float {
        let (a, b) = segment
        let ab = b - a
        let t = simd_clamp(simd_dot(point - a, ab) / max(simd_length_squared(ab), .ulpOfOne), 0, 1)
        return simd_distance(point, a + ab * t)
    }

    static func contains(_ polygon: [SIMD2<Float>], _ point: SIMD2<Float>) -> Bool {
        var inside = false
        var previous = polygon[polygon.count - 1]
        for current in polygon {
            if (current.y > point.y) != (previous.y > point.y), point.x < (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x {
                inside.toggle()
            }
            previous = current
        }
        return inside
    }

    // MARK: Dragging

    struct DragState {
        var handle: Handle
        var frame: Frame
        var startPoint: SIMD2<Float>
        var startWorldPosition: SIMD3<Float>
        var startWorldOrientation: simd_quatf
        var startScale: SIMD3<Float>
        // Where the drag started on the handle's line or plane.
        var startHit: SIMD3<Float>?
    }

    // Closest point on the line through `origin` along `direction` to `ray`, as a distance along the line.
    // GeometryLite3D.Ray3D: visionOS's Spatial framework also has a Ray3D.
    static func closestParameter(origin: SIMD3<Float>, direction: SIMD3<Float>, ray: GeometryLite3D.Ray3D) -> Float? {
        let w = origin - ray.origin
        let b = simd_dot(direction, ray.direction)
        let denominator = 1 - b * b
        guard abs(denominator) > 1e-5 else {
            return nil
        }
        return (b * simd_dot(ray.direction, w) - simd_dot(direction, w)) / denominator
    }

    static func intersect(_ ray: GeometryLite3D.Ray3D, planeOrigin: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float>? {
        let denominator = simd_dot(normal, ray.direction)
        guard abs(denominator) > 1e-5 else {
            return nil
        }
        let t = simd_dot(planeOrigin - ray.origin, normal) / denominator
        return t >= 0 ? ray.origin + ray.direction * t : nil
    }

    static func snap(_ value: Float, step: Float?) -> Float {
        guard let step, step > 0 else {
            return value
        }
        return (value / step).rounded() * step
    }

    // The point on the handle's line or plane under `point`.
    func hit(_ handle: Handle, frame: Frame, point: SIMD2<Float>, viewport: SceneViewport) -> SIMD3<Float>? {
        let ray = viewport.ray(through: point)
        switch (mode, handle) {
        case (.rotate, .axis(let axis)):
            return Self.intersect(ray, planeOrigin: frame.origin, normal: frame.axis(axis))
        case (.rotate, .view):
            return Self.intersect(ray, planeOrigin: frame.origin, normal: frame.cameraForward)
        case (.rotate, .center):
            return nil
        case (_, .axis(let axis)):
            return Self.closestParameter(origin: frame.origin, direction: frame.axis(axis), ray: ray).map { frame.origin + frame.axis(axis) * $0 }
        case (_, .plane(let axis)):
            return Self.intersect(ray, planeOrigin: frame.origin, normal: frame.axis(axis))
        case (_, .center), (_, .view):
            return Self.intersect(ray, planeOrigin: frame.origin, normal: frame.cameraForward)
        }
    }

    public func hitTest(_ point: SIMD2<Float>, viewport: SceneViewport) -> Bool {
        hoveredHandle = handle(at: point, viewport: viewport)
        return hoveredHandle != nil
    }

    public func beginDrag(at point: SIMD2<Float>, viewport: SceneViewport) {
        guard let target, let frame = frame(viewport: viewport), let handle = handle(at: point, viewport: viewport) else {
            return
        }
        drag = DragState(handle: handle, frame: frame, startPoint: point, startWorldPosition: target.worldPosition, startWorldOrientation: target.worldOrientation, startScale: target.trs.scale, startHit: hit(handle, frame: frame, point: point, viewport: viewport))
        activeHandle = handle
        onBegin?(target)
    }

    public func drag(to point: SIMD2<Float>, viewport: SceneViewport) {
        guard let target, let drag else {
            return
        }
        let frame = drag.frame
        switch mode {
        case .translate:
            guard let start = drag.startHit, let current = hit(drag.handle, frame: frame, point: point, viewport: viewport) else {
                return
            }
            var delta = current - start
            // Snap along each gizmo axis.
            if snapping.translation != nil {
                delta = frame.axes.reduce(SIMD3<Float>.zero) { sum, axis in sum + axis * Self.snap(simd_dot(delta, axis), step: snapping.translation) }
            }
            target.worldPosition = drag.startWorldPosition + delta
        case .rotate:
            if drag.handle == .center {
                target.worldOrientation = simd_normalize(Self.trackballRotation(from: drag.startPoint, to: point, frame: frame) * drag.startWorldOrientation)
                break
            }
            let normal: SIMD3<Float>
            switch drag.handle {
            case .axis(let axis):
                normal = frame.axis(axis)
            case .view:
                normal = frame.cameraForward
            case .plane, .center:
                return
            }
            guard let start = drag.startHit, let current = hit(drag.handle, frame: frame, point: point, viewport: viewport) else {
                return
            }
            let a = start - frame.origin, b = current - frame.origin
            let angle = Self.snap(atan2(simd_dot(simd_cross(a, b), normal), simd_dot(a, b)), step: snapping.rotation)
            target.worldOrientation = simd_normalize(simd_quatf(angle: angle, axis: normal) * drag.startWorldOrientation)
        case .scale:
            var scale = drag.startScale
            switch drag.handle {
            case .axis(let axis):
                guard let start = drag.startHit, let current = hit(drag.handle, frame: frame, point: point, viewport: viewport) else {
                    return
                }
                let startDistance = simd_dot(start - frame.origin, frame.axis(axis))
                guard abs(startDistance) > 1e-6 else {
                    return
                }
                let factor = Self.snap(simd_dot(current - frame.origin, frame.axis(axis)) / startDistance, step: snapping.scale)
                scale[axis.rawValue] = drag.startScale[axis.rawValue] * factor
            case .center, .plane, .view:
                guard let center = viewport.project(frame.origin)?.xy, simd_distance(drag.startPoint, center) > 1 else {
                    return
                }
                let factor = Self.snap(simd_distance(point, center) / simd_distance(drag.startPoint, center), step: snapping.scale)
                scale = drag.startScale * factor
            }
            target.trs.scale = scale
        }
        onChange?(target)
    }

    // MARK: Two-finger gestures

    /// Pinches and twists that start within the gizmo's reach on screen (its handle length) scale and turn the
    /// target, whatever the mode.
    public func claimsTwoFingerGesture(at point: SIMD2<Float>, viewport: SceneViewport) -> Bool {
        guard target != nil, let frame = frame(viewport: viewport), let center = viewport.project(frame.origin)?.xy else {
            return false
        }
        let reach = worldSize.map { $0 / viewport.worldSizeOfPoint(at: frame.origin) } ?? size
        return simd_distance(point, center) <= reach
    }

    public func beginTwoFingerGesture(viewport: SceneViewport) {
        guard let target, let frame = frame(viewport: viewport) else {
            return
        }
        twoFingerStart = (target.trs.scale, target.worldOrientation, frame.cameraForward)
        onBegin?(target)
    }

    /// Scales uniformly by `scale` and turns about the view direction by `rotation` (clockwise on screen, as seen from
    /// the camera), each snapped like the handles.
    public func twoFingerGesture(scale: Float, rotation: Float, viewport _: SceneViewport) {
        guard let target, let start = twoFingerStart else {
            return
        }
        target.trs.scale = start.scale * Self.snap(max(scale, 0.001), step: snapping.scale)
        let angle = Self.snap(rotation, step: snapping.rotation)
        target.worldOrientation = simd_normalize(simd_quatf(angle: angle, axis: start.cameraForward) * start.orientation)
        onChange?(target)
    }

    public func endTwoFingerGesture() {
        if let target, twoFingerStart != nil {
            onEnd?(target)
        }
        twoFingerStart = nil
    }

    // Free rotation from a drag in view points (y down): dragging right turns the near side right, dragging down turns
    // it down. Not snapped.
    static func trackballRotation(from start: SIMD2<Float>, to end: SIMD2<Float>, frame: Frame) -> simd_quatf {
        let delta = end - start
        let axis = frame.cameraUp * delta.x + frame.cameraRight * delta.y
        guard simd_length(axis) > 1e-6 else {
            return simd_quatf(ix: 0, iy: 0, iz: 0, r: 1)
        }
        let radiansPerPoint: Float = 0.01
        return simd_quatf(angle: simd_length(delta) * radiansPerPoint, axis: simd_normalize(axis))
    }

    public func endDrag() {
        if let target, drag != nil {
            onEnd?(target)
        }
        drag = nil
        activeHandle = nil
    }

    // MARK: Drawing

    static let axisColors: [Color] = [.red, .green, .blue]

    // swiftlint:disable:next unneeded_throws_rethrows
    public func overlay(viewport: SceneViewport) throws -> AnyElement? {
        guard var frame = frame(viewport: viewport) else {
            return nil
        }
        // Drawn camera-relative, so the handles stay precise far from the world origin (#262). Hit testing and drags
        // keep the world-space frame.
        frame.origin = cameraRelative(frame.origin, to: viewport.cameraMatrix.columns.3.xyz)
        let highlighted = activeHandle ?? hoveredHandle
        var context = GraphicsContext3D()
        for (handle, points) in outlines(frame) {
            let isHighlighted = handle == highlighted
            let opacity = Double(opacity(of: handle, frame: frame))
            guard opacity > 0 else {
                continue
            }
            var path = Path3D()
            path.move(to: points[0])
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            switch handle {
            case .axis(let axis):
                let color = (isHighlighted ? Color.yellow : Self.axisColors[axis.rawValue]).opacity(opacity)
                let lineWidth: Float = isHighlighted ? 6 : 4
                if mode == .rotate {
                    // The half behind the center is dimmer, so the ring reads as a circle in depth.
                    for run in Self.ringRuns(points, frame: frame) where run.points.count > 1 {
                        var runPath = Path3D()
                        runPath.move(to: run.points[0])
                        for point in run.points.dropFirst() {
                            runPath.addLine(to: point)
                        }
                        context.stroke(runPath, with: run.isFront || isHighlighted ? color : color.opacity(0.3), lineWidth: run.isFront ? lineWidth : lineWidth * 0.75)
                    }
                } else {
                    context.stroke(path, with: color, lineWidth: lineWidth)
                    let tip = points[1]
                    context.fill(tipShape(tip: tip, direction: frame.axis(axis), frame: frame), with: color)
                }
            case .plane(let axis):
                path.closeSubpath()
                context.fill(path, with: (isHighlighted ? Color.yellow : Self.axisColors[axis.rawValue]).opacity((isHighlighted ? 0.7 : 0.4) * opacity))
            case .view:
                context.stroke(path, with: (isHighlighted ? Color.yellow : Color.white).opacity(isHighlighted ? 1 : 0.6), lineWidth: isHighlighted ? 5 : 3)
            case .center:
                break
            }
        }
        if mode == .rotate, highlighted == .center {
            // The trackball area inside the rings.
            var disc = Path3D()
            let points = Self.circle(center: frame.origin, u: frame.cameraRight, v: frame.cameraUp, radius: frame.length * 0.9)
            disc.move(to: points[0])
            for point in points.dropFirst() {
                disc.addLine(to: point)
            }
            disc.closeSubpath()
            context.fill(disc, with: Color.white.opacity(0.12))
        }
        if mode != .rotate {
            // A small square facing the camera.
            let right = simd_normalize(viewport.cameraMatrix.columns.0.xyz) * frame.length * 0.06
            let up = simd_normalize(viewport.cameraMatrix.columns.1.xyz) * frame.length * 0.06
            let o = frame.origin
            let square = Path3D { path in
                path.move(to: o - right - up)
                path.addLine(to: o + right - up)
                path.addLine(to: o + right + up)
                path.addLine(to: o - right + up)
                path.closeSubpath()
            }
            context.fill(square, with: highlighted == .center ? .yellow : .white)
        }
        // No depth test, like most editors' gizmos: handles always draw on top.
        return GraphicsContext3DRenderPipeline(context: context, viewProjection: viewport.projectionMatrix * viewport.rotationOnlyViewMatrix, viewport: viewport.drawableSize, depthCompareFunction: .always, writesDepth: false).eraseToAnyElement()
    }

    // An arrowhead for translate, a box for scale, in the plane facing the camera.
    private func tipShape(tip: SIMD3<Float>, direction: SIMD3<Float>, frame: Frame) -> Path3D {
        var side = simd_cross(direction, frame.cameraForward)
        side = simd_length(side) > 1e-4 ? simd_normalize(side) : simd_normalize(simd_cross(direction, [0, 1, 0.1]))
        let size = frame.length * 0.08
        return Path3D { path in
            if mode == .scale {
                path.move(to: tip - side * size - direction * size)
                path.addLine(to: tip + side * size - direction * size)
                path.addLine(to: tip + side * size + direction * size)
                path.addLine(to: tip - side * size + direction * size)
            } else {
                path.move(to: tip + direction * size * 2.5)
                path.addLine(to: tip + side * size)
                path.addLine(to: tip - side * size)
            }
            path.closeSubpath()
        }
    }
}
