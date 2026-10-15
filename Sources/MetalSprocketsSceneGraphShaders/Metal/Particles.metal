#include <metal_stdlib>
#include "MetalSprocketsSceneGraphShaders.h"

using namespace metal;

namespace Particles {

    struct Out {
        float4 position [[position]];
        float2 offset;
        float4 color;
    };

    // Four vertices per instance, as a triangle strip.
    [[vertex]] Out vertex_main(
        uint vertexID [[vertex_id]],
        uint instanceID [[instance_id]],
        constant ParticleInstance *particles [[buffer(0)]],
        constant ParticleUniforms &uniforms [[buffer(1)]]
    ) {
        float2 corner = float2(vertexID & 1 ? 1.0 : -1.0, vertexID & 2 ? 1.0 : -1.0);
        ParticleInstance particle = particles[instanceID];
        float halfSize = particle.positionSize.w * 0.5;
        float3 world = particle.positionSize.xyz + (uniforms.right.xyz * corner.x + uniforms.up.xyz * corner.y) * halfSize;
        Out out;
        out.position = uniforms.viewProjection * float4(world, 1);
        out.offset = corner;
        out.color = particle.color;
        return out;
    }

    // A soft round sprite, premultiplied.
    [[fragment]] float4 fragment_main(Out in [[stage_in]]) {
        float falloff = saturate(1.0 - length(in.offset));
        float alpha = in.color.a * falloff * falloff;
        return float4(in.color.rgb * alpha, alpha);
    }

}
