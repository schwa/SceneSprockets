import GeometryLite3D

/// A camera's projection and category mask, like SceneKit's `SCNCamera`.
///
/// The camera's node places it. A camera looks down its node's -Z axis.
public struct Camera: Sendable {
    /// The projection, for example a GeometryLite3D `PerspectiveProjection` or `OrthographicProjection`.
    public var projection: any ProjectionProtocol
    /// Draws only nodes whose categoryBitMask shares a bit with this, like SCNCamera.categoryBitMask.
    public var categoryBitMask: UInt

    /// Creates a camera.
    ///
    /// - Parameters:
    ///   - projection: The projection.
    ///   - categoryBitMask: The node categories that the camera draws.
    public init(projection: any ProjectionProtocol, categoryBitMask: UInt = .max) {
        self.projection = projection
        self.categoryBitMask = categoryBitMask
    }

    /// A perspective camera.
    ///
    /// - Parameters:
    ///   - fieldOfView: The vertical angle of view.
    ///   - zClip: The near and far clipping distances.
    ///   - categoryBitMask: The node categories that the camera draws.
    public static func perspective(fieldOfView: AngleF = .degrees(60), zClip: ClosedRange<Float> = 0.01 ... 1_000, categoryBitMask: UInt = .max) -> Self {
        Self(projection: PerspectiveProjection(verticalAngleOfView: fieldOfView, depthMode: .standard(zClip: zClip)), categoryBitMask: categoryBitMask)
    }

    /// An orthographic camera.
    ///
    /// - Parameters:
    ///   - halfHeight: Half the height of the view volume, in world units.
    ///   - zClip: The near and far clipping distances.
    ///   - categoryBitMask: The node categories that the camera draws.
    public static func orthographic(halfHeight: Float = 1, zClip: ClosedRange<Float> = 0.01 ... 1_000, categoryBitMask: UInt = .max) -> Self {
        Self(projection: OrthographicProjection(halfHeight: halfHeight, depthMode: .standard(zClip: zClip)), categoryBitMask: categoryBitMask)
    }

    /// A perspective camera with a 60° field of view. `SceneView` uses it when the scene has no camera node.
    public static let `default` = Self.perspective()
}
