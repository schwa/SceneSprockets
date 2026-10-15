#include <metal_stdlib>
#include "MetalSprocketsSceneGraphShaders.h"

using namespace metal;

// https://en.wikipedia.org/wiki/Blinn–Phong_reflection_model
namespace BlinnPhong {

    struct Vertex {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float2 textureCoordinate [[attribute(2)]];
    };

    struct Fragment {
        float4 position [[position]];
        float3 worldPosition;
        float3 normal;
        float2 textureCoordinate;
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
        sampler textureSampler [[sampler(0)]]
    ) {
        float3 ambientColor = material.ambient;
        float3 diffuseColor = material.diffuse;
        float3 specularColor = material.specular;
        if (material.hasAmbientTexture) {
            ambientColor *= ambientTexture.sample(textureSampler, in.textureCoordinate).rgb;
        }
        if (material.hasDiffuseTexture) {
            diffuseColor *= diffuseTexture.sample(textureSampler, in.textureCoordinate).rgb;
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
            diffuse += diffuseColor * lambertian * light.color * attenuation;
            specular += specularColor * highlight * light.color * attenuation;
        }
        return float4(frame.ambientLightColor * ambientColor + diffuse + specular, 1);
    }

}
