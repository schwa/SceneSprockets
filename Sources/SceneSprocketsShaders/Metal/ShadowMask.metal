#include <metal_stdlib>
#include "SceneSprocketsShaders.h"
#include "MetalSprocketsLighting.h"

using namespace metal;

namespace SceneShadowMask {

    // True when the receiver mask is bound; its nonzero pixels belong to meshes that do not receive shadows.
    constant bool HAS_RECEIVER_MASK [[function_constant(0)]];

    // Darkens shadowed pixels of already-drawn geometry. Shadow factors of all slices multiply.
    [[kernel]] void shadow_mask_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        depth2d_array<float, access::sample> shadowMap [[texture(1)]],
        texture2d<float, access::read_write> outputTexture [[texture(2)]],
        texture2d<float, access::read> receiverMask [[texture(3), function_constant(HAS_RECEIVER_MASK)]],
        sampler shadowSampler [[sampler(0)]],
        constant SceneShadowMaskUniforms &uniforms [[buffer(0)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y) {
            return;
        }
        if (HAS_RECEIVER_MASK && receiverMask.read(tid).r > 0.5) {
            return;
        }
        uint2 depthSize = uint2(sceneDepth.get_width(), sceneDepth.get_height());
        float depth = sceneDepth.read(uint2(float2(tid) * float2(depthSize) / float2(outputSize)));
        // Background: the reversed-depth clear value.
        if (depth == 0.0) {
            return;
        }
        float2 ndc = (float2(tid) + 0.5) / float2(outputSize) * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float4 world = uniforms.inverseViewProjection * float4(ndc, depth, 1);
        world /= world.w;
        float lit = 1;
        for (int slice = 0; slice < uniforms.sliceCount; slice++) {
            lit *= Lighting::sliceShadow(world.xyz, uniforms.sliceViewProjections[slice], uniforms.mapSize, uniforms.radius, shadowMap, shadowSampler, uint(slice));
        }
        if (lit >= 1.0) {
            return;
        }
        float4 color = outputTexture.read(tid);
        color.rgb = mix(color.rgb, color.rgb * uniforms.color, uniforms.intensity * (1.0 - lit));
        outputTexture.write(color, tid);
    }

}
