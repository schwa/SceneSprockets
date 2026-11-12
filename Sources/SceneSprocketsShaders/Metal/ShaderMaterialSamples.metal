#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

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
        // World position minus the camera position; precise far from the origin (#251).
        float3 cameraRelativePosition;
        // The view (amplification ID) this is drawn for.
        uint view [[flat]];
    };

    [[vertex]] VertexOut vertex_main(VertexIn in [[stage_in]], ushort view [[amplification_id]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        VertexOut out;
        out.position = transforms.modelViewProjectionMatrices[view] * float4(in.position, 1);
        out.view = view;
        out.worldNormal = (transforms.normalMatrix * float4(in.normal, 0)).xyz;
        out.cameraRelativePosition = (transforms.cameraRelativeModelMatrix * float4(in.position, 1)).xyz;
        return out;
    }

    // World-space normal as color.
    [[fragment]] float4 fragment_normals(VertexOut in [[stage_in]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        return float4(normalize(in.worldNormal) * 0.5 + 0.5, transforms.opacity);
    }

    // `color`, darkened where the surface turns away from the camera; uses no lights.
    [[fragment]] float4 fragment_rim(VertexOut in [[stage_in]], constant float4 &color [[buffer(0)]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        float3 toCamera = normalize(transforms.cameraRelativeEyePositions[in.view] - in.cameraRelativePosition);
        float facing = saturate(dot(normalize(in.worldNormal), toCamera));
        return float4(color.rgb * (0.25 + 0.75 * facing), color.a * transforms.opacity);
    }

    // Lambert diffuse `color` from the scene's lights, each dimmed only by its own shadow. Needs `samplesShadows`.
    [[fragment]] float4 fragment_lit(
        VertexOut in [[stage_in]],
        constant float4 &color [[buffer(0)]],
        constant ShaderMaterialTransforms &transforms [[buffer(10)]],
        constant ShaderMaterialLighting &lighting [[buffer(11)]],
        constant ShaderMaterialLight *lights [[buffer(12)]],
        depth2d_array<float, access::sample> shadowMap [[texture(0)]],
        sampler shadowSampler [[sampler(0)]]
    ) {
        float3 normal = normalize(in.worldNormal);
        float3 diffuse = 0;
        for (int index = 0; index < lighting.lightCount; index++) {
            float3 toLight;
            float3 incoming = shaderMaterialIncomingLight(lights[index], in.cameraRelativePosition, toLight);
            float lambertian = max(dot(toLight, normal), 0.0);
            if (lambertian > 0) {
                diffuse += color.rgb * lambertian * incoming * shaderMaterialShadow(lighting, lights[index], in.cameraRelativePosition, shadowMap, shadowSampler);
            }
        }
        return float4(diffuse, color.a * transforms.opacity);
    }

}
