#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

// The G-buffer pre-pass (#510): view-space normals and screen-space velocity of the opaque meshes, drawn once more
// with one shader. Velocity is this frame's texture coordinate minus last frame's, so a pixel was at uv - velocity.
namespace GBufferPass {

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float4 current;
        float4 previous;
        float3 viewNormal;
    };

    struct FragmentOut {
        float4 normal [[color(0)]];
        float2 velocity [[color(1)]];
    };

    [[vertex]] VertexOut vertex_main(VertexIn in [[stage_in]], constant GBufferDrawUniforms &uniforms [[buffer(1)]]) {
        VertexOut out;
        out.current = uniforms.modelViewProjection * float4(in.position, 1);
        out.previous = uniforms.previousModelViewProjection * float4(in.position, 1);
        out.position = out.current;
        out.viewNormal = uniforms.viewNormalMatrix * in.normal;
        return out;
    }

    static float2 uv(float4 clip) {
        const float2 ndc = clip.xy / clip.w;
        return float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
    }

    [[fragment]] FragmentOut fragment_main(VertexOut in [[stage_in]], bool frontFacing [[front_facing]], constant GBufferDrawUniforms &uniforms [[buffer(1)]]) {
        float3 normal;
        if (uniforms.hasNormals != 0 && length_squared(in.viewNormal) > 1e-8) {
            normal = normalize(in.viewNormal);
            if (!frontFacing) {
                normal = -normal;
            }
        } else {
            // No normals: facing the camera.
            normal = float3(0, 0, 1);
        }
        return { float4(normal, 1), uv(in.current) - uv(in.previous) };
    }
}
