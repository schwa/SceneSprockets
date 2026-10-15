#pragma once

#import <simd/simd.h>

// Uniforms for the color adjustment pass.
struct ColorAdjustUniforms {
    // Multiplies color: 2 ^ exposure.
    float exposureScale;
    // 1 leaves color unchanged.
    float contrast;
    float saturation;
    // 0 is off.
    float vignetteIntensity;
    // Fraction of the center-to-corner distance where the vignette starts.
    float vignetteRadius;
};
typedef struct ColorAdjustUniforms ColorAdjustUniforms;

// Uniforms for screen-space ambient occlusion.
struct AmbientOcclusionUniforms {
    // Clip space (with the renderer's reversed depth) to world space, and back.
    simd_float4x4 inverseViewProjection;
    simd_float4x4 viewProjection;
    simd_float3 cameraPosition;
    // World-space sampling radius.
    float radius;
    // 0 leaves pixels unchanged, 1 darkens fully occluded ones to black.
    float intensity;
    int sampleCount;
};
typedef struct AmbientOcclusionUniforms AmbientOcclusionUniforms;
