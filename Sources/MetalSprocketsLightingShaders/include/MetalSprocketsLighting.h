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

    // SceneKit's attenuation: 1 up to `start`, 0 from `end` on, (remaining fraction)^exponent between.
    inline float falloffAttenuation(float start, float end, float exponent, float distance) {
        if (end <= start) {
            return distance <= start ? 1.0 : 0.0;
        }
        return metal::pow(metal::saturate((end - distance) / (end - start)), exponent);
    }

    inline float spotAttenuation(LightingLight light, float3 toLight) {
        const float cosine = metal::dot(metal::normalize(light.direction), -toLight);
        return metal::smoothstep(light.outerConeCos, light.innerConeCos, cosine);
    }

    // The lights to shade one fragment with (#519): its cluster's list, or every light when clustering is off.
    // Loop `for (uint i = 0; i < list.count; i++) { LightingLight light = lights[list[i]]; ... }`.
    struct LightList {
        // Nil when clustering is off; then the list is 0..<count.
        constant uint *indices;
        uint count;

        uint operator[](uint index) const {
            return indices ? indices[index] : index;
        }
    };

    // The cluster holding a shading-space `position`.
    inline uint clusterIndex(constant LightingClusterUniforms &clusters, float3 position) {
        const float3 relative = position + clusters.originOffset;
        const float4 clip = clusters.viewProjection * float4(relative, 1);
        const float2 ndc = clip.xy / metal::max(clip.w, 1e-6);
        const int3 size = int3(clusters.gridSize);
        const int x = metal::clamp(int(metal::floor((ndc.x * 0.5 + 0.5) * float(size.x))), 0, size.x - 1);
        const int y = metal::clamp(int(metal::floor((ndc.y * 0.5 + 0.5) * float(size.y))), 0, size.y - 1);
        const float distance = -(clusters.view * float4(relative, 1)).z;
        int slice = 0;
        if (distance > clusters.sliceNear) {
            slice = int(metal::floor(metal::log(distance / clusters.sliceNear) / metal::log(clusters.sliceFar / clusters.sliceNear) * float(size.z)));
        }
        slice = metal::clamp(slice, 0, size.z - 1);
        return uint((slice * size.y + y) * size.x + x);
    }

    // `clusters` and `clusterLights` may be null (no clustering): the list is then every one of `lightCount` lights.
    inline LightList lightList(constant LightingClusterUniforms *clusters, constant uint *clusterLights, float3 position, int lightCount) {
        if (clusters == nullptr || clusterLights == nullptr || clusters->enabled == 0) {
            return LightList { nullptr, uint(metal::max(lightCount, 0)) };
        }
        constant uint *cluster = clusterLights + clusterIndex(*clusters, position) * kLightingClusterStride;
        return LightList { cluster + 1, metal::min(cluster[0], uint(kLightingClusterMaxLights)) };
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
            attenuation = light.attenuationFalloffExponent > 0.0
                ? falloffAttenuation(light.attenuationStartDistance, light.range, light.attenuationFalloffExponent, distance)
                : rangeAttenuation(light.range, distance);
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
