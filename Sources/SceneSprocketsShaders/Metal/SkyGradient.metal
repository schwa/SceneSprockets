#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

// A full-screen sky behind the scene, colored by view elevation (#247).
namespace SkyGradient {

    struct VertexOut {
        float4 position [[position]];
        float2 ndc;
        uint view [[flat]];
    };

    // One triangle that covers the screen.
    [[vertex]] VertexOut vertex_main(uint vertexID [[vertex_id]], ushort view [[amplification_id]]) {
        float2 ndc = float2(float((vertexID << 1) & 2), float(vertexID & 2)) * 2.0 - 1.0;
        VertexOut out;
        out.position = float4(ndc, 0, 1);
        out.ndc = ndc;
        out.view = view;
        return out;
    }

    [[fragment]] float4 fragment_main(VertexOut in [[stage_in]], constant SkyGradientUniforms &uniforms [[buffer(0)]]) {
        // Any depth works: the rotation-only view puts every point on the ray from the camera.
        float4 world = uniforms.inverseViewProjections[in.view] * float4(in.ndc, 0.5, 1);
        float3 direction = normalize(world.xyz / world.w);
        float elevation = direction.y;
        float amount = pow(saturate(abs(elevation)), max(uniforms.exponent, 1e-3));
        float3 color = mix(uniforms.horizon, elevation >= 0 ? uniforms.zenith : uniforms.ground, amount);
        return float4(color, 1);
    }

}
