import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd
import SwiftUI

// Move, rotate and scale handles for one node, drawn at a constant size on screen with MetalSprocketsAddOns'
// GraphicsContext3D, like three.js TransformControls (#154). Give it to SceneView(manipulator:).
@MainActor
public final class TransformGizmo: SceneViewManipulator {
    public enum Mode: String, CaseIterable, Sendable {
        case translate, rotate, scale
    }

    public enum Space: String, CaseIterable, Sendable {
        // Handles follow the world axes.
        case world
        // Handles follow the node's rotation.
        case local
    }

    public enum Axis: Int, CaseIterable, Sendable {
        case x, y, z

        var vector: SIMD3<Float> {
            switch self {
            case .x: [1, 0, 0]
            case .y: [0, 1, 0]
            case .z: [0, 0, 1]
            }
        }
    }

    public enum Handle: Equatable, Sendable {
        case axis(Axis)
        // The plane perpendicular to the axis.
        case plane(Axis)
        // Translate: in the view plane. Scale: uniform.
        case center
    }

    public struct Snapping: Sendable {
        // World units; nil is no snapping.
        public var translation: Float?
        // Radians.
        public var rotation: Float?
        // Scale factor steps.
        public var scale: Float?

        public init(translation: Float? = nil, rotation: Float? = nil, scale: Float? = nil) {
            self.translation = translation
            self.rotation = rotation
            self.scale = scale
        }
    }

    public var target: SceneGraph.Node?
    public var mode: Mode = .translate
    public var space: Space = .world
    public var snapping = Snapping()
    // Length of the axis handles in view points.
    public var size: Float = 110
    public private(set) var hoveredHandle: Handle?
    public private(set) var activeHandle: Handle?
    // Called when a drag starts and ends, and with the node after each change, for undo and inspectors.
    public var onBegin: ((SceneGraph.Node) -> Void)?
    public var onChange: ((SceneGraph.Node) -> Void)?
    public var onEnd: ((SceneGraph.Node) -> Void)?

    private var drag: DragState?

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
        return Frame(origin: origin, axes: axes, length: size * viewport.worldSizeOfPoint(at: origin), cameraForward: forward)
    }

    // World polylines for each handle, for drawing and hit testing. Planes are closed quads.
    func outlines(_ frame: Frame) -> [(handle: Handle, points: [SIMD3<Float>])] {
        let o = frame.origin, length = frame.length
        switch mode {
        case .translate, .scale:
            var result: [(Handle, [SIMD3<Float>])] = Axis.allCases.map { axis in (.axis(axis), [o, o + frame.axis(axis) * length]) }
            if mode == .translate {
                for axis in Axis.allCases {
                    let u = frame.axis(Axis(rawValue: (axis.rawValue + 1) % 3)!) * length * 0.25
                    let v = frame.axis(Axis(rawValue: (axis.rawValue + 2) % 3)!) * length * 0.25
                    let corner = o + (u + v) * 0.6
                    result.append((.plane(axis), [corner, corner + u * 0.8, corner + u * 0.8 + v * 0.8, corner + v * 0.8]))
                }
            }
            return result
        case .rotate:
            return Axis.allCases.map { axis in
                let u = frame.axis(Axis(rawValue: (axis.rawValue + 1) % 3)!)
                let v = frame.axis(Axis(rawValue: (axis.rawValue + 2) % 3)!)
                let points = (0 ... 64).map { index -> SIMD3<Float> in
                    let angle = Float(index) / 64 * 2 * .pi
                    return o + (u * cos(angle) + v * sin(angle)) * length * 0.9
                }
                return (.axis(axis), points)
            }
        }
    }

    // 1 for a handle seen well; fades to 0 for an axis pointing at the camera (it collapses to a dot) and a plane seen
    // edge-on. Rings stay visible: their back halves are dimmed instead (see `ringRuns`).
    func opacity(of handle: Handle, frame: Frame) -> Float {
        let facing: Float
        switch (mode, handle) {
        case (.rotate, _), (_, .center):
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
        return best?.handle
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
    static func closestParameter(origin: SIMD3<Float>, direction: SIMD3<Float>, ray: Ray3D) -> Float? {
        let w = origin - ray.origin
        let b = simd_dot(direction, ray.direction)
        let denominator = 1 - b * b
        guard abs(denominator) > 1e-5 else {
            return nil
        }
        return (b * simd_dot(ray.direction, w) - simd_dot(direction, w)) / denominator
    }

    static func intersect(_ ray: Ray3D, planeOrigin: SIMD3<Float>, normal: SIMD3<Float>) -> SIMD3<Float>? {
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
        case (_, .axis(let axis)):
            return Self.closestParameter(origin: frame.origin, direction: frame.axis(axis), ray: ray).map { frame.origin + frame.axis(axis) * $0 }
        case (_, .plane(let axis)):
            return Self.intersect(ray, planeOrigin: frame.origin, normal: frame.axis(axis))
        case (_, .center):
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
            guard case let .axis(axis) = drag.handle, let start = drag.startHit, let current = hit(drag.handle, frame: frame, point: point, viewport: viewport) else {
                return
            }
            let normal = frame.axis(axis)
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
            case .center, .plane:
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

    public func endDrag() {
        if let target, drag != nil {
            onEnd?(target)
        }
        drag = nil
        activeHandle = nil
    }

    // MARK: Drawing

    static let axisColors: [Color] = [.red, .green, .blue]

    public func overlay(viewport: SceneViewport) throws -> AnyElement? {
        guard let frame = frame(viewport: viewport) else {
            return nil
        }
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
            case .center:
                break
            }
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
        return GraphicsContext3DRenderPipeline(context: context, viewProjection: viewport.projectionMatrix * viewport.viewMatrix, viewport: viewport.drawableSize, depthCompareFunction: .always, writesDepth: false).eraseToAnyElement()
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
