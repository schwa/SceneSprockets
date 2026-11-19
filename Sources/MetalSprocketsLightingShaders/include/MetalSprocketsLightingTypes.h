#pragma once

#include <simd/simd.h>

// Shared by Swift and Metal. Plain C, with no other headers, so any package's shaders can include it.

// Imported into Swift as an enum (the CF_ENUM pattern).
typedef enum __attribute__((enum_extensibility(open))) LightingLightType : int LightingLightType;
enum LightingLightType : int {
    kLightingLightTypeDirectional = 0,
    kLightingLightTypePoint = 1,
    kLightingLightTypeSpot = 2,
};

#define kLightingMaxShadowSliceCount 8

// A punctual light (KHR_lights_punctual), in the space the shader shades in.
struct LightingLight {
    simd_float3 position;
    // The way the light travels. Used by directional and spot lights.
    simd_float3 direction;
    // Linear RGB.
    simd_float3 color;
    float intensity;
    // 0 means infinite.
    float range;
    // Cosines of the spot cone half-angles.
    float innerConeCos;
    float outerConeCos;
    LightingLightType type;
    // This light's slices in the shadow map; count 0 casts no shadow.
    int shadowSliceStart;
    int shadowSliceCount;
};
typedef struct LightingLight LightingLight;

// The shadow map shared by every light with shadow slices.
struct LightingShadowUniforms {
    // Shading space to light clip space, one per slice. Depth is compared in 0...1 with the shadow sampler's compare
    // function.
    simd_float4x4 sliceViewProjections[kLightingMaxShadowSliceCount];
    float mapSize;
    // PCF half-size in texels.
    int radius;
    int enabled;
    // 0 leaves shadowed light unchanged, 1 scales it fully by `color`.
    float intensity;
    simd_float3 color;
};
typedef struct LightingShadowUniforms LightingShadowUniforms;

// How linear radiance, after exposure, becomes display values. Mirrored by the Swift LightingToneMapping.
typedef enum __attribute__((enum_extensibility(open))) LightingShaderToneMapping : int LightingShaderToneMapping;
enum LightingShaderToneMapping : int {
    // Khronos PBR Neutral. The default.
    kLightingToneMappingPBRNeutral = 0,
    // Clamp to 0...1 (three.js LinearToneMapping).
    kLightingToneMappingLinear,
    kLightingToneMappingACESFilmic,
    kLightingToneMappingAgX,
    kLightingToneMappingReinhard,
    // Unbounded linear output for HDR targets (three.js NoToneMapping).
    kLightingToneMappingNone,
    kLightingToneMappingCount
};

#ifdef __METAL_VERSION__
#include <metal_stdlib>

// A frame's lighting textures and samplers in one argument buffer, the same for every draw of the frame. Renderers
// bind it as `frameResources`.
struct LightingFrameResources {
    metal::texturecube<float> environmentIrradiance;
    metal::texturecube<float> environmentSpecular;
    metal::texture2d<float> brdfLookup;
    // The opaque scene behind transmissive surfaces, for refraction; a placeholder when there is none.
    metal::texture2d_array<float> transmissionScene;
    metal::depth2d_array<float> shadowMap;
    // Screen-space ambient occlusion, one texel per render target pixel.
    metal::texture2d<float> ambientOcclusion;
    metal::sampler environmentSampler;
    metal::sampler shadowSampler;
};
#endif

// One pass of environment prefiltering.
struct LightingPrefilterParameters {
    float roughness;
    unsigned int sampleCount;
};
typedef struct LightingPrefilterParameters LightingPrefilterParameters;
