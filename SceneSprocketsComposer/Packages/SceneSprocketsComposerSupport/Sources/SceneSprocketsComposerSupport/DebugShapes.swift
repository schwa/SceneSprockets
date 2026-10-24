import GeometryLite3D
import MetalSprockets
import MetalSprocketsAddOns
import SceneSprockets
import simd
import SwiftUI

// Line drawings for lights and cameras, which have no geometry of their own, so they can be seen and clicked (#188).
// Sizes are in view points, so the shapes stay the same size on screen.
enum DebugShapes {
    static let size: Float = 48
    static let hitDistance: Float = 6

    struct Shape {
        var node: SceneGraph.Node
        // World-space polylines.
        var lines: [[SIMD3<Float>]]
    }

    @MainActor
    static func shapes(sceneGraph: SceneGraph, viewport: SceneViewport) -> [Shape] {
        let aspect = viewport.viewSize.y > 0 ? viewport.viewSize.x / viewport.viewSize.y : 1
        var result: [Shape] = []
        for entry in sceneGraph.lightNodes() {
            let length = size * viewport.worldSizeOfPoint(at: entry.worldTransform.columns.3.xyz)
            result.append(Shape(node: entry.node, lines: lightLines(entry.light, length: length).map { transform($0, by: entry.worldTransform) }))
        }
        for entry in sceneGraph.cameraNodes() {
            let length = size * viewport.worldSizeOfPoint(at: entry.worldTransform.columns.3.xyz)
            result.append(Shape(node: entry.node, lines: cameraLines(entry.camera, length: length, aspect: aspect).map { transform($0, by: entry.worldTransform) }))
        }
        return result
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

    @MainActor
    static func element(sceneGraph: SceneGraph, selected: Set<SceneGraph.Node.ID>, viewport: SceneViewport) throws -> AnyElement? {
        let shapes = shapes(sceneGraph: sceneGraph, viewport: viewport)
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
            let isSelected = selected.contains(shape.node.id)
            context.stroke(path, with: isSelected ? Color.yellow : Color.white.opacity(0.8), lineWidth: isSelected ? 3 : 2)
        }
        return GraphicsContext3DRenderPipeline(context: context, viewProjection: viewport.projectionMatrix * viewport.viewMatrix, viewport: viewport.drawableSize, depthCompareFunction: .always, writesDepth: false).eraseToAnyElement()
    }

    // The node whose shape passes within hitDistance points of `point`, nearest first.
    @MainActor
    static func hitTest(_ point: SIMD2<Float>, sceneGraph: SceneGraph, viewport: SceneViewport) -> SceneGraph.Node? {
        var best: (node: SceneGraph.Node, distance: Float)?
        for shape in shapes(sceneGraph: sceneGraph, viewport: viewport) {
            for line in shape.lines {
                let projected = line.map { viewport.project($0) }
                for (start, end) in zip(projected, projected.dropFirst()) {
                    guard let start, let end else {
                        continue
                    }
                    let distance = distanceToSegment(point, start.xy, end.xy)
                    if distance <= hitDistance, distance < (best?.distance ?? .infinity) {
                        best = (shape.node, distance)
                    }
                }
            }
        }
        return best?.node
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
        line.map { (matrix * SIMD4<Float>($0, 1)).xyz }
    }
}
