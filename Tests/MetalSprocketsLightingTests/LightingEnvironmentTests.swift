import Metal
import MetalSprocketsLighting
import Testing

struct LightingEnvironmentTests {
    // Reads face 0, texel (0, 0) of `level`, as half floats.
    private func firstTexel(_ texture: any MTLTexture, level: Int = 0) -> SIMD4<Float> {
        var value = SIMD4<Float16>()
        texture.getBytes(&value, bytesPerRow: 8, bytesPerImage: 8, from: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: level, slice: 0)
        return SIMD4<Float>(value)
    }

    // The same radiance from every direction: prefiltering and convolution must give it back.
    @Test func uniformEnvironmentKeepsItsColor() throws {
        let color = SIMD3<Float>(0.5, 0.25, 1)
        let environment = try LightingEnvironment(source: .uniform(color), specularSize: 32, irradianceSize: 8)
        let irradiance = firstTexel(environment.irradiance)
        #expect(simd_distance(SIMD3(irradiance.x, irradiance.y, irradiance.z), color) < 0.01)
        let roughest = firstTexel(environment.specular, level: environment.specular.mipmapLevelCount - 1)
        #expect(simd_distance(SIMD3(roughest.x, roughest.y, roughest.z), color) < 0.01)
        #expect(environment.brdfLookup.pixelFormat == .rg16Float)
    }
}
