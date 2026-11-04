#pragma once

#import <simd/simd.h>

// Uniforms for the gradient sky background.
struct SkyGradientUniforms {
    // Clip space to world-space view direction: the inverse of projection times the view's rotation.
    simd_float4x4 inverseViewProjection;
    simd_float3 zenith;
    simd_float3 horizon;
    simd_float3 ground;
    float exponent;
};
typedef struct SkyGradientUniforms SkyGradientUniforms;
