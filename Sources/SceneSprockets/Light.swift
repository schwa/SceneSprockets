/// A light's color and shape, like SCNLight. Its node places it: lights point down their node's -Z axis.
public struct Light: Sendable, Equatable, Codable {
    /// The shape of a light.
    public enum LightType: String, Sendable, Equatable, CaseIterable, Codable {
        /// Parallel rays along the node's -Z axis. The position of the node does not matter.
        case directional
        /// Light in all directions from the node's position.
        case point
        /// A cone of light along the node's -Z axis.
        case spot
    }

    /// The shape of the light.
    public var type: LightType
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

    /// Creates a light.
    ///
    /// - Parameters:
    ///   - type: The shape of the light.
    ///   - color: The color, in linear RGB.
    ///   - intensity: The brightness.
    ///   - range: The distance where a point or spot light stops having an effect.
    ///   - innerConeAngle: The half-angle of a spot light's full-intensity cone, in radians.
    ///   - outerConeAngle: The half-angle of a spot light's cone, in radians.
    public init(type: LightType, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6) {
        self.type = type
        self.color = color
        self.intensity = intensity
        self.range = range
        self.innerConeAngle = innerConeAngle
        self.outerConeAngle = outerConeAngle
    }

    /// Creates a spot light.
    public static func spot(color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6) -> Self {
        Self(type: .spot, color: color, intensity: intensity, range: range, innerConeAngle: innerConeAngle, outerConeAngle: outerConeAngle)
    }
}
