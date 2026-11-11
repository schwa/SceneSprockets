#include <metal_stdlib>
#include "SceneSprocketsShaders.h"

using namespace metal;

// Morphs and skins mesh vertices on the GPU, for renderers that draw plain vertex buffers (Blinn-Phong,
// ShaderMaterial, the debug view). Matches MetalMesh.deformed in Deformation.swift.
namespace Deformation {

    static float3 load(device const uchar *buffer, uint offset) {
        return float3(*(device const packed_float3 *)(buffer + offset));
    }

    static void store(device uchar *buffer, uint offset, float3 value) {
        *(device packed_float3 *)(buffer + offset) = packed_float3(value);
    }

    static float3 deform(float3 value, uint vertexIndex, bool isNormal, constant DeformationUniforms &uniforms, device const float *weights, device const packed_float3 *deltas, device const float4 *influences, device const float4x4 *jointMatrices) {
        for (uint target = 0; target < uniforms.morphCount; target++) {
            float weight = weights[target];
            if (weight != 0) {
                value += float3(deltas[target * uniforms.vertexCount + vertexIndex]) * weight;
            }
        }
        if (uniforms.hasSkin) {
            float4 joints = influences[vertexIndex * 2];
            float4 jointWeights = influences[vertexIndex * 2 + 1];
            float3 skinned = 0;
            for (int slot = 0; slot < 4; slot++) {
                if (jointWeights[slot] != 0) {
                    skinned += (jointMatrices[uint(joints[slot])] * float4(value, isNormal ? 0 : 1)).xyz * jointWeights[slot];
                }
            }
            value = skinned;
        }
        if (isNormal && length_squared(value) > 0) {
            value = normalize(value);
        }
        return value;
    }

    // One thread per vertex. Positions and normals may share a buffer (interleaved); the output buffers are copies of
    // the rest buffers, so other attributes are already in place.
    [[kernel]] void deform_vertices(
        uint vertexIndex [[thread_position_in_grid]],
        constant DeformationUniforms &uniforms [[buffer(0)]],
        device const uchar *restPositions [[buffer(1)]],
        device uchar *outputPositions [[buffer(2)]],
        device const uchar *restNormals [[buffer(3)]],
        device uchar *outputNormals [[buffer(4)]],
        device const float *weights [[buffer(5)]],
        device const packed_float3 *positionDeltas [[buffer(6)]],
        device const packed_float3 *normalDeltas [[buffer(7)]],
        device const float4 *influences [[buffer(8)]],
        device const float4x4 *jointMatrices [[buffer(9)]]
    ) {
        if (vertexIndex >= uniforms.vertexCount) {
            return;
        }
        uint positionOffset = uniforms.positionOffset + vertexIndex * uniforms.positionStride;
        store(outputPositions, positionOffset, deform(load(restPositions, positionOffset), vertexIndex, false, uniforms, weights, positionDeltas, influences, jointMatrices));
        if (uniforms.hasNormals) {
            uint normalOffset = uniforms.normalOffset + vertexIndex * uniforms.normalStride;
            store(outputNormals, normalOffset, deform(load(restNormals, normalOffset), vertexIndex, true, uniforms, weights, normalDeltas, influences, jointMatrices));
        }
    }

}
