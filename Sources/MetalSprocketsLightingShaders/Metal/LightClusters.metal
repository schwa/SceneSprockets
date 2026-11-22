#include <metal_stdlib>
#include "MetalSprocketsLightingTypes.h"

using namespace metal;

// Clustered light assignment (#519). One thread per cluster: bound the cluster in view space from its tile's corner
// rays and its depth slice, then list every light whose sphere of influence touches it.
namespace LightClusters {
    // View distance where `slice` starts; the last slice runs on to `far`.
    inline float sliceStart(constant LightingClusterUniforms &uniforms, uint slice) {
        if (slice == 0) {
            return 0.0;
        }
        return uniforms.sliceNear * pow(uniforms.sliceFar / uniforms.sliceNear, float(slice) / float(uniforms.gridSize.z));
    }

    [[kernel]] void assign_lights(
        constant LightingClusterUniforms &uniforms [[buffer(0)]],
        constant LightingLight *lights [[buffer(1)]],
        // (gridSize.x + 1) * (gridSize.y + 1) rays through the tile corners, origin then direction, in view space. A
        // ray's origin has z 0 and its direction z -1, so `origin + direction * d` is at view distance d.
        constant float4 *cornerRays [[buffer(2)]],
        device uint *clusterLights [[buffer(3)]],
        uint3 cluster [[thread_position_in_grid]]
    ) {
        const uint3 size = uniforms.gridSize;
        if (any(cluster >= size)) {
            return;
        }
        const float near = sliceStart(uniforms, cluster.z);
        const float far = cluster.z + 1 == size.z ? 1e9 : sliceStart(uniforms, cluster.z + 1);
        float3 boxMin = float3(INFINITY);
        float3 boxMax = float3(-INFINITY);
        for (uint corner = 0; corner < 4; corner++) {
            const uint x = cluster.x + (corner & 1);
            const uint y = cluster.y + (corner >> 1);
            const uint ray = (y * (size.x + 1) + x) * 2;
            const float3 origin = cornerRays[ray].xyz;
            const float3 direction = cornerRays[ray + 1].xyz;
            const float distances[2] = { near, far };
            for (uint end = 0; end < 2; end++) {
                const float3 point = origin + direction * distances[end];
                boxMin = min(boxMin, point);
                boxMax = max(boxMax, point);
            }
        }
        device uint *list = clusterLights + ((cluster.z * size.y + cluster.y) * size.x + cluster.x) * kLightingClusterStride;
        uint count = 0;
        for (int index = 0; index < uniforms.lightCount && count < kLightingClusterMaxLights; index++) {
            const LightingLight light = lights[index];
            // Directional lights and lights without a range reach everywhere.
            if (light.type != kLightingLightTypeDirectional && light.range > 0.0) {
                const float3 center = (uniforms.view * float4(light.position, 1)).xyz;
                const float3 nearest = clamp(center, boxMin, boxMax);
                const float3 offset = center - nearest;
                if (dot(offset, offset) > light.range * light.range) {
                    continue;
                }
            }
            list[1 + count] = uint(index);
            count++;
        }
        list[0] = count;
    }
}
