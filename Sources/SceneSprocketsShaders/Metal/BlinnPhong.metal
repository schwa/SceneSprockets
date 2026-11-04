#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

// https://en.wikipedia.org/wiki/Blinn–Phong_reflection_model
namespace BlinnPhong {

    // True when a shadow map is bound.
    constant bool HAS_SHADOWS [[function_constant(0)]];
    // True when the mesh has per-vertex colors, bound at attribute 3 (#246).
    constant bool HAS_VERTEX_COLORS [[function_constant(1)]];

    // PCF in one slice; 1 is lit. Positions outside the slice's view are lit.
    static float sliceShadow(float3 world, float4x4 viewProjection, float mapSize, int radius, depth2d_array<float, access::sample> shadowMap, sampler shadowSampler, uint slice) {
        float4 clip = viewProjection * float4(world, 1);
        float3 ndc = clip.xyz / clip.w;
        float2 uv = float2(ndc.x * 0.5 + 0.5, 0.5 - ndc.y * 0.5);
        if (any(uv < 0.0) || any(uv > 1.0) || ndc.z < 0.0 || ndc.z > 1.0) {
            return 1;
        }
        float shadow = 0;
        float texel = 1.0 / mapSize;
        for (int x = -radius; x <= radius; x++) {
            for (int y = -radius; y <= radius; y++) {
                shadow += shadowMap.sample_compare(shadowSampler, uv + float2(x, y) * texel, slice, ndc.z, level(0));
            }
        }
        float side = float(2 * radius + 1);
        return shadow / (side * side);
    }

