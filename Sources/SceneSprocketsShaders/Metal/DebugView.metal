#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

// Debug views for whole scenes (#132), drawn by SceneGraphDebugRenderer. The renderer maps each mesh's position,
// normal and first texture coordinate to attributes 0, 1 and 2. A mesh without normals or texture coordinates gets
// position there instead, and `debug.y` / `debug.z` say so.
namespace DebugView {

    struct VertexIn {
        float3 position [[attribute(0)]];
        float3 normal [[attribute(1)]];
        float2 textureCoordinate [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldNormal;
        float3 worldPosition;
        float2 textureCoordinate;
    };

    // Matches SceneGraphDebugMode's raw values.
    constant int modeShaded = 0;
    constant int modeNormals = 1;
    constant int modeTextureCoordinates = 2;
    constant int modeUVChecker = 3;
    constant int modeWorldPosition = 4;
    constant int modeWireframe = 5;

    [[vertex]] VertexOut vertex_main(VertexIn in [[stage_in]], constant ShaderMaterialTransforms &transforms [[buffer(10)]]) {
        VertexOut out;
        out.position = transforms.modelViewProjectionMatrix * float4(in.position, 1);
        out.worldNormal = (transforms.normalMatrix * float4(in.normal, 0)).xyz;
        out.worldPosition = (transforms.modelMatrix * float4(in.position, 1)).xyz;
        out.textureCoordinate = in.textureCoordinate;
        return out;
    }

    // `debug`: x mode, y has normals, z has texture coordinates.
    [[fragment]] float4 fragment_main(VertexOut in [[stage_in]], bool isFrontFacing [[front_facing]], constant ShaderMaterialTransforms &transforms [[buffer(10)]], constant int4 &debug [[buffer(11)]]) {
        int mode = debug.x;
        bool hasNormals = debug.y != 0;
        bool hasTextureCoordinates = debug.z != 0;
        // Flat normals from screen-space derivatives when the mesh has none.
        float3 normal = hasNormals ? normalize(in.worldNormal) : normalize(cross(dfdx(in.worldPosition), dfdy(in.worldPosition)));
        if (!isFrontFacing) {
            normal = -normal;
        }
        float3 toCamera = normalize(transforms.cameraPosition - in.worldPosition);
        float facing = saturate(dot(normal, toCamera));
        float3 color;
        switch (mode) {
            case modeNormals:
                color = normal * 0.5 + 0.5;
                break;
            case modeTextureCoordinates:
                color = hasTextureCoordinates ? float3(fract(in.textureCoordinate), 0) : float3(1, 0, 1);
                break;
            case modeUVChecker: {
                if (!hasTextureCoordinates) {
                    color = float3(1, 0, 1);
                    break;
                }
                float2 cell = floor(in.textureCoordinate * 8);
                float checker = fmod(cell.x + cell.y, 2) == 0 ? 0.9 : 0.25;
                color = float3(checker) * (0.5 + 0.5 * facing);
                break;
            }
            case modeWorldPosition:
                color = fract(in.worldPosition);
                break;
            case modeWireframe:
                color = float3(0.9);
                break;
            case modeShaded:
            default:
                color = float3(0.8) * (0.2 + 0.8 * facing);
                break;
        }
        // Back faces are tinted red, which shows flipped normals and open meshes.
        if (!isFrontFacing && mode != modeWireframe) {
            color = mix(color, float3(1, 0, 0), 0.5);
        }
        return float4(color, transforms.opacity);
    }
}
