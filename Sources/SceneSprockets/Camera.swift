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
}
