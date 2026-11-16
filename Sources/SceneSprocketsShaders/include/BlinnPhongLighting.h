#pragma once

// Blinn-Phong lighting shared by the mesh shader and other surfaces that make their own position and normal, such as
// raymarched SDFs. Metal only.
#ifdef __METAL_VERSION__

#include <metal_stdlib>
#include "BlinnPhong.h"

namespace BlinnPhong {

    // A surface point's material after textures and vertex colors are applied.
    struct Surface {
        metal::float3 ambient;
        metal::float3 diffuse;
        metal::float3 specular;
        metal::float3 emission;
        float shininess;
        float alpha;
        bool receivesShadow;
    };

    // PCF in one slice; 1 is lit. Positions outside the slice's view are lit.
    inline float sliceShadow(metal::float3 world, metal::float4x4 viewProjection, float mapSize, int radius, metal::depth2d_array<float, metal::access::sample> shadowMap, metal::sampler shadowSampler, uint slice) {
        metal::float4 clip = viewProjection * metal::float4(world, 1);
        metal::float3 ndc = clip.xyz / clip.w;
        metal::float2 uv = metal::float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        if (metal::any(uv < 0.0) || metal::any(uv > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            return 1;
        }
        float shadow = 0;
        float texel = 1.0 / mapSize;
        for (int x = -radius; x <= radius; x++) {
            for (int y = -radius; y <= radius; y++) {
                shadow += shadowMap.sample_compare(shadowSampler, uv + metal::float2(x, y) * texel, slice, ndc.z, metal::level(0));
            }
        }
        float side = float(2 * radius + 1);
        return shadow / (side * side);
    }

    // The lit color of `surface` at `position` (camera-relative) with unit `normal`. `occlusion` scales ambient light.
    // `shadowMap`, `shadowSampler` and `shadow` are only read when `hasShadows` is true.
    inline metal::float4 shade(
        Surface surface,
        metal::float3 position,
        metal::float3 normal,
        metal::float3 cameraPosition,
        constant BlinnPhongFrame &frame,
        constant BlinnPhongLight *lights,
        float occlusion,
        bool hasShadows,
        metal::depth2d_array<float, metal::access::sample> shadowMap,
        metal::sampler shadowSampler,
        constant BlinnPhongShadowUniforms &shadow
    ) {
        metal::float3 viewDirection = metal::normalize(cameraPosition - position);
        metal::float3 diffuse = 0;
        metal::float3 specular = 0;
        for (int index = 0; index < frame.lightCount; index++) {
            BlinnPhongLight light = lights[index];
            // From the surface towards the light.
            metal::float3 toLight;
            float attenuation = 1;
            if (light.type == BLINN_PHONG_LIGHT_DIRECTIONAL) {
                toLight = -light.direction;
            } else {
                toLight = light.position - position;
                float distanceSquared = metal::length_squared(toLight);
                toLight = metal::normalize(toLight);
                // Inverse-square with a smooth cutoff at `range`.
                float rangeRatio = metal::sqrt(distanceSquared) / light.range;
                float rangeFalloff = metal::saturate(1.0 - rangeRatio * rangeRatio * rangeRatio * rangeRatio);
                attenuation = rangeFalloff * rangeFalloff / (distanceSquared + 1.0);
                if (light.type == BLINN_PHONG_LIGHT_SPOT) {
                    attenuation *= metal::smoothstep(light.outerConeCos, light.innerConeCos, metal::dot(-toLight, light.direction));
                }
            }
            float lambertian = metal::max(metal::dot(toLight, normal), 0.0);
            if (lambertian == 0.0 || attenuation == 0.0) {
                continue;
            }
            float highlight = metal::pow(metal::max(metal::dot(metal::normalize(toLight + viewDirection), normal), 0.0), surface.shininess);
            // Only this light's shadow scales only this light's contribution.
            metal::float3 shadowing = 1;
            if (hasShadows && surface.receivesShadow && light.shadowSliceCount > 0) {
                float lit = 1;
                for (int slice = light.shadowSliceStart; slice < light.shadowSliceStart + light.shadowSliceCount; slice++) {
                    lit *= sliceShadow(position, shadow.sliceViewProjections[slice], shadow.mapSize, shadow.radius, shadowMap, shadowSampler, uint(slice));
                }
                shadowing = metal::mix(metal::float3(1), shadow.color, shadow.intensity * (1.0 - lit));
            }
            diffuse += surface.diffuse * lambertian * light.color * attenuation * shadowing;
            specular += surface.specular * highlight * light.color * attenuation * shadowing;
        }
        return metal::float4(frame.ambientLightColor * surface.ambient * occlusion + diffuse + specular + surface.emission, surface.alpha);
    }

    // Material channel views (#195), matching MaterialChannel; returns false for lit output. Blinn-Phong has no
    // metallic, and roughness comes from shininess as in the usual Phong-to-microfacet mapping.
    inline bool channelColor(Surface surface, int channel, thread metal::float4 &color) {
        switch (channel) {
            case 1: color = metal::float4(surface.diffuse, 1); return true;
            case 2: color = metal::float4(metal::float3(surface.alpha), 1); return true;
            case 3: color = metal::float4(0, 0, 0, 1); return true;
            case 4: color = metal::float4(metal::float3(metal::sqrt(2.0 / (surface.shininess + 2.0))), 1); return true;
            case 5: color = metal::float4(surface.specular, 1); return true;
            case 6: color = metal::float4(surface.emission, 1); return true;
            default: return false;
        }
    }

}

#endif
