#pragma once

#import <simd/simd.h>

#define BLINN_PHONG_LIGHT_DIRECTIONAL 0
#define BLINN_PHONG_LIGHT_POINT 1
#define BLINN_PHONG_LIGHT_SPOT 2

// One light, in world space.
struct BlinnPhongLight {
    simd_float3 position;
    // The way the light points (travels). Used by directional and spot lights.
    simd_float3 direction;
    // Linear RGB times intensity.
    simd_float3 color;
    int type;
    float range;
    // Cosines of the spot cone half-angles.
    float innerConeCos;
    float outerConeCos;
    // This light's shadow map slices; count 0 casts no shadow.
    int shadowSliceStart;
    int shadowSliceCount;
};
typedef struct BlinnPhongLight BlinnPhongLight;

// The shadow map, for lights with shadow slices.
struct BlinnPhongShadowUniforms {
    // World to light clip space, one per slice.
    simd_float4x4 sliceViewProjections[8];
    float mapSize;
    // 0 leaves shadowed light unchanged, 1 scales it fully by `color`.
    float intensity;
    simd_float3 color;
    // PCF half-size in texels.
    int radius;
};
typedef struct BlinnPhongShadowUniforms BlinnPhongShadowUniforms;

// Per-draw lighting state, shared by every mesh in a batch.
struct BlinnPhongFrame {
    simd_float4x4 viewProjection;
    simd_float3 cameraPosition;
    simd_float3 ambientLightColor;
    int lightCount;
};
typedef struct BlinnPhongFrame BlinnPhongFrame;

// One material. Colors multiply their textures when the matching flag is set.
struct BlinnPhongMaterialUniforms {
    simd_float3 ambient;
    simd_float3 diffuse;
    simd_float3 specular;
    float shininess;
    int hasAmbientTexture;
    int hasDiffuseTexture;
    int hasSpecularTexture;
    // 0 ignores shadows for this mesh.
    int receivesShadow;
    // Output alpha; multiplied by the diffuse texture's alpha when usesDiffuseAlpha is set.
    float opacity;
    int usesDiffuseAlpha;
    // Added unlit; multiplies the emission texture when hasEmissionTexture is set.
    simd_float3 emission;
    int hasEmissionTexture;
    // Tangent-space normal map (+Y up, OpenGL/glTF convention); the tangent frame comes from screen derivatives.
    int hasNormalMap;
};
typedef struct BlinnPhongMaterialUniforms BlinnPhongMaterialUniforms;
