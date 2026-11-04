import simd

// An environment image for image-based lighting and backgrounds. Renderer modules conform their own types
// (for example PBREnvironment); renderers ignore maps they do not understand.
public protocol EnvironmentMap: AnyObject {}

extension SceneGraph {
    public struct Environment {
        public enum Background {
            // Keep the render pass's clear color.
            case none
            // Linear RGBA.
            case color(SIMD4<Float>)
            // Draw `map` behind the scene. Blur 0 is sharp, 1 is the most blurred.
            case environment(blur: Float = 0)
            // A sky from three colors by view elevation; needs no environment map or PBR renderer.
            case gradient(SkyGradient)
        }

        // Linear RGB. Straight up is `zenith`, level is `horizon`, straight down is `ground`. `exponent` bends the
        // blend: above 1 keeps the horizon color over a wider band.
        public struct SkyGradient: Equatable, Codable, Sendable {
            public var zenith: SIMD3<Float>
            public var horizon: SIMD3<Float>
            public var ground: SIMD3<Float>
            public var exponent: Float

            public init(zenith: SIMD3<Float>, horizon: SIMD3<Float>, ground: SIMD3<Float>, exponent: Float = 1) {
                self.zenith = zenith
                self.horizon = horizon
                self.ground = ground
                self.exponent = exponent
            }
        }

        public var background: Background
        // Image-based lighting source, also used by `.environment` backgrounds. Nil lets renderers use their defaults.
        public var map: (any EnvironmentMap)?
        public var intensity: Float
        // Radians about +Y.
        public var rotation: Float

        public init(background: Background = .none, map: (any EnvironmentMap)? = nil, intensity: Float = 1, rotation: Float = 0) {
            self.background = background
            self.map = map
            self.intensity = intensity
            self.rotation = rotation
        }
    }
}
