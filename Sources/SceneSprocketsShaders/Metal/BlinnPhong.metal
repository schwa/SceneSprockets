#include <metal_stdlib>
#include "SceneSprocketsShaders.h"
#include "BlinnPhongLighting.h"

using namespace metal;

// https://en.wikipedia.org/wiki/Blinn–Phong_reflection_model
namespace BlinnPhong {

    // True when a shadow map is bound.
    constant bool HAS_SHADOWS [[function_constant(0)]];
    // True when the mesh has per-vertex colors, bound at attribute 3 (#246).
    constant bool HAS_VERTEX_COLORS [[function_constant(1)]];

    // Tangent frame from screen-space derivatives (Christian Schuler, "Followup: Normal Mapping Without Precomputed
    // Tangents"), so meshes need no tangent attribute. Texture v runs down, and normal maps point +Y up, hence -B.
    // Columns: the world directions of +u and +v on the surface, and the normal. False if the derivatives are
    // degenerate.
    static bool tangentFrame(float3 normal, float3 position, float2 uv, thread float3x3 &frame) {
        float3 dp1 = dfdx(position);
        float3 dp2 = dfdy(position);
        float2 duv1 = dfdx(uv);
        float2 duv2 = dfdy(uv);
        float3 dp2perp = cross(dp2, normal);
        float3 dp1perp = cross(normal, dp1);
        float3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
        float3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;
        float scale = max(dot(tangent, tangent), dot(bitangent, bitangent));
        if (scale <= 0) {
            return false;
        }
        float inverse = rsqrt(scale);
        frame = float3x3(tangent * inverse, bitangent * inverse, normal);
        return true;
    }

    static float3 perturbedNormal(float3 normal, float3 position, float2 uv, float3 mapped) {
        float3x3 frame;
        if (!tangentFrame(normal, position, uv, frame)) {
            return normal;
        }
        frame[1] = -frame[1];
        return normalize(frame * mapped);
    }

    // Parallax occlusion mapping (#537): steps the view ray down through the height field in texture space and
    // returns the texture coordinate where it meets the surface.
    static float2 parallaxCoordinate(float2 uv, float3 normal, float3 position, float3 cameraPosition, texture2d<float> heightTexture, sampler textureSampler, float heightScale, float depth) {
        float3x3 frame;
        if (depth <= 0 || !tangentFrame(normal, position, uv, frame)) {
            return uv;
        }
        // The view direction in texture space: x along +u, y along +v, z out of the surface.
        float3 view = normalize(cameraPosition - position);
        float3 tangentView = float3(dot(view, frame[0]), dot(view, frame[1]), dot(view, normal));
        if (tangentView.z <= 1e-3) {
            return uv;
        }
        // More steps at grazing angles, where the ray crosses more of the texture.
        const float steps = mix(32.0, 8.0, tangentView.z);
        const float layer = 1.0 / steps;
        const float2 delta = -tangentView.xy / tangentView.z * depth * layer;
        // Gradients from the original coordinate keep mip selection stable while the coordinate moves.
        const float2 gradientX = dfdx(uv);
        const float2 gradientY = dfdy(uv);
        float2 current = uv;
        float rayDepth = 0;
        float surfaceDepth = 1 - saturate(heightTexture.sample(textureSampler, current, gradient2d(gradientX, gradientY)).r * heightScale);
        for (int index = 0; index < 32 && rayDepth < surfaceDepth; index++) {
            current += delta;
            rayDepth += layer;
            surfaceDepth = 1 - saturate(heightTexture.sample(textureSampler, current, gradient2d(gradientX, gradientY)).r * heightScale);
        }
        // Interpolates between the last two steps for a smooth result.
        const float2 previous = current - delta;
        const float after = surfaceDepth - rayDepth;
        const float before = (1 - saturate(heightTexture.sample(textureSampler, previous, gradient2d(gradientX, gradientY)).r * heightScale)) - (rayDepth - layer);
        const float weight = after - before == 0 ? 0 : after / (after - before);
        return mix(current, previous, saturate(weight));
    }

    struct Vertex {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float2 textureCoordinate [[attribute(2)]];
        float4 color [[attribute(3), function_constant(HAS_VERTEX_COLORS)]];
    };

