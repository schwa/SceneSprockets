import simd

/// An environment image for image-based lighting and backgrounds. Renderer modules conform their own types
/// (for example PBREnvironment); renderers ignore maps they do not understand.
public protocol EnvironmentMap: AnyObject {}

extension SceneGraph {
    /// The background and image-based lighting of a scene.
    public struct Environment {
        /// What a scene draws behind its geometry.
        public enum Background {
            /// Nothing: the render pass's clear color stays.
            case none
            /// A color, in linear RGBA.
            case color(SIMD4<Float>)
            /// The environment ``map``. A blur of 0 is sharp, and 1 is the most blurred.
            case environment(blur: Float = 0)
            /// A sky made from three colors by view elevation. It needs no environment map and no PBR renderer.
            case gradient(SkyGradient)
        }

        /// A sky background made from three colors by view elevation.
        ///
        /// The colors are in linear RGB. Straight up is ``zenith``, level is ``horizon``, and straight down is
        /// ``ground``.
        public struct SkyGradient: Equatable, Codable, Sendable {
            /// The color straight up.
            public var zenith: SIMD3<Float>
            /// The color at the horizon.
            public var horizon: SIMD3<Float>
            /// The color straight down.
            public var ground: SIMD3<Float>
            /// The shape of the blend. Values more than 1 keep the horizon color over a wider band.
            public var exponent: Float

            /// Creates a sky gradient.
            public init(zenith: SIMD3<Float>, horizon: SIMD3<Float>, ground: SIMD3<Float>, exponent: Float = 1) {
                self.zenith = zenith
                self.horizon = horizon
                self.ground = ground
                self.exponent = exponent
            }
        }

        /// What the scene draws behind its geometry.
        public var background: Background
        /// Image-based lighting source, also used by `.environment` backgrounds. Nil lets renderers use their defaults.
        public var map: (any EnvironmentMap)?
        /// The strength of the image-based lighting.
        public var intensity: Float
        /// Radians about +Y.
        public var rotation: Float

        /// Creates an environment.
        ///
        /// - Parameters:
        ///   - background: What the scene draws behind its geometry.
        ///   - map: The image-based lighting source, or `nil` for the renderers' defaults.
        ///   - intensity: The strength of the image-based lighting.
        ///   - rotation: The rotation of the map about +Y, in radians.
        public init(background: Background = .none, map: (any EnvironmentMap)? = nil, intensity: Float = 1, rotation: Float = 0) {
            self.background = background
            self.map = map
            self.intensity = intensity
            self.rotation = rotation
        }
    }
}
