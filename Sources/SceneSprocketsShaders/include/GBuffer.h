#pragma once

#import <simd/simd.h>

// Per draw, for the G-buffer pre-pass (#510).
struct GBufferDrawUniforms {
    // Camera-relative model to clip space, this frame and last frame.
    simd_float4x4 modelViewProjection;
    simd_float4x4 previousModelViewProjection;
    // Model to view space for normals (inverse transpose of model-view, rotation part).
    simd_float3x3 viewNormalMatrix;
    // 0 when the mesh has no normals: the face normal is used instead.
    int hasNormals;
};
typedef struct GBufferDrawUniforms GBufferDrawUniforms;