    struct Fragment {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float2 textureCoordinate;
        // Multiplies ambient, diffuse and alpha; white without vertex colors.
        float4 color;
        // The view (amplification ID) this is drawn for.
        uint view [[flat]];
    };

    // One draw per mesh.
    [[vertex]] Fragment vertex_main(
        ushort view [[amplification_id]],
        Vertex in [[stage_in]],
        constant BlinnPhongFrame &frame [[buffer(1)]],
        constant float4x4 &modelMatrix [[buffer(2)]],
        constant float3x3 &normalMatrix [[buffer(3)]]
    ) {
        float4 world = modelMatrix * float4(in.position, 1);
        Fragment out;
        out.position = frame.viewProjections[view] * world;
        out.view = view;
        out.worldPosition = world.xyz / world.w;
        // Not normalized here: a zero normal must stay zero (normalize would give NaN).
        out.normal = normalMatrix * in.normal;
        out.textureCoordinate = in.textureCoordinate;
        out.color = HAS_VERTEX_COLORS ? in.color : float4(1);
        return out;
    }

    // One draw for many copies of a mesh.
    [[vertex]] Fragment vertex_instanced(
        uint instanceID [[instance_id]],
        ushort view [[amplification_id]],
        Vertex in [[stage_in]],
        constant BlinnPhongFrame &frame [[buffer(1)]],
        constant float4x4 *modelMatrices [[buffer(2)]],
        constant float3x3 *normalMatrices [[buffer(3)]]
    ) {
        float4 world = modelMatrices[instanceID] * float4(in.position, 1);
        Fragment out;
        out.position = frame.viewProjections[view] * world;
        out.view = view;
        out.worldPosition = world.xyz / world.w;
        out.normal = normalMatrices[instanceID] * in.normal;
        out.textureCoordinate = in.textureCoordinate;
        out.color = HAS_VERTEX_COLORS ? in.color : float4(1);
        return out;
    }

    // The shaded color, for fragment_main and fragment_weighted.
    static inline float4 fragmentColor(
        Fragment in,
        bool frontFacing,
        constant BlinnPhongFrame &frame,
        constant LightingLight *lights,
        constant BlinnPhongMaterialUniforms &material,
        constant LightingFrameResources &frameResources,
        constant BlinnPhongMaterialResources &materialResources,
        constant LightingClusterUniforms &lightClusterUniforms,
        constant uint *lightClusters,
        constant LightingShadowUniforms &shadow
    ) {
        const texture2d<float> ambientTexture = materialResources.ambientTexture;
        const texture2d<float> diffuseTexture = materialResources.diffuseTexture;
        const texture2d<float> specularTexture = materialResources.specularTexture;
        const texture2d<float> emissionTexture = materialResources.emissionTexture;
        const texture2d<float> normalTexture = materialResources.normalTexture;
        const sampler textureSampler = materialResources.textureSampler;
        float2 uv = in.textureCoordinate;
        if (material.hasHeightTexture) {
            uv = parallaxCoordinate(uv, normalize(in.normal), in.worldPosition, frame.cameraPositions[in.view], materialResources.heightTexture, textureSampler, material.heightScale, material.parallaxDepth);
        }
        const texture2d<float> ambientOcclusion = frameResources.ambientOcclusion;
        float3 ambientColor = material.ambient * in.color.rgb;
        float3 diffuseColor = material.diffuse * in.color.rgb;
        float3 specularColor = material.specular;
        float alpha = material.opacity * in.color.a;
        if (material.hasAmbientTexture) {
            ambientColor *= ambientTexture.sample(textureSampler, uv).rgb;
        }
        if (material.hasDiffuseTexture) {
            float4 sample = diffuseTexture.sample(textureSampler, uv);
            diffuseColor *= sample.rgb;
            if (material.usesDiffuseAlpha) {
                alpha *= sample.a;
            }
        }
        if (material.hasSpecularTexture) {
            specularColor *= specularTexture.sample(textureSampler, uv).rgb;
        }

        // Meshes with missing (zero) normals get the face normal, turned towards the camera.
        float3 normal;
        if (length_squared(in.normal) > 1e-8) {
            normal = normalize(in.normal);
            // Two-sided materials: back faces are lit as seen from their own side (#500).
            if (!frontFacing) {
                normal = -normal;
            }
        } else {
            normal = normalize(cross(dfdx(in.worldPosition), dfdy(in.worldPosition)));
            if (dot(normal, frame.cameraPositions[in.view] - in.worldPosition) < 0) {
                normal = -normal;
            }
        }
        if (material.hasNormalMap) {
            float3 mapped = material.normal;
            if (material.hasNormalTexture) {
                mapped *= normalTexture.sample(textureSampler, uv).xyz * 2.0 - 1.0;
            }
            normal = perturbedNormal(normal, in.worldPosition, in.textureCoordinate, mapped);
        }
        float3 emission = material.emission;
        if (material.hasEmissionTexture) {
            emission *= emissionTexture.sample(textureSampler, uv).rgb;
        }
        if (material.stochasticAlpha != 0) {
            // Stochastic transparency (#539): the pipeline turns alpha into sample coverage.
            alpha = Lighting::stochasticAlpha(alpha, in.position);
            if (alpha <= 0.0) {
                discard_fragment();
            }
        }
        Surface surface = { ambientColor, diffuseColor, specularColor, emission, material.shininess, alpha, material.receivesShadow != 0 };
        float4 channel;
        if (channelColor(surface, frame.materialChannel, channel)) {
            return channel;
        }
        uint2 occlusionSize = uint2(ambientOcclusion.get_width(), ambientOcclusion.get_height());
        const float4 occlusionSample = ambientOcclusion.read(min(uint2(in.position.xy), occlusionSize - 1));
        // Red: ambient occlusion. Green: contact shadows (#495), read only for lights that have them.
        return shade(surface, in.worldPosition, normal, frame.cameraPositions[in.view], frame, lights, &lightClusterUniforms, lightClusters, occlusionSample.r, HAS_SHADOWS, frameResources.shadowMap, frameResources.shadowSampler, shadow, occlusionSample.g);
    }

