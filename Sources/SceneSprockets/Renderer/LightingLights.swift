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
        color = light.tintedColor
        intensity = light.intensity
        // 0 is infinite in KHR_lights_punctual.
        range = light.range.isFinite ? light.range : 0
        if let attenuation = light.attenuation {
            // The shader reads the end distance from `range`.
            range = attenuation.endDistance
            attenuationStartDistance = attenuation.startDistance
            attenuationFalloffExponent = max(attenuation.falloffExponent, 1e-3)
        }
        innerConeCos = cos(light.innerConeAngle)
        outerConeCos = cos(light.outerConeAngle)
        type = switch light.type {
        case .directional: .directional
        case .spot: .spot
        // Ambient lights are summed into RenderContext.ambientLight and never reach shaders as lights.
        case .point, .ambient: .point
        }
        shadowSliceStart = Int32(shadowSlices.lowerBound)
        shadowSliceCount = Int32(shadowSlices.count)
    }
}

package extension RenderContext {
    // The context's direct lights with their shadow slices, positions relative to `cameraPosition`. Ambient lights are
    // left out; they are in `ambientLight`.
    func lightingLights(cameraPosition: SIMD3<Float>) -> [LightingLight] {
        lights.enumerated().compactMap { index, entry in
            guard entry.light.type != .ambient else {
                return nil
            }
            let slices = shadow != nil && index < lightShadowSlices.count ? lightShadowSlices[index] : 0..<0
            var lightingLight = LightingLight(entry.light, worldTransform: entry.worldTransform.cameraRelative(to: cameraPosition), shadowSlices: slices)
            // Batches hold subsets of the lights, so the contact-shadow light is found by its transform (#495).
            if let contactShadowLight, entry.light.type == .directional, entry.worldTransform == contactShadowLight {
                lightingLight.contactShadow = 1
            }
            return lightingLight
        }
    }
}

public extension RenderContext {
    /// The sum of the context's ambient lights' `color * intensity`, in linear RGB. A batch's context holds only the
    /// lights whose categories match its entries, so category masks apply (#602).
    var ambientLight: SIMD3<Float> {
        lights.reduce(.zero) { sum, entry in
            entry.light.type == .ambient ? sum + entry.light.tintedColor * entry.light.intensity : sum
        }
    }
}
