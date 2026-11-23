#pragma once

#include "MetalSprocketsLightingTypes.h"

#ifdef __METAL_VERSION__
#include <metal_stdlib>
#include "MetalSprocketsLightingLTC.h"

namespace Lighting {
    using namespace metal;

    // Probe light (#532): irradiance over pi from L1 spherical harmonics, one float4 per color channel holding
    // (constant, y, z, x), as IrradianceSH stores them.
    inline float3 probeIrradiance(float4 red, float4 green, float4 blue, float3 normal) {
        const float4 basis = float4(1, normal.y, normal.z, normal.x);
        return max(float3(dot(red, basis), dot(green, basis), dot(blue, basis)), 0.0);
    }

    // Rectangular area lights with linearly transformed cosines (#509; Heitz et al. 2016).

    // A table entry, bilinearly filtered, at perceptual roughness and the view angle.
    template <typename T>
    inline T ltcLookup(constant T *table, float perceptualRoughness, float NdotV) {
        const float2 uv = float2(saturate(perceptualRoughness), saturate(acos(saturate(NdotV)) / (M_PI_F * 0.5))) * 63.0;
        const int2 base = int2(floor(uv));
        const int2 next = min(base + 1, int2(63));
        const float2 blend = uv - float2(base);
        const T top = mix(table[base.y * 64 + base.x], table[base.y * 64 + next.x], blend.x);
        const T bottom = mix(table[next.y * 64 + base.x], table[next.y * 64 + next.x], blend.x);
        return mix(top, bottom, blend.y);
    }

    // The vector form factor of one edge of a polygon on the unit sphere; its z is the edge's share of the integral.
    inline float ltcEdge(float3 from, float3 to) {
        const float cosine = clamp(dot(from, to), -0.9999, 0.9999);
        const float theta = acos(cosine);
        return cross(from, to).z * (theta / sin(theta));
    }

    // The cosine-weighted integral of the rectangle `corners` (in order around it) seen from
    // `position`, after `transform` (the inverse LTC matrix in the frame of `normal` and `view`). 1 is the whole
    // hemisphere. The polygon is clipped to the upper hemisphere first.
    inline float ltcIntegrate(float3 normal, float3 view, float3 position, float3x3 transform, thread const float3 *corners) {
        const float3 tangent = normalize(view - normal * dot(view, normal));
        const float3 bitangent = cross(normal, tangent);
        const float3x3 frame = transform * transpose(float3x3(tangent, bitangent, normal));
        float3 points[4];
        for (int index = 0; index < 4; index++) {
            points[index] = frame * (corners[index] - position);
        }
        // Clip to z >= 0 (Sutherland-Hodgman); a quad clipped by a plane has at most five corners.
        float3 clipped[5];
        int count = 0;
        for (int index = 0; index < 4; index++) {
            const float3 current = points[index];
            const float3 next = points[(index + 1) % 4];
            if (current.z >= 0.0) {
                clipped[count++] = current;
            }
            if ((current.z >= 0.0) != (next.z >= 0.0)) {
                clipped[count++] = mix(current, next, current.z / (current.z - next.z));
            }
        }
        if (count < 3) {
            return 0.0;
        }
        float sum = 0.0;
        for (int index = 0; index < count; index++) {
            sum += ltcEdge(normalize(clipped[index]), normalize(clipped[(index + 1) % count]));
        }
        // Points behind the light are skipped before this, so the winding's sign does not matter.
        return abs(sum) / (2.0 * M_PI_F);
    }

    // The light's corners, in order around the rectangle.
    inline void areaCorners(LightingLight light, thread float3 *corners) {
        corners[0] = light.position - light.areaRight - light.areaUp;
        corners[1] = light.position - light.areaRight + light.areaUp;
        corners[2] = light.position + light.areaRight + light.areaUp;
        corners[3] = light.position + light.areaRight - light.areaUp;
    }

    // Diffuse and specular light from an area light, as radiance already weighted by the BRDF lobes: multiply
    // `diffuse` by the diffuse color and `specular` by nothing more. `f0` is the specular color at normal incidence.
    struct AreaLightResult {
        float3 diffuse;
        float3 specular;
    };

