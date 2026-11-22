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
        /// Light scattered by the fog, for visible light beams and shadow shafts (#540). Nil: distance fog only.
        public var scattering: Scattering?

        /// Volumetric fog: a uniform medium that dims what is behind it and scatters each light toward the camera,
        /// where the light's shadow allows. Marched from the camera to the surface, or to `maximumDistance` over the
        /// background. Applied before the distance fog, which still blends to ``Fog/color``; set its alpha to 0 for
        /// volumetric fog alone.
        public struct Scattering: Sendable, Equatable, Codable {
            /// Extinction per unit of distance: after `1 / density` units, about 37% of the light is left.
            public var density: Float
            /// Scales the scattered light.
            public var intensity: Float
            /// Henyey-Greenstein anisotropy, -1...1: positive values scatter forward, so beams glow when you look
            /// toward the light; 0 scatters equally in all directions.
            public var anisotropy: Float
            /// Samples along each pixel's ray. More removes banding and costs time.
            public var stepCount: Int
            /// How far the march goes over the background.
            public var maximumDistance: Float

            public init(density: Float = 0.05, intensity: Float = 1, anisotropy: Float = 0.3, stepCount: Int = 32, maximumDistance: Float = 50) {
                self.density = density
                self.intensity = intensity
                self.anisotropy = anisotropy
                self.stepCount = stepCount
                self.maximumDistance = maximumDistance
            }
        }

        /// Creates fog.
        ///
        /// - Parameters:
        ///   - color: The color in linear RGB. Alpha scales the maximum amount of fog.
        ///   - startDistance: The camera distance where the fog starts.
        ///   - endDistance: The camera distance where the fog reaches full strength.
        ///   - densityExponent: The shape of the change. 1 is linear, and higher values make the fog thinner near the
        ///     start.
        ///   - scattering: Volumetric light scattering, or `nil` for distance fog only.
        public init(color: SIMD4<Float> = [0.7, 0.75, 0.8, 1], startDistance: Float = 5, endDistance: Float = 30, densityExponent: Float = 1, scattering: Scattering? = nil) {
            self.color = color
            self.startDistance = startDistance
            self.endDistance = endDistance
            self.densityExponent = densityExponent
            self.scattering = scattering
        }

        /// 0 (no fog) to color.w (full fog) at `distance` from the camera.
        public func amount(atDistance distance: Float) -> Float {
            let span = max(endDistance - startDistance, .ulpOfOne)
            let linear = min(max((distance - startDistance) / span, 0), 1)
            return pow(linear, max(densityExponent, .ulpOfOne)) * color.w
        }
    }
}