    [[fragment]] float4 fragment_main(
        Fragment in [[stage_in]],
        bool frontFacing [[front_facing]],
        constant BlinnPhongFrame &frame [[buffer(0)]],
        constant LightingLight *lights [[buffer(1)]],
        constant BlinnPhongMaterialUniforms &material [[buffer(2)]],
        // The shadow map and sampler, and screen-space ambient visibility (#136; 1x1 white when off).
        constant LightingFrameResources &frameResources [[buffer(4)]],
        constant BlinnPhongMaterialResources &materialResources [[buffer(5)]],
        // Clustered lights (#519); `enabled` 0 loops over every light.
        constant LightingClusterUniforms &lightClusterUniforms [[buffer(6)]],
        constant uint *lightClusters [[buffer(7)]],
        constant LightingShadowUniforms &shadow [[buffer(3), function_constant(HAS_SHADOWS)]]
    ) {
        return fragmentColor(in, frontFacing, frame, lights, material, frameResources, materialResources, lightClusterUniforms, lightClusters, shadow);
    }

    // fragment_main's color as weighted blended transparency (#494).
    [[fragment]] Lighting::WeightedTransparencyOutput fragment_weighted(
        Fragment in [[stage_in]],
        bool frontFacing [[front_facing]],
        constant BlinnPhongFrame &frame [[buffer(0)]],
        constant LightingLight *lights [[buffer(1)]],
        constant BlinnPhongMaterialUniforms &material [[buffer(2)]],
        constant LightingFrameResources &frameResources [[buffer(4)]],
        constant BlinnPhongMaterialResources &materialResources [[buffer(5)]],
        constant LightingClusterUniforms &lightClusterUniforms [[buffer(6)]],
        constant uint *lightClusters [[buffer(7)]],
        constant LightingShadowUniforms &shadow [[buffer(3), function_constant(HAS_SHADOWS)]]
    ) {
        return Lighting::weightedTransparency(fragmentColor(in, frontFacing, frame, lights, material, frameResources, materialResources, lightClusterUniforms, lightClusters, shadow), in.position);
    }

}
