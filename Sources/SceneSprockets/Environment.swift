import MetalSprocketsLighting
import simd

/// An environment image for image-based lighting and backgrounds. Renderer modules conform their own types
/// (for example LightingEnvironment); renderers ignore maps they do not understand.
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
        /// Screen-space ambient occlusion; nil turns it off.
        public var ambientOcclusion: AmbientOcclusion?
        /// Screen-space contact shadows from the brightest directional light; nil turns them off.
        public var contactShadows: ContactShadows?
        /// Draws straight-alpha transparent Blinn-Phong and PBR meshes with weighted blended order-independent
        /// transparency (#494) instead of sorting them, so intersecting and interleaved surfaces blend without order
        /// errors. An approximation: the result is an average, so a near, opaque-looking layer is less dominant than
        /// with sorting. Other blend modes and materials stay sorted. Needs readable view targets (see
        /// ``Shadows/requiredColorUsage``) and no multisampled view target; not in stereo.
        public var orderIndependentTransparency = false
        /// Multiplies the light before tone mapping, for every renderer.
        public var exposure: Float
        /// How every renderer turns linear light into display values.
        public var toneMapping: LightingToneMapping

        /// Creates an environment.
        ///
        /// - Parameters:
        ///   - background: What the scene draws behind its geometry.
        ///   - map: The image-based lighting source, or `nil` for the renderers' defaults.
        ///   - intensity: The strength of the image-based lighting.
        ///   - rotation: The rotation of the map about +Y, in radians.
        ///   - ambientOcclusion: Screen-space ambient occlusion, or `nil` for none.
        ///   - exposure: Multiplies the light before tone mapping.
        ///   - toneMapping: How linear light becomes display values.
        public init(background: Background = .none, map: (any EnvironmentMap)? = nil, intensity: Float = 1, rotation: Float = 0, ambientOcclusion: AmbientOcclusion? = nil, exposure: Float = 1, toneMapping: LightingToneMapping = .pbrNeutral) {
            self.background = background
            self.map = map
            self.intensity = intensity
            self.rotation = rotation
            self.ambientOcclusion = ambientOcclusion
            self.exposure = exposure
            self.toneMapping = toneMapping
        }
    }

    /// Screen-space contact shadows (#495): the small shadows where objects touch, which shadow maps miss. Each pixel
    /// marches toward the brightest directional light through the scene's depth. Blinn-Phong and PBR dim that light by
    /// it while shading. Needs readable view targets (see ``Shadows/requiredColorUsage``); not drawn in stereo.
    public struct ContactShadows: Sendable, Equatable, Codable {
        /// How far toward the light to march, in world units.
        public var length: Float
        /// How thick a surface counts as, in world units: depth behind it farther than this does not shadow.
        public var thickness: Float
        /// 0 leaves the light unchanged, 1 removes it where shadowed.
        public var strength: Float
        /// Steps per pixel.
        public var stepCount: Int

        public init(length: Float = 0.3, thickness: Float = 0.1, strength: Float = 1, stepCount: Int = 16) {
            self.length = length
            self.thickness = thickness
            self.strength = strength
            self.stepCount = stepCount
        }
    }
}