    // Tangent frame from screen-space derivatives (Christian Schuler, "Followup: Normal Mapping Without Precomputed
    // Tangents"), so meshes need no tangent attribute. Texture v runs down, and normal maps point +Y up, hence -B.
    static float3 perturbedNormal(float3 normal, float3 position, float2 uv, float3 mapped) {
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
            return normal;
        }
        float inverse = rsqrt(scale);
        float3x3 frame = float3x3(tangent * inverse, -bitangent * inverse, normal);
        return normalize(frame * mapped);
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
    };

    // One draw per mesh.
    [[vertex]] Fragment vertex_main(
        Vertex in [[stage_in]],
        constant BlinnPhongFrame &frame [[buffer(1)]],
        constant float4x4 &modelMatrix [[buffer(2)]],
        constant float3x3 &normalMatrix [[buffer(3)]]
    ) {
        float4 world = modelMatrix * float4(in.position, 1);
        Fragment out;
        out.position = frame.viewProjection * world;
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
        Vertex in [[stage_in]],
        constant BlinnPhongFrame &frame [[buffer(1)]],
        constant float4x4 *modelMatrices [[buffer(2)]],
        constant float3x3 *normalMatrices [[buffer(3)]]
    ) {
        float4 world = modelMatrices[instanceID] * float4(in.position, 1);
        Fragment out;
        out.position = frame.viewProjection * world;
        out.worldPosition = world.xyz / world.w;
        out.normal = normalMatrices[instanceID] * in.normal;
        out.textureCoordinate = in.textureCoordinate;
        out.color = HAS_VERTEX_COLORS ? in.color : float4(1);
        return out;
    }

    [[fragment]] float4 fragment_main(
        Fragment in [[stage_in]],
        constant BlinnPhongFrame &frame [[buffer(0)]],
        constant BlinnPhongLight *lights [[buffer(1)]],
        constant BlinnPhongMaterialUniforms &material [[buffer(2)]],
        texture2d<float> ambientTexture [[texture(0)]],
        texture2d<float> diffuseTexture [[texture(1)]],
        texture2d<float> specularTexture [[texture(2)]],
        texture2d<float> emissionTexture [[texture(4)]],
        texture2d<float> normalTexture [[texture(5)]],
        sampler textureSampler [[sampler(0)]],
        depth2d_array<float, access::sample> shadowMap [[texture(3), function_constant(HAS_SHADOWS)]],
        sampler shadowSampler [[sampler(1), function_constant(HAS_SHADOWS)]],
        constant BlinnPhongShadowUniforms &shadow [[buffer(3), function_constant(HAS_SHADOWS)]]
    ) {
        float3 ambientColor = material.ambient * in.color.rgb;
        float3 diffuseColor = material.diffuse * in.color.rgb;
        float3 specularColor = material.specular;
        float alpha = material.opacity * in.color.a;
        if (material.hasAmbientTexture) {
            ambientColor *= ambientTexture.sample(textureSampler, in.textureCoordinate).rgb;
        }
        if (material.hasDiffuseTexture) {
            float4 sample = diffuseTexture.sample(textureSampler, in.textureCoordinate);
            diffuseColor *= sample.rgb;
            if (material.usesDiffuseAlpha) {
                alpha *= sample.a;
            }
        }
        if (material.hasSpecularTexture) {
            specularColor *= specularTexture.sample(textureSampler, in.textureCoordinate).rgb;
        }

        // Meshes with missing (zero) normals get the face normal, turned towards the camera.
        float3 normal;
        if (length_squared(in.normal) > 1e-8) {
            normal = normalize(in.normal);
        } else {
            normal = normalize(cross(dfdx(in.worldPosition), dfdy(in.worldPosition)));
            if (dot(normal, frame.cameraPosition - in.worldPosition) < 0) {
                normal = -normal;
            }
        }
        if (material.hasNormalMap) {
            float3 mapped = normalTexture.sample(textureSampler, in.textureCoordinate).xyz * 2.0 - 1.0;
            normal = perturbedNormal(normal, in.worldPosition, in.textureCoordinate, mapped);
        }
        float3 emission = material.emission;
        if (material.hasEmissionTexture) {
            emission *= emissionTexture.sample(textureSampler, in.textureCoordinate).rgb;
        }
        // Material channel views (#195), matching SceneGraphMaterialChannel. Blinn-Phong has no metallic, and
        // roughness comes from shininess as in the usual Phong-to-microfacet mapping.
        switch (frame.materialChannel) {
            case 1: return float4(diffuseColor, 1);
            case 2: return float4(float3(alpha), 1);
            case 3: return float4(0, 0, 0, 1);
            case 4: return float4(float3(sqrt(2.0 / (material.shininess + 2.0))), 1);
            case 5: return float4(specularColor, 1);
            case 6: return float4(emission, 1);
            default: break;
        }
        float3 viewDirection = normalize(frame.cameraPosition - in.worldPosition);
        float3 diffuse = 0;
        float3 specular = 0;
        for (int index = 0; index < frame.lightCount; index++) {
            BlinnPhongLight light = lights[index];
            // From the surface towards the light.
            float3 toLight;
            float attenuation = 1;
            if (light.type == BLINN_PHONG_LIGHT_DIRECTIONAL) {
                toLight = -light.direction;
            } else {
                toLight = light.position - in.worldPosition;
                float distanceSquared = length_squared(toLight);
                toLight = normalize(toLight);
                // Inverse-square with a smooth cutoff at `range`.
                float rangeRatio = sqrt(distanceSquared) / light.range;
                float rangeFalloff = saturate(1.0 - rangeRatio * rangeRatio * rangeRatio * rangeRatio);
                attenuation = rangeFalloff * rangeFalloff / (distanceSquared + 1.0);
                if (light.type == BLINN_PHONG_LIGHT_SPOT) {
                    attenuation *= smoothstep(light.outerConeCos, light.innerConeCos, dot(-toLight, light.direction));
                }
            }
            float lambertian = max(dot(toLight, normal), 0.0);
            if (lambertian == 0.0 || attenuation == 0.0) {
                continue;
            }
            float highlight = pow(max(dot(normalize(toLight + viewDirection), normal), 0.0), material.shininess);
            // Only this light's shadow scales only this light's contribution.
            float3 shadowing = 1;
            if (HAS_SHADOWS && material.receivesShadow != 0 && light.shadowSliceCount > 0) {
                float lit = 1;
                for (int slice = light.shadowSliceStart; slice < light.shadowSliceStart + light.shadowSliceCount; slice++) {
                    lit *= sliceShadow(in.worldPosition, shadow.sliceViewProjections[slice], shadow.mapSize, shadow.radius, shadowMap, shadowSampler, uint(slice));
                }
                shadowing = mix(float3(1), shadow.color, shadow.intensity * (1.0 - lit));
            }
            diffuse += diffuseColor * lambertian * light.color * attenuation * shadowing;
            specular += specularColor * highlight * light.color * attenuation * shadowing;
        }
        return float4(frame.ambientLightColor * ambientColor + diffuse + specular + emission, alpha);
    }

}
