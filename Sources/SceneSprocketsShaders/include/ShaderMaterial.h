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

// Bound by name as `lighting` when the material's `samplesShadows` is true, with `lights` (an array of
// `lightCount` LightingLight, camera-relative), `shadow` (LightingShadowUniforms), `shadowMap` (a
// depth2d_array<float>) and `shadowSampler`. Light them with Lighting::sample and shaderMaterialShadow.
struct ShaderMaterialLighting {
    int lightCount;
    // 0 when the frame has no shadows or the mesh does not receive them.
    int receivesShadow;
};
typedef struct ShaderMaterialLighting ShaderMaterialLighting;

#ifdef __METAL_VERSION__
#include <metal_stdlib>
#include "MetalSprocketsLighting.h"

// What multiplies `light`'s radiance at a camera-relative position: 1 where lit, towards the shadow color where
// shadowed. Each light's shadow dims only that light, as in Blinn-Phong and PBR.
static inline metal::float3 shaderMaterialShadow(
    constant ShaderMaterialLighting &lighting,
    LightingLight light,
    metal::float3 cameraRelativePosition,
    constant LightingShadowUniforms &shadow,
    metal::depth2d_array<float, metal::access::sample> shadowMap,
    metal::sampler shadowSampler
) {
    if (lighting.receivesShadow == 0) {
        return metal::float3(1);
    }
    return Lighting::shadow(light, cameraRelativePosition, shadow, shadowMap, shadowSampler);
}
#endif
