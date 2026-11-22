#include <metal_stdlib>
#include "SceneSprocketsShaders.h"
#include "MetalSprocketsLighting.h"

using namespace metal;

namespace Fog {

    // Henyey-Greenstein phase function; `cosine` is between the light's travel and the direction to the eye.
    inline float phase(float cosine, float anisotropy) {
        const float g = clamp(anisotropy, -0.99, 0.99);
        const float denominator = 1.0 + g * g - 2.0 * g * cosine;
        return (1.0 - g * g) / (4.0 * M_PI_F * pow(max(denominator, 1e-4), 1.5));
    }

    // Lighting::shadow for points in the air. Shadow maps are fitted to the scene's geometry, so empty space past the
    // farthest caster is beyond a slice's far plane, where Lighting::sliceShadow counts it as lit. Such a point is
    // behind whatever the map holds there, so it is compared at the far plane instead (reversed depth: 0). Points
    // nearer than the near plane are in front of every caster: lit.
    inline float3 volumeShadow(LightingLight light, float3 position, constant LightingShadowUniforms &uniforms, depth2d_array<float> shadowMap, sampler shadowSampler) {
        if (uniforms.enabled == 0 || light.shadowSliceCount <= 0) {
            return float3(1.0);
        }
        float lit = 1.0;
        const int end = min(light.shadowSliceStart + light.shadowSliceCount, kLightingMaxShadowSliceCount);
        for (int slice = max(light.shadowSliceStart, 0); slice < end; slice++) {
            const float4 clip = uniforms.sliceViewProjections[slice] * float4(position, 1);
            const float3 ndc = clip.xyz / clip.w;
            const float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
            if (clip.w <= 0.0 || any(uv < 0.0) || any(uv > 1.0) || ndc.z > 1.0) {
                continue;
            }
            lit *= shadowMap.sample_compare(shadowSampler, uv, uint(slice), max(ndc.z, 0.0), level(0));
        }
        return mix(float3(1.0), uniforms.color, uniforms.intensity * (1.0 - lit));
    }

    // Interleaved gradient noise: a per-pixel offset for the first step, which turns banding into fine noise.
    inline float stepJitter(uint2 pixel) {
        return fract(52.9829189 * fract(dot(float2(pixel), float2(0.06711056, 0.00583715))));
    }

    // Volumetric fog (#540): marches each pixel's ray from the camera to the surface (or `maximumDistance` over the
    // background), dimming what is behind and adding light scattered toward the camera, shadowed per light. Then
    // blends the distance fog as fog_compute does.
    [[kernel]] void fog_scatter_compute(
        uint2 tid [[thread_position_in_grid]],
        depth2d<float, access::read> sceneDepth [[texture(0)]],
        texture2d<float, access::read_write> outputTexture [[texture(1)]],
        depth2d_array<float> shadowMap [[texture(2)]],
        sampler shadowSampler [[sampler(0)]],
        constant FogUniforms &uniforms [[buffer(0)]],
        constant FogScatteringUniforms &scattering [[buffer(1)]],
        constant LightingLight *lights [[buffer(2)]],
        constant LightingShadowUniforms &shadow [[buffer(3)]]
    ) {
        uint2 outputSize = uint2(outputTexture.get_width(), outputTexture.get_height());
        if (tid.x >= outputSize.x || tid.y >= outputSize.y) {
            return;
        }
        uint2 depthSize = uint2(sceneDepth.get_width(), sceneDepth.get_height());
        uint2 depthCoord = uint2(float2(tid) * float2(depthSize) / float2(outputSize));
        const float depth = sceneDepth.read(depthCoord);
        const bool isBackground = depth == 0.0;
        float2 ndc = (float2(tid) + 0.5) / float2(outputSize) * 2.0 - 1.0;
        ndc.y = -ndc.y;
        // A point on the ray: the surface, or any depth for the background (reverse-Z: 1 is the near plane).
        float4 point = uniforms.inverseViewProjection * float4(ndc, isBackground ? 1.0 : depth, 1.0);
        point /= point.w;
        const float3 toPoint = point.xyz - uniforms.cameraPosition;
        const float3 direction = normalize(toPoint);
        const float distance = isBackground ? scattering.maximumDistance : min(length(toPoint), scattering.maximumDistance);

        float4 color = outputTexture.read(tid);
        const int stepCount = max(scattering.stepCount, 1);
        const float stepLength = distance / float(stepCount);
        const float stepTransmittance = exp(-scattering.density * stepLength);
        float transmittance = 1.0;
        float3 scattered = 0.0;
        const float jitter = stepJitter(tid);
        for (int step = 0; step < stepCount; step++) {
            const float3 position = uniforms.cameraPosition + direction * ((float(step) + jitter) * stepLength);
            float3 inScattered = 0.0;
            for (int index = 0; index < scattering.lightCount; index++) {
                const LightingLight light = lights[index];
                const Lighting::LightSample lightSample = Lighting::sample(light, position);
                if (all(lightSample.radiance == 0.0)) {
                    continue;
                }
                // The light travels along -toLight; the eye is along -direction.
                const float cosine = dot(lightSample.toLight, direction);
                inScattered += lightSample.radiance * volumeShadow(light, position, shadow, shadowMap, shadowSampler) * phase(cosine, scattering.anisotropy);
            }
            // Light scattered in this step, dimmed by the fog between it and the camera.
            scattered += transmittance * inScattered * (1.0 - stepTransmittance) ;
            transmittance *= stepTransmittance;
        }
        color.rgb = color.rgb * transmittance + scattered * scattering.intensity;

        if (!isBackground) {
            const float span = max(uniforms.endDistance - uniforms.startDistance, 1e-6);
            const float amount = pow(saturate((length(toPoint) - uniforms.startDistance) / span), max(uniforms.densityExponent, 1e-6)) * uniforms.color.w;
            color.rgb = mix(color.rgb, uniforms.color.rgb, amount);
        }
        outputTexture.write(color, tid);
    }

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
