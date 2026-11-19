#pragma once

// Metal-only sampling and GGX helpers, used by the environment prefiltering kernels and by renderers' BRDFs.

#ifdef __METAL_VERSION__
#include <metal_stdlib>

namespace Lighting {
    using namespace metal;

    constant float kPi = 3.14159265358979323846;

    inline float distributionGGX(float NdotH, float alpha) {
        const float alpha2 = alpha * alpha;
        const float f = NdotH * NdotH * (alpha2 - 1.0) + 1.0;
        return alpha2 / (kPi * f * f);
    }

    // Height-correlated Smith visibility. Includes the 1 / (4 NdotL NdotV) term.
    inline float visibilitySmithGGXCorrelated(float NdotL, float NdotV, float alpha) {
        const float alpha2 = alpha * alpha;
        const float ggxV = NdotL * sqrt(NdotV * NdotV * (1.0 - alpha2) + alpha2);
        const float ggxL = NdotV * sqrt(NdotL * NdotL * (1.0 - alpha2) + alpha2);
        const float sum = ggxV + ggxL;
        return sum > 0.0 ? 0.5 / sum : 0.0;
    }

    // A world direction in the environment's frame. An all-zero matrix (uniforms never set) leaves it unrotated.
    inline float3 environmentDirection(float3 direction, float3x3 rotation) {
        return all(rotation[0] == 0.0) ? direction : rotation * direction;
    }

    inline float2 hammersley(uint index, uint count) {
        return float2(float(index) / float(count), float(reverse_bits(index)) * 2.3283064365386963e-10);
    }

    inline float3x3 tangentFrame(float3 normal) {
        const float3 up = abs(normal.z) < 0.999 ? float3(0, 0, 1) : float3(1, 0, 0);
        const float3 tangent = normalize(cross(up, normal));
        return float3x3(tangent, cross(normal, tangent), normal);
    }

    inline float3 importanceSampleGGX(float2 xi, float3 normal, float alpha) {
        const float phi = 2.0 * kPi * xi.x;
        const float cosTheta = sqrt((1.0 - xi.y) / (1.0 + (alpha * alpha - 1.0) * xi.y));
        const float sinTheta = sqrt(1.0 - cosTheta * cosTheta);
        return normalize(tangentFrame(normal) * float3(sinTheta * cos(phi), sinTheta * sin(phi), cosTheta));
    }

    // Equirectangular mapping, row 0 at +Y. Same longitude convention as three.js (which stores row 0 at -Y).
    inline float2 equirectUV(float3 direction) {
        const float3 d = normalize(direction);
        return float2(atan2(d.z, d.x) / (2.0 * kPi) + 0.5, 0.5 - asin(clamp(d.y, -1.0, 1.0)) / kPi);
    }

    inline float3 equirectDirection(float2 uv) {
        const float phi = (uv.x - 0.5) * 2.0 * kPi;
        const float theta = (0.5 - uv.y) * kPi;
        return float3(cos(theta) * cos(phi), sin(theta), cos(theta) * sin(phi));
    }

    // Direction through a cube texel; `uv` is 0...1 with v down, faces in Metal order +X -X +Y -Y +Z -Z.
    inline float3 cubeDirection(uint face, float2 uv) {
        const float2 p = uv * 2.0 - 1.0;
        switch (face) {
            case 0: return normalize(float3(1, -p.y, -p.x));
            case 1: return normalize(float3(-1, -p.y, p.x));
            case 2: return normalize(float3(p.x, 1, p.y));
            case 3: return normalize(float3(p.x, -1, -p.y));
            case 4: return normalize(float3(p.x, -p.y, 1));
            default: return normalize(float3(-p.x, -p.y, -1));
        }
    }
} // namespace Lighting

#endif
