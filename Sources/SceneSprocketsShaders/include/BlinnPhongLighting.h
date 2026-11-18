#pragma once

// Blinn-Phong lighting shared by the mesh shader and other surfaces that make their own position and normal, such as
// raymarched SDFs. Metal only.
#ifdef __METAL_VERSION__

#include <metal_stdlib>
#include "MetalSprocketsLighting.h"
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

    // The lit color of `surface` at `position` (camera-relative) with unit `normal`. `occlusion` scales ambient light.
    // `shadowMap`, `shadowSampler` and `shadow` are only read when `hasShadows` is true.
    inline metal::float4 shade(
        Surface surface,
        metal::float3 position,
        metal::float3 normal,
        metal::float3 cameraPosition,
        constant BlinnPhongFrame &frame,
        constant LightingLight *lights,
        float occlusion,
        bool hasShadows,
        metal::depth2d_array<float, metal::access::sample> shadowMap,
        metal::sampler shadowSampler,
        constant LightingShadowUniforms &shadow
    ) {
        metal::float3 viewDirection = metal::normalize(cameraPosition - position);
        metal::float3 diffuse = 0;
        metal::float3 specular = 0;
        for (int index = 0; index < frame.lightCount; index++) {
            const LightingLight light = lights[index];
            const Lighting::LightSample lightSample = Lighting::sample(light, position);
            const metal::float3 toLight = lightSample.toLight;
            float lambertian = metal::max(metal::dot(toLight, normal), 0.0);
            if (lambertian == 0.0 || metal::all(lightSample.radiance == 0.0)) {
                continue;
            }
            float highlight = metal::pow(metal::max(metal::dot(metal::normalize(toLight + viewDirection), normal), 0.0), surface.shininess);
            // Only this light's shadow scales only this light's contribution.
            metal::float3 radiance = lightSample.radiance;
            if (hasShadows && surface.receivesShadow) {
                radiance *= Lighting::shadow(light, position, shadow, shadowMap, shadowSampler);
            }
            diffuse += surface.diffuse * lambertian * radiance;
            specular += surface.specular * highlight * radiance;
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
