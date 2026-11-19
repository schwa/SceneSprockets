#pragma once

#include "MetalSprocketsLightingTypes.h"

#ifdef __METAL_VERSION__
#include <metal_stdlib>

namespace Lighting {
    using namespace metal;

    // KHR_lights_punctual range attenuation: inverse square, cut off smoothly at `range` (0 means infinite).
    inline float rangeAttenuation(float range, float distance) {
        const float inverseSquare = 1.0 / metal::max(distance * distance, 1e-4);
        if (range <= 0.0) {
            return inverseSquare;
        }
        return metal::clamp(1.0 - metal::pow(distance / range, 4.0), 0.0, 1.0) * inverseSquare;
    }

    inline float spotAttenuation(LightingLight light, float3 toLight) {
        const float cosine = metal::dot(metal::normalize(light.direction), -toLight);
        return metal::smoothstep(light.outerConeCos, light.innerConeCos, cosine);
    }

    // The light arriving at a point, before shadows.
    struct LightSample {
        // Unit vector from the point toward the light.
        float3 toLight;
        // color * intensity * attenuation.
        float3 radiance;
    };

    inline LightSample sample(LightingLight light, float3 position) {
        LightSample result;
        float attenuation = 1.0;
        if (light.type == kLightingLightTypeDirectional) {
            result.toLight = -metal::normalize(light.direction);
        } else {
            const float3 delta = light.position - position;
            const float distance = metal::length(delta);
            result.toLight = delta / metal::max(distance, 1e-6);
            attenuation = rangeAttenuation(light.range, distance);
            if (light.type == kLightingLightTypeSpot) {
                attenuation *= spotAttenuation(light, result.toLight);
            }
        }
        result.radiance = light.color * light.intensity * attenuation;
        return result;
    }

    // PCF in one slice; 1 is lit. Positions outside the slice's view are lit.
    inline float sliceShadow(float3 position, float4x4 viewProjection, float mapSize, int radius, metal::depth2d_array<float> shadowMap, metal::sampler shadowSampler, uint slice) {
        const float4 clip = viewProjection * float4(position, 1);
        const float3 ndc = clip.xyz / clip.w;
        const float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        if (metal::any(uv < 0.0) || metal::any(uv > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            return 1.0;
        }
        float lit = 0.0;
        const float texel = 1.0 / mapSize;
        for (int x = -radius; x <= radius; x++) {
            for (int y = -radius; y <= radius; y++) {
                lit += shadowMap.sample_compare(shadowSampler, uv + float2(x, y) * texel, slice, ndc.z, metal::level(0));
            }
        }
        const float side = float(2 * radius + 1);
        return lit / (side * side);
    }

    // How much of `light` reaches `position`: the product of its slices' PCF results, tinted by the shadow color and
    // scaled by the shadow intensity. Multiply a LightSample's radiance by it.
    inline float3 shadow(LightingLight light, float3 position, constant LightingShadowUniforms &uniforms, metal::depth2d_array<float> shadowMap, metal::sampler shadowSampler) {
        if (uniforms.enabled == 0 || light.shadowSliceCount <= 0) {
            return float3(1.0);
        }
        float lit = 1.0;
        const int end = metal::min(light.shadowSliceStart + light.shadowSliceCount, kLightingMaxShadowSliceCount);
        for (int slice = metal::max(light.shadowSliceStart, 0); slice < end; slice++) {
            lit *= sliceShadow(position, uniforms.sliceViewProjections[slice], uniforms.mapSize, uniforms.radius, shadowMap, shadowSampler, uint(slice));
        }
        return metal::mix(float3(1.0), uniforms.color, uniforms.intensity * (1.0 - lit));
    }
} // namespace Lighting

#endif
