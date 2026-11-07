import simd

extension SceneGraph {
    /// Distance fog, like SceneKit's fogStartDistance, fogEndDistance, fogColor and fogDensityExponent. Applied to
    /// geometry (not the background) by SceneGraphElement after every renderer has drawn.
    public struct Fog: Sendable, Equatable, Codable {
        /// Linear RGB; alpha scales the maximum fog amount.
        public var color: SIMD4<Float>
        /// The camera distance where the fog starts.
        public var startDistance: Float
        /// The camera distance where the fog reaches full strength.
        public var endDistance: Float
        /// 1 is linear between start and end; higher values thin the fog near the start.
        public var densityExponent: Float

        /// Creates fog.
        ///
        /// - Parameters:
        ///   - color: The color in linear RGB. Alpha scales the maximum amount of fog.
        ///   - startDistance: The camera distance where the fog starts.
        ///   - endDistance: The camera distance where the fog reaches full strength.
        ///   - densityExponent: The shape of the change. 1 is linear, and higher values make the fog thinner near the
        ///     start.
        public init(color: SIMD4<Float> = [0.7, 0.75, 0.8, 1], startDistance: Float = 5, endDistance: Float = 30, densityExponent: Float = 1) {
            self.color = color
            self.startDistance = startDistance
            self.endDistance = endDistance
            self.densityExponent = densityExponent
        }

        /// 0 (no fog) to color.w (full fog) at `distance` from the camera.
        public func amount(atDistance distance: Float) -> Float {
            let span = max(endDistance - startDistance, .ulpOfOne)
            let linear = min(max((distance - startDistance) / span, 0), 1)
            return pow(linear, max(densityExponent, .ulpOfOne)) * color.w
        }
    }
}
