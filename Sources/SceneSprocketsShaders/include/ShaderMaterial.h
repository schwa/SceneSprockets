#pragma once

#import <simd/simd.h>

// Bound by name as `transforms` to a ShaderMaterial's vertex function (and fragment function, if it declares one).
// Copy this layout, or include this header, in custom shaders.
struct ShaderMaterialTransforms {
    simd_float4x4 modelMatrix;
    simd_float4x4 viewMatrix;
    // Includes the renderer's reversed depth.
    simd_float4x4 projectionMatrix;
    simd_float4x4 modelViewProjectionMatrix;
    // Inverse transpose of the model matrix, for normals.
    simd_float4x4 normalMatrix;
    simd_float3 cameraPosition;
    // The node's inherited opacity. Multiply the output alpha by it to support fading; the renderer already blends
    // when it is below 1.
    float opacity;
    // The model matrix with the camera at the origin: its translation is model minus camera position, subtracted in
    // double precision. Far from the world origin, derive positions from this, not from modelMatrix (#251).
    simd_float4x4 cameraRelativeModelMatrix;
    // The view matrix without the camera's translation. projectionMatrix * cameraRelativeViewMatrix *
    // cameraRelativeModelMatrix equals modelViewProjectionMatrix.
    simd_float4x4 cameraRelativeViewMatrix;
    // Stereo (#379): with vertex amplification, index these by [[amplification_id]]. Entry 0 is the only view in mono;
    // in stereo, cameraRelativeModelMatrix is relative to a center camera between the eyes. Model matrix to clip space
    // per view:
    simd_float4x4 modelViewProjectionMatrices[2];
    // Per view: the eye minus the camera position (zero in mono). The direction to the eye is this minus a
    // camera-relative position.
    simd_float3 cameraRelativeEyePositions[2];
};
typedef struct ShaderMaterialTransforms ShaderMaterialTransforms;

#define SHADER_MATERIAL_LIGHT_DIRECTIONAL 0
#define SHADER_MATERIAL_LIGHT_POINT 1
#define SHADER_MATERIAL_LIGHT_SPOT 2

// One light, bound by name as `lights` (an array of `lighting.lightCount`) when the material's `samplesShadows` is
// true. Positions are camera-relative (world minus camera position).
struct ShaderMaterialLight {
    simd_float3 position;
    // The way the light points (travels). Used by directional and spot lights.
    simd_float3 direction;
    // Linear RGB times intensity.
    simd_float3 color;
    int type;
    float range;
    // Cosines of the spot cone half-angles.
    float innerConeCos;
    float outerConeCos;
    // This light's shadow map slices; count 0 casts no shadow.
    int shadowSliceStart;
    int shadowSliceCount;
};
typedef struct ShaderMaterialLight ShaderMaterialLight;

// Bound by name as `lighting` when the material's `samplesShadows` is true, with `lights`, `shadowMap` (a
// depth2d_array<float>) and `shadowSampler`. Pass them to shaderMaterialShadow.
struct ShaderMaterialLighting {
    // Camera-relative position to light clip space, one per shadow map slice.
    simd_float4x4 shadowSliceViewProjections[8];
    int lightCount;
    // 0 when the frame has no shadows or the mesh does not receive them.
    int receivesShadow;
    float shadowMapSize;
    // 0 leaves shadowed light unchanged, 1 scales it fully by `shadowColor`.
    float shadowIntensity;
    simd_float3 shadowColor;
    // PCF half-size in texels.
    int shadowRadius;
};
typedef struct ShaderMaterialLighting ShaderMaterialLighting;

#ifdef __METAL_VERSION__
#include <metal_stdlib>

// What multiplies `light`'s contribution at a camera-relative position: 1 where lit, towards `shadowColor` where
// shadowed. Each light's shadow dims only that light, as in Blinn-Phong and PBR.
static inline metal::float3 shaderMaterialShadow(
    constant ShaderMaterialLighting &lighting,
    ShaderMaterialLight light,
    metal::float3 cameraRelativePosition,
    metal::depth2d_array<float, metal::access::sample> shadowMap,
    metal::sampler shadowSampler
) {
    if (lighting.receivesShadow == 0 || light.shadowSliceCount <= 0) {
        return metal::float3(1);
    }
    float lit = 1;
    float texel = 1.0 / lighting.shadowMapSize;
    int radius = lighting.shadowRadius;
    float side = float(2 * radius + 1);
    for (int slice = light.shadowSliceStart; slice < light.shadowSliceStart + light.shadowSliceCount; slice++) {
        metal::float4 clip = lighting.shadowSliceViewProjections[slice] * metal::float4(cameraRelativePosition, 1);
        metal::float3 ndc = clip.xyz / clip.w;
        metal::float2 uv = metal::float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        if (metal::any(uv < 0.0) || metal::any(uv > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            continue;
        }
        float sum = 0;
        for (int x = -radius; x <= radius; x++) {
            for (int y = -radius; y <= radius; y++) {
                sum += shadowMap.sample_compare(shadowSampler, uv + metal::float2(x, y) * texel, uint(slice), ndc.z, metal::level(0));
            }
        }
        lit *= sum / (side * side);
    }
    return metal::mix(metal::float3(1), lighting.shadowColor, lighting.shadowIntensity * (1.0 - lit));
}

// The light reaching a camera-relative position and the direction towards it, with the same falloff as Blinn-Phong.
static inline metal::float3 shaderMaterialIncomingLight(ShaderMaterialLight light, metal::float3 cameraRelativePosition, thread metal::float3 &toLight) {
    if (light.type == SHADER_MATERIAL_LIGHT_DIRECTIONAL) {
        toLight = -light.direction;
        return light.color;
    }
    toLight = light.position - cameraRelativePosition;
    float distanceSquared = metal::length_squared(toLight);
    toLight = metal::normalize(toLight);
    float rangeRatio = metal::sqrt(distanceSquared) / light.range;
    float rangeFalloff = metal::saturate(1.0 - rangeRatio * rangeRatio * rangeRatio * rangeRatio);
    float attenuation = rangeFalloff * rangeFalloff / (distanceSquared + 1.0);
    if (light.type == SHADER_MATERIAL_LIGHT_SPOT) {
        attenuation *= metal::smoothstep(light.outerConeCos, light.innerConeCos, metal::dot(-toLight, light.direction));
    }
    return light.color * attenuation;
}
#endif
