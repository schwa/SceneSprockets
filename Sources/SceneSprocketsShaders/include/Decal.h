#pragma once

#import <simd/simd.h>

// Uniforms for DecalRenderer (#397). Positions are camera-relative (camera at the origin).
struct DecalUniforms {
    // The projector box (a unit cube) to clip space.
    simd_float4x4 modelViewProjection;
    // Camera-relative positions to the box's unit space, where the box spans -0.5...0.5.
    simd_float4x4 inverseModel;
    // Clip space (reversed depth) to camera-relative positions.
    simd_float4x4 inverseViewProjection;
    // Linear RGBA, multiplied with the texture.
    simd_float4 color;
    // The direction the decal faces, camera-relative: surfaces facing it get the full decal.
    simd_float3 axis;
    simd_float2 viewSize;
    // Cosines of the angle between the surface normal and `axis` where the decal starts fading, and where it is gone.
    float fadeStartCosine;
    float fadeEndCosine;
    int hasTexture;
};
typedef struct DecalUniforms DecalUniforms;
