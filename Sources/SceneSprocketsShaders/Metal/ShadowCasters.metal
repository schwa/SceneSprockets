#include <metal_stdlib>

using namespace metal;

// Depth-only drawing of shadow casters from a light, for Shadows.
namespace ShadowCasters {

    struct StaticIn {
        float3 position [[attribute(0)]];
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

    [[fragment]] void fragment_depth() {
    }

    // See-through casters (#541): the same vertices plus texture coordinates in buffer 5.
    struct StaticAlphaIn {
        float3 position [[attribute(0)]];
        float2 texCoord [[attribute(3)]];
    };

    struct AlphaOut {
        float4 position [[position]];
        float2 texCoord;
    };

    [[vertex]] AlphaOut vertex_static_alpha(
        StaticAlphaIn in [[stage_in]],
        constant float4x4 &lightViewProjection [[buffer(2)]],
        constant float4x4 &modelMatrix [[buffer(3)]]
    ) {
        return { lightViewProjection * modelMatrix * float4(in.position, 1), in.texCoord };
    }

    // alpha.x: opacity, alpha.y: cutoff. Texture coordinates go through `uvTransform` (KHR_texture_transform).
    [[fragment]] void fragment_alpha(
        AlphaOut in [[stage_in]],
        constant float4 &alpha [[buffer(0)]],
        constant float3x3 &uvTransform [[buffer(1)]],
        texture2d<float> alphaTexture [[texture(0)]],
        sampler alphaSampler [[sampler(0)]]
    ) {
        const float2 uv = (uvTransform * float3(in.texCoord, 1)).xy;
        if (alpha.x * alphaTexture.sample(alphaSampler, uv).a < alpha.y) {
            discard_fragment();
        }
    }

    // Marks pixels in the receiver mask.
    [[fragment]] float4 fragment_mark() {
        return 1;
    }

}
