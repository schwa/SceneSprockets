#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

// ShaderMaterial shaders for SceneSprocketsAddOns' PointCloud: round, colored points of a fixed size in points.
namespace PointCloud {

    struct VertexIn {
        float3 position [[attribute(0)]];
        float4 color [[attribute(1)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float pointSize [[point_size]];
        float4 color;
    };

    // Vertex buffers use the low slots, so the parameter goes above them.
    [[vertex]] VertexOut vertex_points(VertexIn in [[stage_in]], constant float &pointSize [[buffer(11)]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        VertexOut out;
        out.position = transforms.modelViewProjectionMatrix * float4(in.position, 1);
        out.pointSize = pointSize;
        out.color = in.color;
        return out;
    }

    [[fragment]] float4 fragment_points(VertexOut in [[stage_in]], float2 pointCoordinate [[point_coord]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        if (length_squared(pointCoordinate - 0.5) > 0.25) {
            discard_fragment();
        }
        return float4(in.color.rgb, in.color.a * transforms.opacity);
    }
}
