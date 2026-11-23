import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd
import SwiftUI

/// Editor aids drawn over a scene: a ground grid, world axes, line icons for lights and cameras (which have no
/// geometry of their own), and bounding boxes (#406). Draw them with ``element(sceneGraph:viewport:options:selected:gridTransform:)``
/// from `SceneView.sceneDecorations`.
public enum EditorGizmos {
    /// Which aids to draw.
    public struct Options: OptionSet, Sendable, Hashable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        /// Lines on the XZ plane every ``EditorGizmos/gridSpacing``, out to ``EditorGizmos/gridExtent``.
        public static let grid = Self(rawValue: 1 << 0)
        /// Red X, green Y and blue Z axes from the origin.
        public static let axes = Self(rawValue: 1 << 1)
        /// Line icons for light and camera nodes, the same size on screen at any distance.
        public static let lightsAndCameras = Self(rawValue: 1 << 2)
        /// The world bounding boxes of the selected nodes and their subtrees.
        public static let bounds = Self(rawValue: 1 << 3)
        /// The curves of nodes with a `SceneGraph.Node.path` (#607). Clicking one picks its node.
        public static let paths = Self(rawValue: 1 << 4)
        public static let all: Self = [.grid, .axes, .lightsAndCameras, .bounds, .paths]
    }

    /// World-space polylines in one color, for one node or for the whole scene.
    public struct Shape {
        /// The light, camera or path node the shape stands for; nil for the grid and axes.
        public var node: SceneGraph.Node?
        public var lines: [[SIMD3<Float>]]
        /// Linear RGBA.
        public var color: SIMD4<Float>
        /// Drawn over everything; otherwise hidden behind scene geometry.
        public var isOverlay: Bool
    }

    /// The light and camera icons' size, in view points.
    public static let iconSize: Float = 48
    /// How close a click must be to an icon's lines to pick it, in view points.
    public static let hitDistance: Float = 6
    public static let gridExtent: Float = 10
    public static let gridSpacing: Float = 1

    private static let gridColor = SIMD4<Float>(0.5, 0.5, 0.5, 0.6)
    private static let iconColor = SIMD4<Float>(1, 1, 1, 0.8)
    private static let selectedColor = SIMD4<Float>(1, 0.85, 0, 1)
    private static let pathColor = SIMD4<Float>(0.4, 0.8, 1, 0.9)

    /// The aids' geometry.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene.
    ///   - viewport: The view, which sizes the icons.
    ///   - options: Which aids to include.
    ///   - selected: Nodes whose bounds `.bounds` draws, and whose icons are highlighted.
    ///   - gridTransform: Where the grid and axes are drawn: identity puts them at the world origin on the XZ plane.
    @MainActor
    public static func shapes(sceneGraph: SceneGraph, viewport: Viewport, options: Options = .all, selected: Set<SceneGraph.Node.ID> = [], gridTransform: simd_float4x4 = matrix_identity_float4x4) -> [Shape] {
        var result: [Shape] = []
        if options.contains(.grid) {
            var lines: [[SIMD3<Float>]] = []
            let count = Int((gridExtent / gridSpacing).rounded())
            for index in -count...count where index != 0 || !options.contains(.axes) {
                let offset = Float(index) * gridSpacing
                lines.append([[offset, 0, -gridExtent], [offset, 0, gridExtent]])
                lines.append([[-gridExtent, 0, offset], [gridExtent, 0, offset]])
            }
            result.append(Shape(node: nil, lines: lines.map { transform($0, by: gridTransform) }, color: gridColor, isOverlay: false))
        }
        if options.contains(.axes) {
            let length = gridExtent
            result.append(Shape(node: nil, lines: [transform([.zero, [length, 0, 0]], by: gridTransform)], color: [1, 0.2, 0.2, 1], isOverlay: false))
            result.append(Shape(node: nil, lines: [transform([.zero, [0, length, 0]], by: gridTransform)], color: [0.2, 1, 0.2, 1], isOverlay: false))
            result.append(Shape(node: nil, lines: [transform([.zero, [0, 0, length]], by: gridTransform)], color: [0.3, 0.5, 1, 1], isOverlay: false))
        }
        if options.contains(.lightsAndCameras) {
            let aspect = viewport.viewSize.y > 0 ? viewport.viewSize.x / viewport.viewSize.y : 1
            for entry in sceneGraph.lightNodes() {
                let length = iconSize * viewport.worldSizeOfPoint(at: entry.worldTransform.columns.3.xyz)
                result.append(Shape(node: entry.node, lines: lightLines(entry.light, length: length).map { transform($0, by: entry.worldTransform) }, color: selected.contains(entry.node.id) ? selectedColor : iconColor, isOverlay: true))
            }
            for entry in sceneGraph.cameraNodes() {
                let length = iconSize * viewport.worldSizeOfPoint(at: entry.worldTransform.columns.3.xyz)
                result.append(Shape(node: entry.node, lines: cameraLines(entry.camera, length: length, aspect: aspect).map { transform($0, by: entry.worldTransform) }, color: selected.contains(entry.node.id) ? selectedColor : iconColor, isOverlay: true))
            }
        }
        if options.contains(.paths) {
            sceneGraph.visit { node, worldTransform in
                guard let path = node.path, path.length > 0 else {
                    return
                }
                let line = pathLine(path).map { (worldTransform * SIMD4($0, 1)).xyz }
                result.append(Shape(node: node, lines: [line], color: selected.contains(node.id) ? selectedColor : pathColor, isOverlay: true))
            }
        }
        if options.contains(.bounds), !selected.isEmpty {
            sceneGraph.visit { node, worldTransform in
                guard selected.contains(node.id), let bounds = node.subtreeBounds else {
                    return
                }
                // subtreeBounds is in the parent's space.
                let parentTransform = worldTransform * node.composedTransform.inverse
                result.append(Shape(node: node, lines: boxLines(bounds).map { transform($0, by: parentTransform) }, color: selectedColor, isOverlay: false))
            }
        }
        return result
    }

    /// An element that draws the aids, for `SceneView.sceneDecorations`. Nil when there is nothing to draw.
    @MainActor
    public static func element(sceneGraph: SceneGraph, viewport: Viewport, options: Options = .all, selected: Set<SceneGraph.Node.ID> = [], gridTransform: simd_float4x4 = matrix_identity_float4x4) throws -> AnyElement? {
        let shapes = shapes(sceneGraph: sceneGraph, viewport: viewport, options: options, selected: selected, gridTransform: gridTransform)
        guard !shapes.isEmpty else {
            return nil
        }
        func context(_ shapes: [Shape]) -> GraphicsContext3D? {
            guard !shapes.isEmpty else {
                return nil
            }
            var context = GraphicsContext3D()
            for shape in shapes {
                let path = Path3D { path in
                    for line in shape.lines where line.count > 1 {
                        path.move(to: line[0])
                        for point in line.dropFirst() {
                            path.addLine(to: point)
                        }
                    }
                }
                let color = Color(.sRGBLinear, red: Double(shape.color.x), green: Double(shape.color.y), blue: Double(shape.color.z), opacity: Double(shape.color.w))
                context.stroke(path, with: color, lineWidth: shape.node != nil && shape.color == selectedColor ? 3 : (shape.isOverlay ? 2 : 1))
            }
            return context
        }
        let viewProjection = viewport.projectionMatrix * viewport.viewMatrix
        // Depth-tested against the scene, which draws with reversed depth (nearer is greater); Viewport's projection is
        // standard depth, so it is reversed to match.
        let behind = context(shapes.filter { !$0.isOverlay }).map {
            GraphicsContext3DRenderPipeline(context: $0, viewProjection: .reverseZ * viewProjection, viewport: viewport.drawableSize, depthCompareFunction: .greaterEqual, writesDepth: false).eraseToAnyElement()
        }
        let over = context(shapes.filter(\.isOverlay)).map {
            GraphicsContext3DRenderPipeline(context: $0, viewProjection: viewProjection, viewport: viewport.drawableSize, depthCompareFunction: .always, writesDepth: false).eraseToAnyElement()
        }
        return try MetalSprockets.Group {
            if let behind {
                behind
            }
            if let over {
                over
            }
        }
        .eraseToAnyElement()
    }

    /// The light, camera or path node whose lines pass within ``hitDistance`` points of `point` (in view points),
    /// nearest first.
    @MainActor
    public static func hitTest(_ point: SIMD2<Float>, sceneGraph: SceneGraph, viewport: Viewport) -> SceneGraph.Node? {
        var best: (node: SceneGraph.Node, distance: Float)?
        for shape in shapes(sceneGraph: sceneGraph, viewport: viewport, options: [.lightsAndCameras, .paths]) {
            guard let node = shape.node else {
                continue
            }
            for line in shape.lines {
                let projected = line.map { viewport.project($0) }
                for (start, end) in zip(projected, projected.dropFirst()) {
                    guard let start, let end else {
                        continue
                    }
                    let distance = distanceToSegment(point, SIMD2(start.x, start.y), SIMD2(end.x, end.y))
                    if distance <= hitDistance, distance < (best?.distance ?? .infinity) {
                        best = (node, distance)
                    }
                }
            }
        }
        return best?.node
    }

    // Local space: lights and cameras face -Z.
    static func lightLines(_ light: Light, length: Float) -> [[SIMD3<Float>]] {
        switch light.type {
        case .directional:
            let head = length * 0.25
            var lines = [circle(radius: length * 0.2, z: 0)]
            for offset: SIMD2<Float> in [[0, 0], [0.15, 0], [-0.15, 0], [0, 0.15], [0, -0.15]] {
                let start = SIMD3<Float>(offset.x * length, offset.y * length, 0)
                lines.append([start, start + [0, 0, -length]])
            }
            lines.append([[head * 0.5, 0, -length + head], [0, 0, -length], [-head * 0.5, 0, -length + head]])
            return lines
        case .area:
            // The rectangle, and a line along the direction it lights.
            let (x, y) = (light.areaSize.x / 2, light.areaSize.y / 2)
            return [[[-x, -y, 0], [x, -y, 0], [x, y, 0], [-x, y, 0], [-x, -y, 0]], [[0, 0, 0], [0, 0, -length]]]
        case .ambient:
            // No position or direction: a small star of lines marks the node.
            let size = length * 0.15
            return [[[-size, 0, 0], [size, 0, 0]], [[0, -size, 0], [0, size, 0]], [[0, 0, -size], [0, 0, size]]]
        case .point:
            let radius = length * 0.25
            var lines = [circle(radius: radius, z: 0), circle(radius: radius, z: 0).map { [$0.x, $0.z, $0.y] }, circle(radius: radius, z: 0).map { [$0.z, $0.y, $0.x] }]
            if light.range.isFinite {
                lines.append(circle(radius: light.range, z: 0).map { [$0.x, $0.z, $0.y] })
            }
            return lines
        case .spot:
            let depth = light.range.isFinite ? min(light.range, length * 2) : length * 2
            let outer = circle(radius: depth * tan(light.outerConeAngle), z: -depth)
            let inner = circle(radius: depth * tan(light.innerConeAngle), z: -depth)
            var lines = [outer, inner]
            for index in stride(from: 0, to: outer.count - 1, by: outer.count / 4) {
                lines.append([.zero, outer[index]])
            }
            return lines
        }
    }

    static func cameraLines(_ camera: Camera, length: Float, aspect: Float) -> [[SIMD3<Float>]] {
        let halfHeight: Float
        if let perspective = camera.projection as? PerspectiveProjection {
            halfHeight = length * tan(Float(perspective.verticalAngleOfView.radians) / 2)
        } else {
            halfHeight = length * 0.5
        }
        let halfWidth = halfHeight * aspect
        let corners: [SIMD3<Float>] = [[-halfWidth, -halfHeight, -length], [halfWidth, -halfHeight, -length], [halfWidth, halfHeight, -length], [-halfWidth, halfHeight, -length]]
        var lines = [corners + [corners[0]]]
        for corner in corners {
            lines.append([.zero, corner])
        }
        // A triangle above the far rectangle marks up.
        lines.append([[-halfWidth * 0.4, halfHeight * 1.1, -length], [0, halfHeight * 1.5, -length], [halfWidth * 0.4, halfHeight * 1.1, -length], [-halfWidth * 0.4, halfHeight * 1.1, -length]])
        return lines
    }

    // The 12 edges of a box.
    // The curve as a polyline, 16 samples per point, closed curves back to the start.
    static func pathLine(_ path: SceneGraph.Spline) -> [SIMD3<Float>] {
        let samples = max(path.points.count * 16, 2)
        return (0...samples).map { path.position(at: Float($0) / Float(samples)) }
    }

    static func boxLines(_ box: BoundingBox3D) -> [[SIMD3<Float>]] {
        let (low, high) = (box.min, box.max)
        let bottom: [SIMD3<Float>] = [[low.x, low.y, low.z], [high.x, low.y, low.z], [high.x, low.y, high.z], [low.x, low.y, high.z]]
        let top = bottom.map { SIMD3($0.x, high.y, $0.z) }
        return [bottom + [bottom[0]], top + [top[0]]] + zip(bottom, top).map { [$0, $1] }
    }

    static func distanceToSegment(_ point: SIMD2<Float>, _ start: SIMD2<Float>, _ end: SIMD2<Float>) -> Float {
        let segment = end - start
        let lengthSquared = simd_length_squared(segment)
        let fraction = lengthSquared > 0 ? simd_clamp(simd_dot(point - start, segment) / lengthSquared, 0, 1) : 0
        return simd_distance(point, start + segment * fraction)
    }

    private static func circle(radius: Float, z: Float, segments: Int = 32) -> [SIMD3<Float>] {
        (0...segments).map { index in
            let angle = Float(index) / Float(segments) * 2 * .pi
            return [cos(angle) * radius, sin(angle) * radius, z]
        }
    }

    private static func transform(_ line: [SIMD3<Float>], by matrix: simd_float4x4) -> [SIMD3<Float>] {
        line.map { point in
            let transformed = matrix * SIMD4<Float>(point, 1)
            return SIMD3(transformed.x, transformed.y, transformed.z)
        }
    }
}