    inline AreaLightResult areaLight(LightingLight light, float3 position, float3 normal, float3 view, float perceptualRoughness, float3 f0) {
        float3 corners[4];
        areaCorners(light, corners);
        // Lit only from its front: points behind the rectangle get nothing.
        if (dot(position - light.position, light.direction) <= 0.0) {
            return { float3(0.0), float3(0.0) };
        }
        const float NdotV = saturate(dot(normal, view));
        const float4 inverse = ltcLookup(kLightingLTC1, perceptualRoughness, NdotV);
        const float3x3 transform = float3x3(float3(inverse.x, 0, inverse.y), float3(0, 1, 0), float3(inverse.z, 0, inverse.w));
        const float2 terms = ltcLookup(kLightingLTC2, perceptualRoughness, NdotV);
        const float3 radiance = light.color * light.intensity;
        const float specular = ltcIntegrate(normal, view, position, transform, corners);
        const float diffuse = ltcIntegrate(normal, view, position, float3x3(1.0), corners);
        return { radiance * diffuse, radiance * specular * (f0 * terms.x + (1.0 - f0) * terms.y) };
    }

    // KHR_lights_punctual range attenuation: inverse square, cut off smoothly at `range` (0 means infinite).
    inline float rangeAttenuation(float range, float distance) {
        const float inverseSquare = 1.0 / metal::max(distance * distance, 1e-4);
        if (range <= 0.0) {
            return inverseSquare;
        }
        return metal::clamp(1.0 - metal::pow(distance / range, 4.0), 0.0, 1.0) * inverseSquare;
    }

    // SceneKit's attenuation: 1 up to `start`, 0 from `end` on, (remaining fraction)^exponent between.
    inline float falloffAttenuation(float start, float end, float exponent, float distance) {
        if (end <= start) {
            return distance <= start ? 1.0 : 0.0;
        }
        return metal::pow(metal::saturate((end - distance) / (end - start)), exponent);
    }

    inline float spotAttenuation(LightingLight light, float3 toLight) {
        const float cosine = metal::dot(metal::normalize(light.direction), -toLight);
        return metal::smoothstep(light.outerConeCos, light.innerConeCos, cosine);
    }

    // The lights to shade one fragment with (#519): its cluster's list, or every light when clustering is off.
    // Loop `for (uint i = 0; i < list.count; i++) { LightingLight light = lights[list[i]]; ... }`.
    struct LightList {
        // Nil when clustering is off; then the list is 0..<count.
        constant uint *indices;
        uint count;

        uint operator[](uint index) const {
            return indices ? indices[index] : index;
        }
    };

    // The cluster holding a shading-space `position`.
    inline uint clusterIndex(constant LightingClusterUniforms &clusters, float3 position) {
        const float3 relative = position + clusters.originOffset;
        const float4 clip = clusters.viewProjection * float4(relative, 1);
        const float2 ndc = clip.xy / metal::max(clip.w, 1e-6);
        const int3 size = int3(clusters.gridSize);
        const int x = metal::clamp(int(metal::floor((ndc.x * 0.5 + 0.5) * float(size.x))), 0, size.x - 1);
        const int y = metal::clamp(int(metal::floor((ndc.y * 0.5 + 0.5) * float(size.y))), 0, size.y - 1);
        const float distance = -(clusters.view * float4(relative, 1)).z;
        int slice = 0;
        if (distance > clusters.sliceNear) {
            slice = int(metal::floor(metal::log(distance / clusters.sliceNear) / metal::log(clusters.sliceFar / clusters.sliceNear) * float(size.z)));
        }
        slice = metal::clamp(slice, 0, size.z - 1);
        return uint((slice * size.y + y) * size.x + x);
    }

    // `clusters` and `clusterLights` may be null (no clustering): the list is then every one of `lightCount` lights.
    inline LightList lightList(constant LightingClusterUniforms *clusters, constant uint *clusterLights, float3 position, int lightCount) {
        if (clusters == nullptr || clusterLights == nullptr || clusters->enabled == 0) {
            return LightList { nullptr, uint(metal::max(lightCount, 0)) };
        }
        constant uint *cluster = clusterLights + clusterIndex(*clusters, position) * kLightingClusterStride;
        // A count past the list's size means more lights reach the cluster than it holds: shade every light (#628).
        if (cluster[0] > uint(kLightingClusterMaxLights)) {
            return LightList { nullptr, uint(metal::max(lightCount, 0)) };
        }
        return LightList { cluster + 1, cluster[0] };
    }

