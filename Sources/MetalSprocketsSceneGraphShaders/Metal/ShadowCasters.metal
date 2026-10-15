#include <metal_stdlib>

using namespace metal;

// Depth-only drawing of shadow casters from a light, for SceneGraphShadows.
namespace ShadowCasters {

    struct StaticIn {
        float3 position [[attribute(0)]];
    };

    struct SkinnedIn {
        float3 position [[attribute(0)]];
        float4 joints [[attribute(1)]];
        float4 weights [[attribute(2)]];
    };

    struct Out {
        float4 position [[position]];
    };

    [[vertex]] Out vertex_static(
        StaticIn in [[stage_in]],
        constant float4x4 &lightViewProjection [[buffer(2)]],
        constant float4x4 &modelMatrix [[buffer(3)]]
    ) {
        return { lightViewProjection * modelMatrix * float4(in.position, 1) };
    }

    // Rest positions moved by up to four joints; joint matrices are joint world * inverse bind.
    [[vertex]] Out vertex_skinned(
        SkinnedIn in [[stage_in]],
        constant float4x4 &lightViewProjection [[buffer(2)]],
        constant float4x4 *jointMatrices [[buffer(3)]]
    ) {
        float4 position = float4(in.position, 1);
        float4 skinned = 0;
        for (int index = 0; index < 4; index++) {
            skinned += in.weights[index] * (jointMatrices[uint(in.joints[index])] * position);
        }
        return { lightViewProjection * skinned };
    }

    [[fragment]] void fragment_depth() {
    }

    // Marks pixels in the receiver mask.
    [[fragment]] float4 fragment_mark() {
        return 1;
    }

}
