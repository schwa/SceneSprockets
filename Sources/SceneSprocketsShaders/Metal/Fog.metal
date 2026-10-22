#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

namespace Fog {

    // Blends fog into already-rendered geometry, by camera distance rebuilt from depth. Background pixels (depth at
    // the reversed-depth clear value, 0) are left alone.
    [[kernel]] void fog_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float, access::read_write> outputTexture [[texture(1)]],
        constant FogUniforms &uniforms [[buffer(0)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y) {
            return;
        }
        uint2 depthSize = uint2(sceneDepth.get_width(), sceneDepth.get_height());
        uint2 depthCoord = uint2(float2(tid) * float2(depthSize) / float2(outputSize));
        float depth = sceneDepth.read(depthCoord);
        if (depth == 0.0) {
            return;
        }
        float2 ndc = (float2(tid) + 0.5) / float2(outputSize) * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float4 world = uniforms.inverseViewProjection * float4(ndc, depth, 1.0);
        world /= world.w;
        float distance = length(world.xyz - uniforms.cameraPosition);
        float span = max(uniforms.endDistance - uniforms.startDistance, 1e-6);
        float amount = pow(saturate((distance - uniforms.startDistance) / span), max(uniforms.densityExponent, 1e-6)) * uniforms.color.w;
        if (amount <= 0.0) {
            return;
        }
        float4 color = outputTexture.read(tid);
        color.rgb = mix(color.rgb, uniforms.color.rgb, amount);
        outputTexture.write(color, tid);
    }

}
