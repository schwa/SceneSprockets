import Foundation
import simd

/// A light's color and shape, like SCNLight. Its node places it: lights point down their node's -Z axis.
public struct Light: Sendable, Equatable, Codable {
    /// The shape of a light.
    public enum Kind: String, Sendable, Equatable, CaseIterable, Codable {
        /// Parallel rays along the node's -Z axis. The position of the node does not matter.
        case directional
        /// Light in all directions from the node's position.
        case point
        /// A cone of light along the node's -Z axis.
        case spot
        /// Even light from every direction, like SCNLight's `.ambient`: it lights every surface in its categories by
        /// `color * intensity`, without shading or shadows. The node's position and direction do not matter (#602).
        case ambient
    }

    /// The former name of ``Kind``.
    @available(*, deprecated, renamed: "Kind")
    public typealias LightType = Kind

    /// The shape of the light.
    public var type: Kind
    /// Linear RGB.
    public var color: SIMD3<Float>
    /// The brightness, which multiplies ``color``.
    public var intensity: Float
    /// Distance at which point and spot lights fade to nothing.
    public var range: Float
    /// Spot cone half-angles in radians: full intensity inside `innerConeAngle`, none outside `outerConeAngle`.
    public var innerConeAngle: Float
    /// The half-angle of a spot light's cone, in radians. Outside it, the light has no effect.
    public var outerConeAngle: Float
    /// Whether the light casts shadows when the scene has shadows, like SCNLight.castsShadow. Each shadow-casting light
    /// draws the casters again (a point light six times), so turn it off for fill and decorative lights.
    public var castsShadow: Bool
    /// A color temperature in kelvin that tints ``color``, like SCNLight.temperature: 6500 is white, lower is warmer,
    /// higher is cooler. Nil leaves the color unchanged.
    public var temperature: Float?
    /// SceneKit-style distance falloff for point and spot lights, instead of physical inverse-square falloff with
    /// ``range``. Nil keeps the physical falloff.
    public var attenuation: Attenuation?
    /// This light's shadow settings. Nil uses the defaults of ``Shadows``.
    public var shadowSettings: ShadowSettings?

    /// Shadow settings for one light, overriding ``Shadows``.
    public struct ShadowSettings: Sendable, Equatable, Codable {
        /// Directional lights only: the number of shadow map slices, each covering the scene up to a farther distance
        /// from the camera, so near shadows get more texels (cascaded shadow maps). 1 fits one view to the whole scene.
        public var cascadeCount: Int
        /// How cascade split distances are spaced, from 0 (even) to 1 (logarithmic: more cascades near the camera).
        public var splitFactor: Float
        /// The fraction of ``Shadows/resolution`` this light's slices use, from 0 to 1.
        public var resolutionScale: Float
        /// Replaces ``Shadows/depthBias`` for this light. Nil uses it.
        public var depthBias: Float?
        /// Replaces ``Shadows/slopeScale`` for this light. Nil uses it.
        public var slopeScale: Float?

        public init(cascadeCount: Int = 1, splitFactor: Float = 0.75, resolutionScale: Float = 1, depthBias: Float? = nil, slopeScale: Float? = nil) {
            self.cascadeCount = cascadeCount
            self.splitFactor = splitFactor
            self.resolutionScale = resolutionScale
            self.depthBias = depthBias
            self.slopeScale = slopeScale
        }
    }

    /// Distance falloff like SCNLight's attenuationStartDistance, attenuationEndDistance and
    /// attenuationFalloffExponent.
    public struct Attenuation: Sendable, Equatable, Codable {
        /// Full intensity up to this distance.
        public var startDistance: Float
        /// No light from this distance on.
        public var endDistance: Float
        /// The curve between: 1 is linear, 2 (the default) is quadratic.
        public var falloffExponent: Float

        public init(startDistance: Float = 0, endDistance: Float, falloffExponent: Float = 2) {
            self.startDistance = startDistance
            self.endDistance = endDistance
            self.falloffExponent = falloffExponent
        }
    }

