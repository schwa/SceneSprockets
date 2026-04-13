import simd

extension SceneGraph {
    // Distance fog, like SceneKit's fogStartDistance, fogEndDistance, fogColor and fogDensityExponent. Applied to
    // geometry (not the background) by SceneGraphElement after every renderer has drawn.
    public struct Fog: Sendable, Equatable {
        // Linear RGB; alpha scales the maximum fog amount.
        public var color: SIMD4<Float>
        // Camera distance where fog starts and where it reaches full strength.
        public var startDistance: Float
        public var endDistance: Float
        // 1 is linear between start and end; higher values thin the fog near the start.
        public var densityExponent: Float

        public init(color: SIMD4<Float> = [0.7, 0.75, 0.8, 1], startDistance: Float = 5, endDistance: Float = 30, densityExponent: Float = 1) {
            self.color = color
            self.startDistance = startDistance
            self.endDistance = endDistance
            self.densityExponent = densityExponent
        }

        // 0 (no fog) to color.w (full fog) at `distance` from the camera.
        public func amount(atDistance distance: Float) -> Float {
            let span = max(endDistance - startDistance, .ulpOfOne)
            let linear = min(max((distance - startDistance) / span, 0), 1)
            return pow(linear, max(densityExponent, .ulpOfOne)) * color.w
        }
    }
}
