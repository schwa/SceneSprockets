#include <metal_stdlib>
#include "SceneSprocketShaders.h"

using namespace metal;

// Sample ShaderMaterial shaders, and a starting point for custom ones. Meshes made by SwiftMesh put position at
// attribute 0 and normal at attribute 1.
namespace ShaderMaterialSamples {

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldNormal;
        float3 worldPosition;
    };

    [[vertex]] VertexOut vertex_main(VertexIn in [[stage_in]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        VertexOut out;
        out.position = transforms.modelViewProjectionMatrix * float4(in.position, 1);
        out.worldNormal = (transforms.normalMatrix * float4(in.normal, 0)).xyz;
        out.worldPosition = (transforms.modelMatrix * float4(in.position, 1)).xyz;
        return out;
    }

    // World-space normal as color.
    [[fragment]] float4 fragment_normals(VertexOut in [[stage_in]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        return float4(normalize(in.worldNormal) * 0.5 + 0.5, transforms.opacity);
    }

    // `color`, darkened where the surface turns away from the camera; uses no lights.
    [[fragment]] float4 fragment_rim(VertexOut in [[stage_in]], constant float4 &color [[buffer(0)]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        float3 toCamera = normalize(transforms.cameraPosition - in.worldPosition);
        float facing = saturate(dot(normalize(in.worldNormal), toCamera));
        return float4(color.rgb * (0.25 + 0.75 * facing), color.a * transforms.opacity);
    }

}
