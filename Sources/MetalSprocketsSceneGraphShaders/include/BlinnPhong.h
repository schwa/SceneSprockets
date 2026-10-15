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
};
typedef struct BlinnPhongLight BlinnPhongLight;

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
};
typedef struct BlinnPhongMaterialUniforms BlinnPhongMaterialUniforms;
