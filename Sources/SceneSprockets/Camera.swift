import GeometryLite3D

public struct Camera: Sendable {
    public var projection: any ProjectionProtocol
    /// Draws only nodes whose categoryBitMask shares a bit with this, like SCNCamera.categoryBitMask.
    public var categoryBitMask: UInt

    public init(projection: any ProjectionProtocol, categoryBitMask: UInt = .max) {
        self.projection = projection
        self.categoryBitMask = categoryBitMask
    }
}