    // The light arriving at a point, before shadows.
    struct LightSample {
        // Unit vector from the point toward the light.
        float3 toLight;
        // color * intensity * attenuation.
        float3 radiance;
    };

    inline LightSample sample(LightingLight light, float3 position) {
        LightSample result;
        float attenuation = 1.0;
        if (light.type == kLightingLightTypeDirectional) {
            result.toLight = -metal::normalize(light.direction);
        } else {
            const float3 delta = light.position - position;
            const float distance = metal::length(delta);
            result.toLight = delta / metal::max(distance, 1e-6);
            attenuation = light.attenuationFalloffExponent > 0.0
                ? falloffAttenuation(light.attenuationStartDistance, light.range, light.attenuationFalloffExponent, distance)
                : rangeAttenuation(light.range, distance);
            if (light.type == kLightingLightTypeSpot) {
                attenuation *= spotAttenuation(light, result.toLight);
            }
        }
        result.radiance = light.color * light.intensity * attenuation;
        return result;
    }

    // How much of a slice's width and height a light uses, from its top left (#88); 0 means all of it.
    inline float sliceExtent(float4 cascade) {
        return cascade.z > 0.0 ? cascade.z : 1.0;
    }

    // PCF in one slice; 1 is lit. Positions outside the slice's view (the top-left `extent` of the slice) are lit.
    inline float sliceShadow(float3 position, float4x4 viewProjection, float mapSize, int radius, metal::depth2d_array<float> shadowMap, metal::sampler shadowSampler, uint slice, float extent = 1.0) {
        const float4 clip = viewProjection * float4(position, 1);
        const float3 ndc = clip.xyz / clip.w;
        const float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        if (metal::any(uv < 0.0) || metal::any(uv > extent) || ndc.z < 0.0 || ndc.z > 1.0) {
            return 1.0;
        }
        float lit = 0.0;
        const float texel = 1.0 / mapSize;
        for (int x = -radius; x <= radius; x++) {
            for (int y = -radius; y <= radius; y++) {
                lit += shadowMap.sample_compare(shadowSampler, uv + float2(x, y) * texel, slice, ndc.z, metal::level(0));
            }
        }
        const float side = float(2 * radius + 1);
        return lit / (side * side);
    }

    // How much of `light` reaches `position`: the product of its slices' PCF results, tinted by the shadow color and
    // scaled by the shadow intensity. Multiply a LightSample's radiance by it.
    inline float3 shadow(LightingLight light, float3 position, constant LightingShadowUniforms &uniforms, metal::depth2d_array<float> shadowMap, metal::sampler shadowSampler) {
        if (uniforms.enabled == 0 || light.shadowSliceCount <= 0) {
            return float3(1.0);
        }
        float lit = 1.0;
        const int start = metal::max(light.shadowSliceStart, 0);
        const int end = metal::min(light.shadowSliceStart + light.shadowSliceCount, kLightingMaxShadowSliceCount);
        if (start < end && uniforms.sliceCascades[start].x > 0.0) {
            // Cascades: the nearest slice that covers the point, blended into the next near its far end.
            const float distance = metal::length(position);
            for (int slice = start; slice < end; slice++) {
                const float4 cascade = uniforms.sliceCascades[slice];
                if (distance > cascade.x && slice + 1 < end) {
                    continue;
                }
                lit = sliceShadow(position, uniforms.sliceViewProjections[slice], uniforms.mapSize, uniforms.radius, shadowMap, shadowSampler, uint(slice), sliceExtent(cascade));
                if (slice + 1 < end && distance > cascade.y) {
                    const float next = sliceShadow(position, uniforms.sliceViewProjections[slice + 1], uniforms.mapSize, uniforms.radius, shadowMap, shadowSampler, uint(slice + 1), sliceExtent(uniforms.sliceCascades[slice + 1]));
                    lit = metal::mix(lit, next, metal::saturate((distance - cascade.y) / metal::max(cascade.x - cascade.y, 1e-6)));
                }
                break;
            }
        } else {
            for (int slice = start; slice < end; slice++) {
                lit *= sliceShadow(position, uniforms.sliceViewProjections[slice], uniforms.mapSize, uniforms.radius, shadowMap, shadowSampler, uint(slice), sliceExtent(uniforms.sliceCascades[slice]));
            }
        }
        return metal::mix(float3(1.0), uniforms.color, uniforms.intensity * (1.0 - lit));
    }
} // namespace Lighting

#endif
