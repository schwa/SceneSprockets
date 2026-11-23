#include <metal_stdlib>
#include "Decal.h"

using namespace metal;

// Projected decals (#397): draws the back faces of the projector box, rebuilds each pixel's surface position from the
// scene depth, and blends the decal texture onto surfaces inside the box.
namespace Decal {

    struct Out {
        float4 position [[position]];
    };

    // A unit cube from vertex_id: 12 triangles, counter-clockwise seen from outside.
    [[vertex]] Out vertex_main(uint vertexID [[vertex_id]], constant DecalUniforms &uniforms [[buffer(0)]]) {
        const ushort indices[36] = {
            0, 2, 1, 1, 2, 3, // -z
            4, 5, 6, 5, 7, 6, // +z
            0, 1, 4, 1, 5, 4, // -y
            2, 6, 3, 3, 6, 7, // +y
            0, 4, 2, 2, 4, 6, // -x
            1, 3, 5, 3, 7, 5, // +x
        };
        const ushort corner = indices[vertexID];
        const float3 position = float3(corner & 1 ? 0.5 : -0.5, corner & 2 ? 0.5 : -0.5, corner & 4 ? 0.5 : -0.5);
        return { uniforms.modelViewProjection * float4(position, 1) };
    }

    [[fragment]] float4 fragment_main(
        Out in [[stage_in]],
        constant DecalUniforms &uniforms [[buffer(0)]],
        texture2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float> decalTexture [[texture(1)]],
        sampler decalSampler [[sampler(0)]]
    ) {
        const uint2 pixel = uint2(in.position.xy);
        const float depth = sceneDepth.read(pixel).r;
        // The background (the reversed-depth clear value) takes no decal.
        if (depth <= 0.0) {
            discard_fragment();
        }
        float2 ndc = in.position.xy / uniforms.viewSize * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float4 world = uniforms.inverseViewProjection * float4(ndc, depth, 1);
        world /= world.w;
        const float3 local = (uniforms.inverseModel * world).xyz;
        if (any(abs(local) > 0.5)) {
            discard_fragment();
        }
        // The surface normal from neighboring pixels' positions.
        const float3 normal = normalize(cross(dfdy(world.xyz), dfdx(world.xyz)));
        const float facing = dot(normal, uniforms.axis);
        const float fade = saturate((facing - uniforms.fadeEndCosine) / max(uniforms.fadeStartCosine - uniforms.fadeEndCosine, 1e-4));
        const float2 uv = float2(local.x + 0.5, 0.5 - local.y);
        float4 color = uniforms.color;
        if (uniforms.hasTexture != 0) {
            color *= decalTexture.sample(decalSampler, uv);
        }
        color.a *= fade;
        return color;
    }
}
