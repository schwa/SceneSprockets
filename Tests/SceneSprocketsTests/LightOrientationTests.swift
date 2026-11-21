import Foundation
import MetalSprocketsPBR
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
@testable import SceneSprocketsPBR
import SceneSprocketsShaders
import simd
import Testing

// Rotate -90° about X: the node's -Z axis points down (-Y).
private let pointingDown = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])) * simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]))

@Test
func lightingLightUsesNodeOrientation() {
    var transform = pointingDown
    transform.columns.3 = [1, 2, 3, 1]
    let light = LightingLight(Light.spot(intensity: 2), worldTransform: transform, shadowSlices: 2..<5)
    #expect(light.position == [1, 2, 3])
    #expect(simd_distance(light.direction, [0, -1, 0]) < 0.0001)
    #expect(light.type == .spot)
    #expect(light.color == [1, 1, 1])
    #expect(light.intensity == 2)
    // Infinite range is 0, as in KHR_lights_punctual.
    #expect(light.range == 0)
    #expect(light.shadowSliceStart == 2)
    #expect(light.shadowSliceCount == 3)
}

@Test
func pbrSpotLightUsesConeAngles() {
    let light = LightingLight(.spot(innerConeAngle: 0.2, outerConeAngle: 0.4), worldTransform: pointingDown)
    #expect(light.type == .spot)
    #expect(abs(light.innerConeCos - cos(0.2)) < 0.0001)
    #expect(abs(light.outerConeCos - cos(0.4)) < 0.0001)
    #expect(simd_distance(light.direction, [0, -1, 0]) < 0.0001)
}

// #86: temperature tints the color the renderers get; 6500 K is white, low is warm, high is cool.
@Test
func temperatureTintsLightColor() {
    #expect(simd_distance(Light.color(temperature: 6_500), [1, 1, 1]) < 1e-4)
    let warm = Light.color(temperature: 2_700)
    #expect(warm.x > warm.z)
    let cool = Light.color(temperature: 12_000)
    #expect(cool.z > cool.x)
    var light = Light(type: .point, color: [0.5, 0.5, 0.5])
    light.temperature = 2_700
    #expect(simd_distance(LightingLight(light, worldTransform: matrix_identity_float4x4).color, warm * 0.5) < 1e-5)
}

// #86: SceneKit-style attenuation reaches the shader as start distance, falloff exponent and the end in `range`.
@Test
func attenuationIsPassedToShaders() throws {
    var light = Light(type: .spot, range: 20)
    light.attenuation = .init(startDistance: 2, endDistance: 10, falloffExponent: 1)
    light.temperature = 4_000
    let converted = LightingLight(light, worldTransform: matrix_identity_float4x4)
    #expect(converted.range == 10)
    #expect(converted.attenuationStartDistance == 2)
    #expect(converted.attenuationFalloffExponent == 1)
    #expect(LightingLight(Light(type: .point), worldTransform: matrix_identity_float4x4).attenuationFalloffExponent == 0)
    let decoded = try JSONDecoder().decode(Light.self, from: JSONEncoder().encode(light))
    #expect(decoded == light)
}
