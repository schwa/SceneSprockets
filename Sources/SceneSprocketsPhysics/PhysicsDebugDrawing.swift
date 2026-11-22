import JoltPhysics
import Metal
import SceneSprockets
import simd
import SwiftMesh

/// Physics debug geometry in world space: collision shapes, bounds, velocities and constraints, as Jolt draws them
/// (#431).
public struct PhysicsDebugGeometry: Sendable {
    public struct Line: Sendable, Equatable {
        public var from: SIMD3<Float>
        public var to: SIMD3<Float>
        /// Linear RGBA, 0...1.
        public var color: SIMD4<Float>
    }

    public struct Triangle: Sendable, Equatable {
        public var vertices: (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)
        public var color: SIMD4<Float>

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.vertices == rhs.vertices && lhs.color == rhs.color
        }
    }

    public var lines: [Line] = []
    public var triangles: [Triangle] = []

    public var isEmpty: Bool { lines.isEmpty && triangles.isEmpty }
}

private final class DebugGeometryCollector: DebugRenderer {
    var geometry = PhysicsDebugGeometry()

    func drawLine(from: SIMD3<Float>, to: SIMD3<Float>, color: DebugColor) {
        geometry.lines.append(.init(from: from, to: to, color: color.simd))
    }

    func drawTriangle(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, color: DebugColor) {
        geometry.triangles.append(.init(vertices: (a, b, c), color: color.simd))
    }
}

public extension SceneGraphPhysicsWorld {
    /// The world's debug geometry: shapes (solid, or lines with `settings.wireframe`), and bounds, centers of mass,
    /// velocities and constraints as `settings` asks.
    func debugGeometry(settings: DebugDrawSettings = DebugDrawSettings()) -> PhysicsDebugGeometry {
        let collector = DebugGeometryCollector()
        world.debugDraw(to: collector, settings: settings)
        return collector.geometry
    }

    /// Sets `node`'s content to the world's debug geometry drawn with `material`, or empties it when there is nothing
    /// to draw. Call it after each step. The geometry is in world space, so keep `node` at the scene's origin with no
    /// transform. A material that shows vertex colors, such as `ShaderMaterial.vertexColors()`, shows Jolt's colors.
    func updateDebugNode(_ node: SceneGraph.Node, material: any SceneMaterial, settings: DebugDrawSettings = DebugDrawSettings(), device: any MTLDevice) {
        let geometry = debugGeometry(settings: settings)
        guard let mesh = Self.debugMesh(geometry, device: device) else {
            node.content = .empty
            return
        }
        node.content = .mesh(mesh, materials: [material], castsShadow: false, receivesShadow: false)
    }

    // Positions and colors, with zero normals and texture coordinates so materials that read them still work. One
    // line submesh and one triangle submesh, each only when it has something.
    private static func debugMesh(_ geometry: PhysicsDebugGeometry, device: any MTLDevice) -> MetalMesh? {
        guard !geometry.isEmpty else {
            return nil
        }
        var positions: [SIMD3<Float>] = []
        var colors: [SIMD4<Float>] = []
        var submeshes: [MetalMesh.SubmeshIndices] = []
        for line in geometry.lines {
            positions += [line.from, line.to]
            colors += [line.color, line.color]
        }
        if !geometry.lines.isEmpty {
            submeshes.append(.init(label: "Lines", indices: (0..<UInt32(positions.count)).map(\.self), primitiveType: .line))
        }
        let triangleStart = UInt32(positions.count)
        for triangle in geometry.triangles {
            positions += [triangle.vertices.0, triangle.vertices.1, triangle.vertices.2]
            colors += [triangle.color, triangle.color, triangle.color]
        }
        if !geometry.triangles.isEmpty {
            submeshes.append(.init(label: "Triangles", indices: (triangleStart..<UInt32(positions.count)).map(\.self), primitiveType: .triangle))
        }
        let zeros = [SIMD3<Float>](repeating: .zero, count: positions.count)
        let attributes: [MetalMesh.VertexAttributeData] = [
            .positions(positions),
            .normals(zeros),
            .textureCoordinates([SIMD2<Float>](repeating: .zero, count: positions.count)),
            .colors(colors)
        ]
        return MetalMesh(device: device, attributes: attributes, submeshes: submeshes, label: "Physics Debug")
    }
}
