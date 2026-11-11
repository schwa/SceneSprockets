#pragma once

#import <simd/simd.h>

// One mesh's morph and skin deformation, for the GPU deformation pre-pass. Offsets and strides are in bytes; a
// position or normal is three floats at `offset + vertex * stride` of its buffer.
struct DeformationUniforms {
    unsigned int vertexCount;
    unsigned int positionOffset;
    unsigned int positionStride;
    unsigned int normalOffset;
    unsigned int normalStride;
    // 0 when the mesh has no float3 normals.
    int hasNormals;
    // Morph targets in the delta buffers, each `vertexCount` packed float3s long.
    unsigned int morphCount;
    // 0 when the mesh is not skinned.
    int hasSkin;
};
typedef struct DeformationUniforms DeformationUniforms;
