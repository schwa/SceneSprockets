#pragma once

#import <simd/simd.h>

// Uniforms for the screen-space fog pass.
struct FogUniforms {
    // Clip space (with the renderer's reversed depth) to world space.
    simd_float4x4 inverseViewProjection;
    simd_float3 cameraPosition;
    // Linear RGB; w scales the maximum fog amount.
    simd_float4 color;
    float startDistance;
    float endDistance;
    float densityExponent;
};
typedef struct FogUniforms FogUniforms;
