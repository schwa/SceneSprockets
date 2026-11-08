import Metal
import MetalSprockets
import SceneSprockets
import SceneSprocketsShaderMaterial
import SceneSprocketsShaders
import simd
import SwiftMesh

/// Colored points of a fixed screen size, such as scanned data or particles that do not move.
///
/// ``makeNode(device:)`` makes a node with a point mesh and a `ShaderMaterial`, so the view needs a
/// `ShaderMaterialRenderer`. Points do not cast shadows and are not hit by triangle hit tests.
public struct PointCloud {
    /// One point.
    public struct Point: Sendable, Equatable {
        public var position: SIMD3<Float>
        /// The color in linear RGB, with alpha in `w`.
        public var color: SIMD4<Float>

        /// Creates a point.
        public init(position: SIMD3<Float>, color: SIMD4<Float> = [1, 1, 1, 1]) {
            self.position = position
            self.color = color
        }
    }

    /// The points.
    public var points: [Point]
    /// The diameter of each point, in points on screen.
    public var pointSize: Float

    /// Creates a point cloud.
    ///
    /// - Parameters:
    ///   - points: The points.
    ///   - pointSize: The diameter of each point, in points on screen.
    public init(points: [Point], pointSize: Float = 4) {
        self.points = points
        self.pointSize = pointSize
    }

    /// The material that draws the points. It blends when any point's alpha is below 1.
    ///
    /// - Throws: An error if the shader library cannot load.
    public func makeMaterial() throws -> ShaderMaterial {
        let library = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("PointCloud")
        let isTransparent = points.contains { $0.color.w < 1 }
        return ShaderMaterial(vertexShader: try library.vertex_points, fragmentShader: try library.fragment_points, parameters: ["pointSize": .float(pointSize)], isTransparent: isTransparent)
    }

    /// A node that draws the points, labeled "Point Cloud".
    ///
    /// - Parameter device: The device for the mesh.
    /// - Returns: The node. It has no content when there are no points.
    /// - Throws: An error if the shader library cannot load.
    public func makeNode(device: MTLDevice) throws -> SceneGraph.Node {
        let node = SceneGraph.Node(label: "Point Cloud")
        guard !points.isEmpty else {
            return node
        }
        let mesh = MetalMesh(
            device: device,
            attributes: [.positions(points.map(\.position)), .colors(points.map(\.color))],
            submeshes: [MetalMesh.SubmeshIndices(label: "Points", indices: points.indices.map { UInt32($0) }, primitiveType: .point)],
            label: "Point Cloud"
        )
        node.content = .mesh(mesh, materials: [try makeMaterial()], castsShadow: false)
        return node
    }
}
