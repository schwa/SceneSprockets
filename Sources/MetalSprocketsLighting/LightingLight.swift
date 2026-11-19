@_exported import MetalSprocketsLightingShaders
import simd

public extension LightingLight {
    static func directional(direction: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1) -> Self {
        var light = Self()
        light.type = .directional
        light.direction = simd_normalize(direction)
        light.color = color
        light.intensity = intensity
        return light
    }

    /// `range` 0 means infinite.
    static func point(position: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = 0) -> Self {
        var light = Self()
        light.type = .point
        light.position = position
        light.color = color
        light.intensity = intensity
        light.range = range
        return light
    }

    /// Cone angles are half-angles in radians; light fades from `innerConeAngle` to `outerConeAngle`.
    static func spot(position: SIMD3<Float>, direction: SIMD3<Float>, color: SIMD3<Float> = [1, 1, 1], intensity: Float = 1, range: Float = 0, innerConeAngle: Float = 0, outerConeAngle: Float = .pi / 4) -> Self {
        var light = point(position: position, color: color, intensity: intensity, range: range)
        light.type = .spot
        light.direction = simd_normalize(direction)
        light.innerConeCos = cos(innerConeAngle)
        light.outerConeCos = cos(outerConeAngle)
        return light
    }
}
