#pragma once

#import <simd/simd.h>

// One particle as drawn: a camera-facing square.
struct ParticleInstance {
    // xyz: world position, w: size (full width).
    simd_float4 positionSize;
    // Linear RGBA.
    simd_float4 color;
};
typedef struct ParticleInstance ParticleInstance;

struct ParticleUniforms {
    // World to clip space, with the renderer's reversed depth.
    simd_float4x4 viewProjection;
    // The camera's world right and up axes.
    simd_float4 right;
    simd_float4 up;
};
typedef struct ParticleUniforms ParticleUniforms;
