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
    // 0 leaves visibility at 1, 1 makes fully occluded pixels 0.
    float intensity;
    int sampleCount;
};
typedef struct AmbientOcclusionUniforms AmbientOcclusionUniforms;

// Bloom and tone mapping of the HDR scene (#640).
struct BloomUniforms {
    // Multiplies the linear scene before the threshold and tone mapping.
    float exposure;
    float threshold;
    float intensity;
    // LightingShaderToneMapping.
    int toneMapping;
};
typedef struct BloomUniforms BloomUniforms;

// Screen-space contact shadows (#495). Positions are camera-relative (camera at the origin).
struct ContactShadowUniforms {
    simd_float4x4 inverseViewProjection;
    simd_float4x4 viewProjection;
    // Unit vector from a surface toward the light.
    simd_float3 toLight;
    float length;
    float thickness;
    float strength;
    int stepCount;
    // Whether texture(2) holds ambient occlusion to copy into the red channel; otherwise red is 1.
    int hasAmbientOcclusion;
};
typedef struct ContactShadowUniforms ContactShadowUniforms;
