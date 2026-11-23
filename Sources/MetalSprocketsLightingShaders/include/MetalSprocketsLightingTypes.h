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

// The most shadow map slices any renderer reads; Shadows.maximumSliceCount picks how many are used (#299).
#define kLightingMaxShadowSliceCount 32

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
    // SceneKit-style falloff, used when attenuationFalloffExponent > 0: full intensity up to
    // attenuationStartDistance, none from `range` on, with this exponent between. 0 keeps inverse-square falloff.
    float attenuationStartDistance;
    float attenuationFalloffExponent;
};
typedef struct LightingLight LightingLight;

// Clustered light assignment (#519): the view frustum is cut into a grid of clusters (screen tiles times view-depth
// slices), and a compute pass lists the lights that reach each one. Shaders then loop over their fragment's cluster
// instead of every light. The list buffer holds, per cluster, a count followed by kLightingClusterMaxLights light
// indices. When more lights reach a cluster, the count is larger than kLightingClusterMaxLights and shaders loop over
// every light for it instead (#628).
#define kLightingClusterMaxLights 63
#define kLightingClusterStride (kLightingClusterMaxLights + 1)

struct LightingClusterUniforms {
    // Camera-relative position (camera at the origin) to clip space, and to view space (rotation only).
    simd_float4x4 viewProjection;
    simd_float4x4 view;
    // Added to a shading-space position to make it camera-relative: shading origin minus camera position.
    simd_float3 originOffset;
    // Tiles across and down, and depth slices.
    simd_uint3 gridSize;
    // Depth slices are exponential in view distance from sliceNear to sliceFar; nearer is slice 0, farther the last.
    float sliceNear;
    float sliceFar;
    // 0 means no clusters: shaders loop over every light.
    int enabled;
    int lightCount;
};
typedef struct LightingClusterUniforms LightingClusterUniforms;

// The shadow map shared by every light with shadow slices.
struct LightingShadowUniforms {
    // Shading space to light clip space, one per slice. Depth is compared in 0...1 with the shadow sampler's compare
    // function.
    simd_float4x4 sliceViewProjections[kLightingMaxShadowSliceCount];
    // Cascaded slices (#88): x is the distance from the camera (the shading-space origin) the slice covers, y where
    // blending into the light's next slice starts. x is 0 for slices that are not cascades; a light whose first slice
    // is a cascade uses one of its slices per point instead of multiplying them all. z is the fraction of the slice's
    // width and height the light draws into, from the top left (0 means all of it).
    simd_float4 sliceCascades[kLightingMaxShadowSliceCount];
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