    /// ``color`` tinted by ``temperature``.
    public var tintedColor: SIMD3<Float> {
        temperature.map { color * Self.color(temperature: $0) } ?? color
    }

    /// The linear RGB of a black body at `kelvin`, scaled so 6500 K is white. Tanner Helland's fit, 1000 K to 40000 K.
    public static func color(temperature kelvin: Float) -> SIMD3<Float> {
        func blackBody(_ kelvin: Float) -> SIMD3<Float> {
            let value = min(max(kelvin, 1_000), 40_000) / 100
            let red: Float = value <= 66 ? 255 : 329.698727446 * pow(value - 60, -0.1332047592)
            let green: Float = value <= 66 ? 99.4708025861 * log(value) - 161.1195681661 : 288.1221695283 * pow(value - 60, -0.0755148492)
            let blue: Float = value >= 66 ? 255 : (value <= 19 ? 0 : 138.5177312231 * log(value - 10) - 305.0447927307)
            let srgb = simd_clamp(SIMD3(red, green, blue) / 255, .zero, .one)
            // sRGB to linear.
            return SIMD3(srgb.indices.map { index in
                let channel = srgb[index]
                return channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            })
        }
        return blackBody(kelvin) / blackBody(6_500)
    }

    /// Creates a light.
    ///
    /// - Parameters:
    ///   - type: The shape of the light.
    ///   - color: The color, in linear RGB.
    ///   - intensity: The brightness.
    ///   - range: The distance where a point or spot light stops having an effect.
    ///   - innerConeAngle: The half-angle of a spot light's full-intensity cone, in radians.
    ///   - outerConeAngle: The half-angle of a spot light's cone, in radians.
    ///   - castsShadow: Whether the light casts shadows when the scene has shadows.
    public init(type: Kind, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6, castsShadow: Bool = true) {
        self.castsShadow = castsShadow
        self.type = type
        self.color = color
        self.intensity = intensity
        self.range = range
        self.innerConeAngle = innerConeAngle
        self.outerConeAngle = outerConeAngle
    }

    private enum CodingKeys: String, CodingKey {
        case type, color, intensity, range, innerConeAngle, outerConeAngle, castsShadow, temperature, attenuation, shadowSettings
    }

    /// Decodes a light. Archives from before `castsShadow` decode with shadows on.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Kind.self, forKey: .type)
        color = try container.decode(SIMD3<Float>.self, forKey: .color)
        intensity = try container.decode(Float.self, forKey: .intensity)
        range = try container.decode(Float.self, forKey: .range)
        innerConeAngle = try container.decode(Float.self, forKey: .innerConeAngle)
        outerConeAngle = try container.decode(Float.self, forKey: .outerConeAngle)
        castsShadow = try container.decodeIfPresent(Bool.self, forKey: .castsShadow) ?? true
        temperature = try container.decodeIfPresent(Float.self, forKey: .temperature)
        attenuation = try container.decodeIfPresent(Attenuation.self, forKey: .attenuation)
        shadowSettings = try container.decodeIfPresent(ShadowSettings.self, forKey: .shadowSettings)
    }

    /// Creates a spot light. It shines along its node's -Z axis.
    public static func spot(color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6, castsShadow: Bool = true) -> Self {
        Self(type: .spot, color: color, intensity: intensity, range: range, innerConeAngle: innerConeAngle, outerConeAngle: outerConeAngle, castsShadow: castsShadow)
    }

    /// Creates a point light. It shines in all directions from its node's position.
    public static func point(color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, castsShadow: Bool = true) -> Self {
        Self(type: .point, color: color, intensity: intensity, range: range, castsShadow: castsShadow)
    }

    /// Creates a directional light. Its rays are parallel to its node's -Z axis.
    public static func directional(color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, castsShadow: Bool = true) -> Self {
        Self(type: .directional, color: color, intensity: intensity, castsShadow: castsShadow)
    }
}
