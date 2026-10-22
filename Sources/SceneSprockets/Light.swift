// A light's color and shape, like SCNLight. Its node places it: lights point down their node's -Z axis.
public struct Light: Sendable, Equatable, Codable {
    public enum LightType: Sendable, Equatable, Codable {
        // Parallel rays along the node's -Z; position does not matter.
        case directional
        case point
        // A cone along the node's -Z.
        case spot
    }

    public var type: LightType
    // Linear RGB.
    public var color: SIMD3<Float>
    public var intensity: Float
    // Distance at which point and spot lights fade to nothing.
    public var range: Float
    // Spot cone half-angles in radians: full intensity inside `innerConeAngle`, none outside `outerConeAngle`.
    public var innerConeAngle: Float
    public var outerConeAngle: Float

    public init(type: LightType, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6) {
        self.type = type
        self.color = color
        self.intensity = intensity
        self.range = range
        self.innerConeAngle = innerConeAngle
        self.outerConeAngle = outerConeAngle
    }

    public static func spot(color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = .infinity, innerConeAngle: Float = .pi / 8, outerConeAngle: Float = .pi / 6) -> Self {
        Self(type: .spot, color: color, intensity: intensity, range: range, innerConeAngle: innerConeAngle, outerConeAngle: outerConeAngle)
    }
}
