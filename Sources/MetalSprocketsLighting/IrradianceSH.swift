import simd

/// Diffuse indirect light arriving at a point from every direction, as first-order (L1) spherical harmonics (#532).
///
/// Each row is one color channel: (constant, y, z, x). The irradiance divided by pi for a surface with unit normal
/// `n` is `max(0, row.x + row.y * n.y + row.z * n.z + row.w * n.x)` per channel, so a diffuse color multiplied by it
/// gives the reflected radiance, as an irradiance environment map would.
public struct IrradianceSH: Sendable, Equatable, Codable {
    public var red: SIMD4<Float>
    public var green: SIMD4<Float>
    public var blue: SIMD4<Float>

    public static let zero = Self(red: .zero, green: .zero, blue: .zero)

    public init(red: SIMD4<Float>, green: SIMD4<Float>, blue: SIMD4<Float>) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Irradiance divided by pi for a surface facing `normal`.
    public func evaluate(normal: SIMD3<Float>) -> SIMD3<Float> {
        let basis = SIMD4<Float>(1, normal.y, normal.z, normal.x)
        return simd_max(SIMD3(simd_dot(red, basis), simd_dot(green, basis), simd_dot(blue, basis)), .zero)
    }

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(red: lhs.red + rhs.red, green: lhs.green + rhs.green, blue: lhs.blue + rhs.blue)
    }

    public static func += (lhs: inout Self, rhs: Self) {
        lhs = lhs + rhs
    }

    public static func * (lhs: Self, rhs: Float) -> Self {
        Self(red: lhs.red * rhs, green: lhs.green * rhs, blue: lhs.blue * rhs)
    }
}
