import MetalSprocketsLighting
import MetalSprocketsLightingShaders
import simd

package extension LightingLight {
    // Lights point down their node's -Z axis. Every renderer converts scene lights here, so they agree (#592).
    init(_ light: Light, worldTransform: simd_float4x4, shadowSlices: Range<Int> = 0..<0) {
        self.init()
        position = SIMD3(worldTransform.columns.3.x, worldTransform.columns.3.y, worldTransform.columns.3.z)
        let forward = -SIMD3(worldTransform.columns.2.x, worldTransform.columns.2.y, worldTransform.columns.2.z)
        direction = simd_length(forward) > 0 ? simd_normalize(forward) : [0, 0, -1]
        color = light.color
        intensity = light.intensity
        // 0 is infinite in KHR_lights_punctual.
        range = light.range.isFinite ? light.range : 0
        innerConeCos = cos(light.innerConeAngle)
        outerConeCos = cos(light.outerConeAngle)
        type = switch light.type {
        case .directional: .directional
        case .spot: .spot
        case .point: .point
        }
        shadowSliceStart = Int32(shadowSlices.lowerBound)
        shadowSliceCount = Int32(shadowSlices.count)
    }
}

package extension RenderContext {
    // The context's lights with their shadow slices, positions relative to `cameraPosition`.
    func lightingLights(cameraPosition: SIMD3<Float>) -> [LightingLight] {
        lights.enumerated().map { index, entry in
            let slices = shadow != nil && index < lightShadowSlices.count ? lightShadowSlices[index] : 0..<0
            return LightingLight(entry.light, worldTransform: entry.worldTransform.cameraRelative(to: cameraPosition), shadowSlices: slices)
        }
    }
}
