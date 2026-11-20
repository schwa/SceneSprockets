import GeometryLite3D
import Metal
import MetalSupport
import simd
import SwiftMesh

// CPU morphing and skinning, for renderers without GPU support for them.

extension SceneGraph.MeshEntry {
    /// A mesh with morph targets and skinning applied on the CPU.
    public struct Deformed {
        /// The deformed mesh.
        public var mesh: MetalMesh
        /// Skinned meshes are already in world space, so this is identity for them.
        public var modelMatrix: simd_float4x4
    }

    /// Nil when the node has no active morph targets and no valid skin. Cached on the node until `revision` changes.
    public func deformed(revision: SceneGraph.Revision) -> Deformed? {
        let skin = self.skin
        let hasMorphs = self.hasMorphs
        guard skin != nil || hasMorphs else {
            return nil
        }
        let modelMatrix = skin == nil ? worldTransform : matrix_identity_float4x4
        if let cache = renderCache.deformation, cache.revision == revision {
            return Deformed(mesh: cache.mesh, modelMatrix: modelMatrix)
        }
        let morphs = hasMorphs ? validMorphs : []
        // Outside the lock: two threads may both deform the mesh, and the last one's copy is kept.
        guard let deformedMesh = mesh.deformed(morphTargets: morphs.map(\.target), weights: morphs.map(\.weight), jointMatrices: skin?.jointMatrices(), skinVertices: skinVertices) else {
            return nil
        }
        renderCache.deformation = (revision, deformedMesh)
        return Deformed(mesh: deformedMesh, modelMatrix: modelMatrix)
    }

    // The morph targets that fit the mesh, in order, each with its weight (0 when there is none). The one rule for
    // which targets and weights the CPU and GPU paths use (#590).
    var validMorphs: [(target: SceneGraph.MorphTarget, weight: Float)] {
        let vertexCount = mesh.vertexCount
        let weights = morphWeights
        return morphTargets.enumerated().compactMap { index, target in
            target.isValid(vertexCount: vertexCount) ? (target, index < weights.count ? weights[index] : 0) : nil
        }
    }

    /// This entry ready to draw from plain vertex buffers: its mesh morphed and skinned (by this frame's GPU
    /// deformation pass when there is one, otherwise on the CPU), placed by the model matrix, with no skin or morphs left
    /// and bounds that cover the deformation. Unchanged when there is nothing to deform.
    ///
    /// SceneGraphElement does this for materials whose renderer draws plain vertex buffers. Use it in your own
    /// elements built on ``renderBatches(_:context:)``.
    public func resolvingDeformation(revision: SceneGraph.Revision) -> Self {
        let result: Deformed?
        if let state = renderCache.gpuDeformation, let current = state.current, current.revision == revision, state.key.matches(mesh) {
            result = Deformed(mesh: current.mesh, modelMatrix: current.modelMatrix)
        } else {
            result = deformed(revision: revision)
        }
        guard let result else {
            return self
        }
        // Skinned meshes are in world space, so their posed world bounds are their mesh bounds.
        let bounds: BoundingBox3D? = if skin != nil {
            posedWorldBounds
        } else {
            posedLocalBounds
        }
        return replacingDeformation(mesh: result.mesh, modelMatrix: result.modelMatrix, meshBounds: bounds)
    }
}

// Deformation results, one per node.
final class NodeRenderCache {
    private let lock = NSLock()
    private var storedDeformation: (revision: SceneGraph.Revision, mesh: MetalMesh)?
    private var storedJointBounds: (structure: Int, bounds: [BoundingBox3D?])?

    // Rest-space bounds of the vertices each joint influences, for posed bounds (PosedBounds.swift). Kept until the node's
    // structure revision changes (its mesh or skin vertices).
    var jointBounds: (structure: Int, bounds: [BoundingBox3D?])? {
        get { lock.withLock { storedJointBounds } }
        set { lock.withLock { storedJointBounds = newValue } }
    }

    // The CPU-deformed mesh. Locked: hit testing asks for it on the thread that edits the scene while the render
    // thread asks for it too (#476).
    var deformation: (revision: SceneGraph.Revision, mesh: MetalMesh)? {
        get { lock.withLock { storedDeformation } }
        set { lock.withLock { storedDeformation = newValue } }
    }

    // See GPUDeformation.swift. Only the render thread reads and writes it.
    var gpuDeformation: GPUDeformationState?
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
            guard let copy = buffer.device.makeBuffer(bytes: buffer.cpuReadable.contents(), length: buffer.length, options: .storageModeShared) else {
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
