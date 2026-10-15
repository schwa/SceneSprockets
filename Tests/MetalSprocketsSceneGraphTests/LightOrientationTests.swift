import MetalSprocketsAddOns
import MetalSprocketsAddOnsShaders
import MetalSprocketsPBR
import Testing
import simd
@testable import MetalSprocketsSceneGraph

// Rotate -90° about X: the node's -Z axis points down (-Y).
private let pointingDown = simd_float4x4(simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])) * simd_float4x4(columns: ([1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]))

@Test
func blinnPhongLightsUseNodeOrientation() {
    var transform = pointingDown
    transform.columns.3 = [1, 2, 3, 1]
    let inputs = blinnPhongLights([(transform, Light.spot(intensity: 2))])
    #expect(inputs.count == 1)
    #expect(inputs[0].position == [1, 2, 3])
    #expect(simd_distance(inputs[0].direction, [0, -1, 0]) < 0.0001)
    #expect(inputs[0].light.type == .spot)
}

@Test
func pbrSpotLightUsesConeAngles() {
    let light = pbrLight(worldTransform: pointingDown, light: .spot(innerConeAngle: 0.2, outerConeAngle: 0.4))
    #expect(light.type == .spot)
    #expect(abs(light.innerConeCos - cos(0.2)) < 0.0001)
    #expect(abs(light.outerConeCos - cos(0.4)) < 0.0001)
    #expect(simd_distance(light.direction, [0, -1, 0]) < 0.0001)
}
