#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

namespace PostProcessing {

    // Exposure, contrast around mid grey, saturation, then a vignette. Applies to every pixel, background included.
    [[kernel]] void color_adjust(
        uint2 tid [[thread_position_in_grid]],
        texture2d<float, access::read_write> outputTexture [[texture(0)]],
        constant ColorAdjustUniforms &uniforms [[buffer(0)]]
    ) {
        uint2 size = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= size.x || tid.y >= size.y) {
            return;
        }
        float4 color = outputTexture.read(tid);
        float3 rgb = color.rgb * uniforms.exposureScale;
        rgb = (rgb - 0.5) * uniforms.contrast + 0.5;
        float luminance = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        rgb = mix(float3(luminance), rgb, uniforms.saturation);
        if (uniforms.vignetteIntensity > 0) {
            float2 centered = ((float2(tid) + 0.5) / float2(size)) * 2.0 - 1.0;
            // 0 at the center, 1 at the corners.
            float distance = length(centered) / sqrt(2.0);
            float falloff = smoothstep(uniforms.vignetteRadius, 1.0, distance);
            rgb *= 1.0 - uniforms.vignetteIntensity * falloff;
        }
        color.rgb = max(rgb, 0.0);
        outputTexture.write(color, tid);
    }

    static float3 worldPosition(uint2 pixel, float depth, uint2 size, float4x4 inverseViewProjection) {
        float2 ndc = (float2(pixel) + 0.5) / float2(size) * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float4 world = inverseViewProjection * float4(ndc, depth, 1.0);
        return world.xyz / world.w;
    }

    // Depth at an output pixel; the depth texture may be a different size.
    static float depthAt(depth2d<float, access::read> sceneDepth, uint2 pixel, uint2 size) {
        uint2 depthSize = uint2(sceneDepth.get_width(), sceneDepth.get_height());
        return sceneDepth.read(min(uint2(float2(pixel) * float2(depthSize) / float2(size)), depthSize - 1));
    }

    static float hash(uint2 pixel, uint index) {
        uint value = pixel.x * 1973u + pixel.y * 9277u + index * 26699u;
        value = (value << 13u) ^ value;
        value = value * (value * value * 15731u + 789221u) + 1376312589u;
        return float(value & 0x00FFFFFFu) / float(0x01000000u);
    }

    // Darkens geometry by how much of the hemisphere above it is blocked by nearby geometry. Normals come from
    // depth; background pixels are left alone.
    [[kernel]] void ambient_occlusion(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float, access::read_write> outputTexture [[texture(1)]],
        constant AmbientOcclusionUniforms &uniforms [[buffer(0)]]
    ) {
        uint2 size = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= size.x || tid.y >= size.y) {
            return;
        }
        float depth = depthAt(sceneDepth, tid, size);
        if (depth == 0.0) {
            return;
        }
        float3 position = worldPosition(tid, depth, size, uniforms.inverseViewProjection);
        // Normal from the neighbors with the smaller depth jump on each axis, so edges do not smear.
        uint2 left = uint2(max(int(tid.x) - 1, 0), tid.y);
        uint2 right = uint2(min(tid.x + 1, size.x - 1), tid.y);
        uint2 down = uint2(tid.x, max(int(tid.y) - 1, 0));
        uint2 up = uint2(tid.x, min(tid.y + 1, size.y - 1));
        float3 leftPosition = worldPosition(left, depthAt(sceneDepth, left, size), size, uniforms.inverseViewProjection);
        float3 rightPosition = worldPosition(right, depthAt(sceneDepth, right, size), size, uniforms.inverseViewProjection);
        float3 downPosition = worldPosition(down, depthAt(sceneDepth, down, size), size, uniforms.inverseViewProjection);
        float3 upPosition = worldPosition(up, depthAt(sceneDepth, up, size), size, uniforms.inverseViewProjection);
        float3 dx = length(rightPosition - position) < length(position - leftPosition) ? rightPosition - position : position - leftPosition;
        float3 dy = length(upPosition - position) < length(position - downPosition) ? upPosition - position : position - downPosition;
        float3 normal = normalize(cross(dx, dy));
        if (dot(normal, uniforms.cameraPosition - position) < 0) {
            normal = -normal;
        }
        float3 helper = abs(normal.y) < 0.99 ? float3(0, 1, 0) : float3(1, 0, 0);
        float3 tangent = normalize(cross(normal, helper));
        float3 bitangent = cross(normal, tangent);

        int count = max(uniforms.sampleCount, 1);
        float occluded = 0;
        for (int index = 0; index < count; index++) {
            // A random point in the hemisphere, denser near the center.
            float angle = hash(tid, uint(index) * 3u) * 2.0 * M_PI_F;
            float elevation = sqrt(hash(tid, uint(index) * 3u + 1u));
            float scale = mix(0.1, 1.0, hash(tid, uint(index) * 3u + 2u));
            float horizontal = sqrt(max(1.0 - elevation * elevation, 0.0));
            float3 direction = tangent * cos(angle) * horizontal + bitangent * sin(angle) * horizontal + normal * elevation;
            float3 sample = position + direction * uniforms.radius * scale * scale;
            float4 clip = uniforms.viewProjection * float4(sample, 1.0);
            float2 uv = float2(clip.x / clip.w * 0.5 + 0.5, 0.5 - clip.y / clip.w * 0.5);
            if (any(uv < 0.0) || any(uv > 1.0)) {
                continue;
            }
            uint2 pixel = uint2(uv * float2(size));
            float sceneSampleDepth = depthAt(sceneDepth, pixel, size);
            if (sceneSampleDepth == 0.0) {
                continue;
            }
            float3 scenePosition = worldPosition(pixel, sceneSampleDepth, size, uniforms.inverseViewProjection);
            float sampleDistance = length(sample - uniforms.cameraPosition);
            float sceneDistance = length(scenePosition - uniforms.cameraPosition);
            // Blocked when the visible surface is in front of the sample, and close enough to matter.
            float rangeCheck = smoothstep(0.0, 1.0, uniforms.radius / max(length(scenePosition - position), 1e-4));
            occluded += (sceneDistance < sampleDistance - uniforms.radius * 0.02 ? 1.0 : 0.0) * rangeCheck;
        }
        float visibility = 1.0 - uniforms.intensity * (occluded / float(count));
        float4 color = outputTexture.read(tid);
        color.rgb *= saturate(visibility);
        outputTexture.write(color, tid);
    }

}
