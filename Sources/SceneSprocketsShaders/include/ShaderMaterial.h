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
};
typedef struct ShaderMaterialTransforms ShaderMaterialTransforms;
