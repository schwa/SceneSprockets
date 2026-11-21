#include <metal_stdlib>

using namespace metal;

namespace AutoExposure {

    constant uint kGridSize = 32;

    // Meters the drawn frame for automatic exposure (#508): the mean log2 luminance of a 32 x 32 grid of samples,
    // skipping background pixels (depth at the reversed-depth clear value, 0). One threadgroup of 1024 threads.
    // Writes (mean log2 luminance, sample count) to `result`.
    [[kernel]] void meter(
        uint index [[thread_index_in_threadgroup]],
        texture2d<float, access::read> color [[texture(0)]],
        depth2d<float, access::read> sceneDepth [[texture(1)]],
        device float2 *result [[buffer(0)]]
    ) {
        threadgroup float sums[kGridSize * kGridSize];
        threadgroup float counts[kGridSize * kGridSize];
        const uint2 cell = uint2(index % kGridSize, index / kGridSize);
        const uint2 size = uint2(color.get_width(), color.get_height());
        const uint2 pixel = min(uint2((float2(cell) + 0.5) / float(kGridSize) * float2(size)), size - 1);
        const uint2 depthSize = uint2(sceneDepth.get_width(), sceneDepth.get_height());
        const float depth = sceneDepth.read(min(uint2(float2(pixel) * float2(depthSize) / float2(size)), depthSize - 1));
        const float3 rgb = color.read(pixel).rgb;
        const float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        const bool counts_sample = depth != 0.0;
        sums[index] = counts_sample ? log2(max(luminance, 1e-4)) : 0.0;
        counts[index] = counts_sample ? 1.0 : 0.0;
        threadgroup_barrier(mem_flags::mem_threadgroup);
        for (uint stride = kGridSize * kGridSize / 2; stride > 0; stride /= 2) {
            if (index < stride) {
                sums[index] += sums[index + stride];
                counts[index] += counts[index + stride];
            }
            threadgroup_barrier(mem_flags::mem_threadgroup);
        }
        if (index == 0) {
            result[0] = float2(counts[0] > 0 ? sums[0] / counts[0] : 0.0, counts[0]);
        }
    }

}
