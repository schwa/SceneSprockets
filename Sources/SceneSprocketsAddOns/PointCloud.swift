import Metal
import MetalSprockets
import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import SceneSprockets
import simd
import SwiftMesh

/// Colored points, such as scanned data, drawn with MetalSprocketsAddOns' compute point rasterizer.
///
/// ``makeNode(device:)`` makes a node with a ``PointCloudMaterial``, so the view needs a ``PointCloudRenderer``.
/// The rasterizer needs an Apple GPU family 8 device or later; on other devices the points are not drawn.
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
    /// The size of each point, in pixels or world units (see ``sizeUnits``).
    public var pointSize: Float
    /// Whether ``pointSize`` is in screen pixels or world units.
    public var sizeUnits: PointCloudSizeUnits
    /// The shape of each point.
    public var shape: PointCloudShape

    /// Creates a point cloud.
    public init(points: [Point], pointSize: Float = 4, sizeUnits: PointCloudSizeUnits = .pixels, shape: PointCloudShape = .disc) {
        self.points = points
        self.pointSize = pointSize
        self.sizeUnits = sizeUnits
        self.shape = shape
    }

    /// A node that draws the points, labeled "Point Cloud". It has no content when there are no points.
    ///
    /// - Parameter device: The device for the point buffer and the mesh that gives the node its bounds.
    /// - Throws: An error if the point buffer cannot be made.
    public func makeNode(device: MTLDevice) throws -> SceneGraph.Node {
        let node = SceneGraph.Node(label: "Point Cloud")
        guard !points.isEmpty else {
            return node
        }
        let packed = points.map { point in
            let color = SIMD4<UInt8>(simd_clamp(point.color, .zero, .one) * 255 + 0.5)
            return PointCloudPoint(position: point.position, color: color)
        }
        let buffer = try device.makeBuffer(bytes: packed, length: packed.count * MemoryLayout<PointCloudPoint>.stride, options: .storageModeShared)
            .orThrow(.resourceCreationFailure("Failed to create the point cloud buffer"))
        buffer.label = "Point Cloud Points"
        // The mesh is only for bounds, culling and selection; the renderer draws from `buffer`.
        let mesh = MetalMesh(
            device: device,
            attributes: [.positions(points.map(\.position))],
            submeshes: [MetalMesh.SubmeshIndices(label: "Points", indices: points.indices.map { UInt32($0) }, primitiveType: .point)],
            label: "Point Cloud"
        )
        let material = PointCloudMaterial(points: buffer, pointCount: points.count, pointSize: pointSize, sizeUnits: sizeUnits, shape: shape)
        node.content = .mesh(mesh, materials: [material], castsShadow: false, receivesShadow: false)
        return node
    }
}

/// The material of a point cloud node: its points and how to draw them. A ``PointCloudRenderer`` draws it.
public struct PointCloudMaterial: SceneSprockets.Material {
    /// `PointCloudPoint` values (MetalSprocketsAddOnsShaders) in the node's space, with linear colors.
    public var points: MTLBuffer
    /// The number of points in ``points``.
    public var pointCount: Int
    /// The size of each point, in pixels or world units (see ``sizeUnits``).
    public var pointSize: Float
    /// Whether ``pointSize`` is in screen pixels or world units.
    public var sizeUnits: PointCloudSizeUnits
    /// The shape of each point.
    public var shape: PointCloudShape

    /// Creates a point cloud material.
    public init(points: MTLBuffer, pointCount: Int, pointSize: Float = 4, sizeUnits: PointCloudSizeUnits = .pixels, shape: PointCloudShape = .disc) {
        self.points = points
        self.pointCount = pointCount
        self.pointSize = pointSize
        self.sizeUnits = sizeUnits
        self.shape = shape
    }

    public var isTransparent: Bool {
        false
    }

    public var appliesNodeOpacity: Bool {
        false
    }
}

/// The renderer that draws every node with a ``PointCloudMaterial``.
///
/// Each point cloud is rasterized in its own compute pass before the scene pass, then resolved into the scene pass,
/// depth-tested against the other meshes. Add one instance to the renderers of a `SceneView` or `SceneGraphElement`.
public struct PointCloudRenderer: SceneGraphMaterialRenderer, SceneGraphPrePassRenderer {
    // One framebuffer per point cloud node, kept across frames; the rasterizer cycles its own buffers per frame.
    private final class Framebuffers {
        var byNode: [ObjectIdentifier: PointCloudFramebuffer] = [:]

        func framebuffer(for node: SceneGraph.Node) -> PointCloudFramebuffer {
            if let existing = byNode[ObjectIdentifier(node)] {
                return existing
            }
            let framebuffer = PointCloudFramebuffer()
            byNode[ObjectIdentifier(node)] = framebuffer
            return framebuffer
        }
    }

    private let framebuffers = Framebuffers()

    /// Creates a point cloud renderer.
    public init() {
        // Framebuffers are made per node on first use.
    }

    public var materialType: any SceneSprockets.Material.Type {
        PointCloudMaterial.self
    }

    public func makePrePassElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext, viewSize: (width: Int, height: Int), otherOpaqueContent _: () throws -> AnyElement?) throws -> AnyElement? {
        let passes: [AnyElement] = try entries.compactMap { entry in
            guard let material = entry.material as? PointCloudMaterial, material.pointCount > 0, PointCloudFramebuffer.isSupported(on: material.points.device) else {
                return nil
            }
            return try PointCloudRasterizePass(
                points: material.points,
                count: material.pointCount,
                viewProjection: context.projectionMatrix * context.viewMatrix * entry.worldTransform,
                viewportSize: [viewSize.width, viewSize.height],
                reverseZ: true,
                framebuffer: framebuffers.framebuffer(for: entry.node),
                pointSize: material.pointSize,
                shape: material.shape,
                colorSpace: .linear,
                sizeUnits: material.sizeUnits
            )
            .eraseToAnyElement()
        }
        guard !passes.isEmpty else {
            return nil
        }
        return ForEach(Array(passes.enumerated()), id: \.offset) { _, pass in
            pass
        }
        .eraseToAnyElement()
    }

    // swiftlint:disable:next unneeded_throws_rethrows - the protocol requirement throws
    public func makeElement(entries: [SceneGraph.MeshEntry], context _: SceneGraphRenderContext) throws -> AnyElement {
        let resolves: [AnyElement] = entries.compactMap { entry in
            guard let material = entry.material as? PointCloudMaterial, material.pointCount > 0, PointCloudFramebuffer.isSupported(on: material.points.device) else {
                return nil
            }
            return PointCloudResolvePipeline(framebuffer: framebuffers.framebuffer(for: entry.node)).eraseToAnyElement()
        }
        return ForEach(Array(resolves.enumerated()), id: \.offset) { _, resolve in
            resolve
        }
        .eraseToAnyElement()
    }
}
