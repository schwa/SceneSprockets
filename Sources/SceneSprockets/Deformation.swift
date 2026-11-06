import Metal
import MetalSupport
import simd
import SwiftMesh

// CPU morphing and skinning, for renderers without GPU support for them.

extension SceneGraph.MeshEntry {
    public struct Deformed {
        public var mesh: MetalMesh
        // Skinned meshes are already in world space, so this is identity for them.
        public var modelMatrix: simd_float4x4
    }

    // Nil when the node has no active morph targets and no valid skin. Cached on the node until `revision` changes.
    public func deformed(revision: SceneGraph.Revision) -> Deformed? {
        let skin = node.validSkin(vertexCount: mesh.vertexCount)
        let hasMorphs = node.morphTargets.contains { $0.isValid(vertexCount: mesh.vertexCount) } && node.morphWeights.contains { $0 != 0 }
        guard skin != nil || hasMorphs else {
            return nil
        }
        let modelMatrix = skin == nil ? worldTransform : matrix_identity_float4x4
        if let cache = node.deformationCache, cache.revision == revision {
            return Deformed(mesh: cache.mesh, modelMatrix: modelMatrix)
        }
        guard let deformedMesh = mesh.deformed(morphTargets: hasMorphs ? node.morphTargets : [], weights: node.morphWeights, jointMatrices: skin?.jointMatrices(), skinVertices: node.skinVertices) else {
            return nil
        }
        node.deformationCache = (revision, deformedMesh)
        return Deformed(mesh: deformedMesh, modelMatrix: modelMatrix)
    }
}

extension SceneGraph.Node {
    func validSkin(vertexCount: Int) -> SceneGraph.Skin? {
        guard let skin, skin.joints.count == skin.inverseBindMatrices.count, skinVertices.count == vertexCount else {
            return nil
        }
        return skin
    }
}

extension MetalMesh {
    private func attribute(_ semantic: VertexDescriptor.Attribute.Semantic) -> (buffer: Int, offset: Int, stride: Int)? {
        guard let attribute = vertexDescriptor.attributes.first(where: { $0.semantic == semantic }), attribute.format == .float3 else {
            return nil
        }
        return (attribute.bufferIndex, attribute.offset, vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12)
    }

    // Copies the vertex buffers and rewrites float3 positions and normals. Submeshes keep their index buffers.
    // swiftlint:disable:next discouraged_optional_collection - nil means the mesh is not skinned
    func deformed(morphTargets: [SceneGraph.MorphTarget], weights: [Float], jointMatrices: [simd_float4x4]?, skinVertices: [SceneGraph.SkinVertex]) -> MetalMesh? {
        var copies: [Int: MTLBuffer] = [:]
        for (index, buffer) in vertexBuffers {
            guard let copy = buffer.device.makeBuffer(bytes: buffer.contents(), length: buffer.length, options: .storageModeShared) else {
                return nil
            }
            copy.label = buffer.label.map { "\($0) (deformed)" }
            copies[index] = copy
        }
        func rewrite(_ semantic: VertexDescriptor.Attribute.Semantic, isNormal: Bool) {
            guard let attribute = attribute(semantic), let buffer = copies[attribute.buffer] else {
                return
            }
            let base = buffer.contents().advanced(by: attribute.offset)
            for vertex in 0..<vertexCount {
                let pointer = base.advanced(by: vertex * attribute.stride)
                var value = SIMD3<Float>(pointer.loadUnaligned(as: Float.self), pointer.loadUnaligned(fromByteOffset: 4, as: Float.self), pointer.loadUnaligned(fromByteOffset: 8, as: Float.self))
                for (target, weight) in zip(morphTargets, weights) where weight != 0 {
                    let deltas = isNormal ? target.normalDeltas : target.positionDeltas
                    if !deltas.isEmpty {
                        value += deltas[vertex] * weight
                    }
                }
                if let jointMatrices {
                    let influence = skinVertices[vertex]
                    var skinned = SIMD3<Float>.zero
                    for slot in 0..<4 where influence.weights[slot] != 0 {
                        let jointIndex = Int(influence.joints[slot])
                        guard jointMatrices.indices.contains(jointIndex) else {
                            continue
                        }
                        let transformed = jointMatrices[jointIndex] * SIMD4(value, isNormal ? 0 : 1)
                        skinned += SIMD3(transformed.x, transformed.y, transformed.z) * influence.weights[slot]
                    }
                    value = skinned
                }
                if isNormal, simd_length(value) > 0 {
                    value = simd_normalize(value)
                }
                pointer.storeBytes(of: value.x, as: Float.self)
                pointer.storeBytes(of: value.y, toByteOffset: 4, as: Float.self)
                pointer.storeBytes(of: value.z, toByteOffset: 8, as: Float.self)
            }
        }
        rewrite(.position, isNormal: false)
        rewrite(.normal, isNormal: true)
        var result = self
        result.vertexBuffers = copies
        return result
    }
}
