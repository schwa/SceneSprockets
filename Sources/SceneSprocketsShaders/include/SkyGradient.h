#pragma once

#import <simd/simd.h>

// Uniforms for the gradient sky background.
struct SkyGradientUniforms {
    // Per view (1, or 2 for stereo): clip space to world-space view direction, the inverse of projection times the
    // view's rotation.
    simd_float4x4 inverseViewProjections[2];
    simd_float3 zenith;
    simd_float3 horizon;
    simd_float3 ground;
    float exponent;
};
typedef struct SkyGradientUniforms SkyGradientUniforms;
