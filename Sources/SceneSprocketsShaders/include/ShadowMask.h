#pragma once

#import <simd/simd.h>

#define SCENE_SHADOW_MAX_SLICES 8

// Uniforms for Shadows' screen-space mask pass.
struct SceneShadowMaskUniforms {
    // Clip space (with the renderer's reversed depth) to world space.
    simd_float4x4 inverseViewProjection;
    // World to light clip space, one per shadow map slice.
    simd_float4x4 sliceViewProjections[SCENE_SHADOW_MAX_SLICES];
    int sliceCount;
    float mapSize;
    // 0 leaves shadowed pixels unchanged, 1 multiplies them by `color`.
    float intensity;
    // Linear RGB multiplied into fully shadowed pixels; black darkens.
    simd_float3 color;
    // PCF kernel half-size in shadow map texels; 1 samples 3x3.
    int radius;
};
typedef struct SceneShadowMaskUniforms SceneShadowMaskUniforms;
