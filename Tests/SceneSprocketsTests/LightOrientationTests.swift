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
