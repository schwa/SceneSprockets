#pragma once

#import <simd/simd.h>
// Lights (LightingLight) and shadows (LightingShadowUniforms). Positions are camera-relative (world minus camera
// position), like everything the shader sees (#253).
#import "MetalSprocketsLightingTypes.h"

// Per-draw lighting state, shared by every mesh in a batch.
// Views drawn at once: 1, or 2 for stereo, where vertex amplification draws each primitive once per view and
// [[amplification_id]] picks the view's entry in the per-view arrays.
#define kBlinnPhongMaxViewCount 2

struct BlinnPhongFrame {
    // Per view: projection times the view, relative to the render origin; model matrices are relative to it too.
    simd_float4x4 viewProjections[kBlinnPhongMaxViewCount];
    // Per view: the eye relative to the render origin (zero for a single view).
    simd_float3 cameraPositions[kBlinnPhongMaxViewCount];
    simd_float3 ambientLightColor;
    int lightCount;
    // MaterialChannel's raw value, or 0 for lit output.
    int materialChannel;
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
    // The constant normal, or the tint that multiplies the decoded normal texture when hasNormalTexture is set.
    simd_float3 normal;
    int hasNormalTexture;
};
typedef struct BlinnPhongMaterialUniforms BlinnPhongMaterialUniforms;
