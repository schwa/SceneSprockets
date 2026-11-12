import Foundation
import Metal
import MetalSprockets
import MetalSupport
import SceneSprocketsShaders
import simd
import SwiftMesh

/// Materials whose renderer draws plain vertex buffers, so SceneGraphElement morphs and skins their meshes on the GPU
/// before the scene pass (#298). Renderers get the result from `MeshEntry.renderDeformed(revision:)`.
package protocol DrawsDeformedVertices {}

extension SceneGraph.MeshEntry {
    /// The GPU-deformed mesh that this frame's deformation pass writes, or the CPU-deformed mesh when there is none.
    package func renderDeformed(revision: SceneGraph.Revision) -> Deformed? {
        if let state = renderCache.gpuDeformation, let current = state.current, current.revision == revision, state.key.matches(mesh) {
            return Deformed(mesh: current.mesh, modelMatrix: current.modelMatrix)
        }
        return deformed(revision: revision)
    }
}

// Per node: copies of the mesh's vertex buffers, one set per frame in flight (like the shadow map), and the morph and
// skin data, which change rarely.
final class GPUDeformationState {
    static let slotCount = 3

    struct Key {
        var buffers: [ObjectIdentifier]
        var offsets: [Int]
        var vertexCount: Int
        var morphTargets: [SceneGraph.MorphTarget]
        var skinVertices: [SceneGraph.SkinVertex]

        init(mesh: MetalMesh, entry: SceneGraph.MeshEntry) {
            let sorted = mesh.vertexBuffers.sorted { $0.key < $1.key }
            buffers = sorted.map { ObjectIdentifier($0.value) }
            offsets = sorted.map { mesh.vertexBufferOffsets[$0.key] ?? 0 }
            vertexCount = mesh.vertexCount
            morphTargets = entry.morphTargets
            skinVertices = entry.skinVertices
        }

        func matches(_ mesh: MetalMesh) -> Bool {
            let sorted = mesh.vertexBuffers.sorted { $0.key < $1.key }
            return buffers == sorted.map { ObjectIdentifier($0.value) } && offsets == sorted.map { mesh.vertexBufferOffsets[$0.key] ?? 0 } && vertexCount == mesh.vertexCount
        }

        // Arrays compare by storage identity first, so an unchanged node is cheap to check.
        func matches(_ mesh: MetalMesh, entry: SceneGraph.MeshEntry) -> Bool {
            matches(mesh) && morphTargets == entry.morphTargets && skinVertices == entry.skinVertices
        }
    }

    let key: Key
    let slots: [[Int: MTLBuffer]]
    let layout: (positionBuffer: Int, normalBuffer: Int?, uniforms: DeformationUniforms)
    let positionDeltas: MTLBuffer?
    let normalDeltas: MTLBuffer?
    let influences: MTLBuffer?
    var current: (revision: SceneGraph.Revision, mesh: MetalMesh, modelMatrix: simd_float4x4)?

    // Nil when the mesh has no float3 positions or a buffer cannot be made; the CPU path is used then.
    init?(mesh: MetalMesh, entry: SceneGraph.MeshEntry) {
        func attribute(_ semantic: VertexDescriptor.Attribute.Semantic) -> (buffer: Int, offset: Int, stride: Int)? {
            guard let attribute = mesh.vertexDescriptor.attributes.first(where: { $0.semantic == semantic }), attribute.format == .float3, mesh.vertexBuffers[attribute.bufferIndex] != nil else {
                return nil
            }
            let offset = attribute.offset + (mesh.vertexBufferOffsets[attribute.bufferIndex] ?? 0)
            return (attribute.bufferIndex, offset, mesh.vertexDescriptor.layouts[attribute.bufferIndex]?.stride ?? 12)
        }
        guard let position = attribute(.position), mesh.vertexCount > 0 else {
            return nil
        }
        let normal = attribute(.normal)
        let device = mesh.vertexBuffer.device
        var slots: [[Int: MTLBuffer]] = []
        for slot in 0..<Self.slotCount {
            var copies: [Int: MTLBuffer] = [:]
            for (index, buffer) in mesh.vertexBuffers {
                guard let copy = device.makeBuffer(bytes: buffer.cpuReadable.contents(), length: buffer.length, options: .storageModeShared) else {
                    return nil
                }
                copy.label = "\(buffer.label ?? "Vertices") (GPU deformed \(slot))"
                copies[index] = copy
            }
            slots.append(copies)
        }
        let vertexCount = mesh.vertexCount
        let morphTargets = entry.morphTargets.filter { $0.isValid(vertexCount: vertexCount) }
        func deltas(_ path: KeyPath<SceneGraph.MorphTarget, [SIMD3<Float>]>) -> MTLBuffer? {
            guard !morphTargets.isEmpty else {
                return nil
            }
            var packed: [Packed3] = []
            packed.reserveCapacity(morphTargets.count * vertexCount)
            for target in morphTargets {
                let values = target[keyPath: path]
                packed += values.isEmpty ? Array(repeating: Packed3(.zero), count: vertexCount) : values.map(Packed3.init)
            }
            return device.makeBuffer(bytes: packed, length: packed.count * MemoryLayout<Packed3>.stride, options: .storageModeShared)
        }
        let skinned = entry.skinVertices.count == vertexCount
        let influences = skinned ? entry.skinVertices.flatMap { [SIMD4<Float>($0.joints), $0.weights] } : []
        self.key = Key(mesh: mesh, entry: entry)
        self.slots = slots
        self.layout = (
            position.buffer,
            normal?.buffer,
            DeformationUniforms(
                vertexCount: UInt32(vertexCount),
                positionOffset: UInt32(position.offset),
                positionStride: UInt32(position.stride),
                normalOffset: UInt32(normal?.offset ?? 0),
                normalStride: UInt32(normal?.stride ?? 0),
                hasNormals: normal == nil ? 0 : 1,
                morphCount: UInt32(morphTargets.count),
                hasSkin: 0
            )
        )
        self.positionDeltas = deltas(\.positionDeltas)
        self.normalDeltas = deltas(\.normalDeltas)
        self.influences = influences.isEmpty ? nil : device.makeBuffer(bytes: influences, length: influences.count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
    }
}

// The deformation of one mesh in one frame.
struct GPUDeformationJob {
    var uniforms: DeformationUniforms
    var restPositions: MTLBuffer
    var outputPositions: MTLBuffer
    var restNormals: MTLBuffer
    var outputNormals: MTLBuffer
    var weights: [Float]
    var positionDeltas: MTLBuffer?
    var normalDeltas: MTLBuffer?
    var influences: MTLBuffer?
    var jointMatrices: [simd_float4x4]
}

enum GPUDeformation {
    // Prepares this frame's deformation of every morphed or skinned mesh drawn by a DrawsDeformedVertices material, and
    // publishes the result on each node for `renderDeformed(revision:)`. Returns the jobs for DeformationPass.
    static func prepare(entries: [SceneGraph.MeshEntry], revision: SceneGraph.Revision, submissionIndex: UInt64) -> [GPUDeformationJob] {
        var jobs: [GPUDeformationJob] = []
        var done = Set<SceneGraph.Node.ID>()
        let slot = Int(submissionIndex % UInt64(GPUDeformationState.slotCount))
        for entry in entries where entry.material is any DrawsDeformedVertices {
            let cache = entry.renderCache
            guard done.insert(entry.nodeID).inserted else {
                continue
            }
            let mesh = entry.mesh
            let skin = entry.skin
            let weights = entry.morphWeights
            let hasMorphs = entry.hasMorphs
            guard skin != nil || hasMorphs else {
                continue
            }
            if cache.gpuDeformation.map({ !$0.key.matches(mesh, entry: entry) }) ?? true {
                cache.gpuDeformation = GPUDeformationState(mesh: mesh, entry: entry)
            }
            guard let state = cache.gpuDeformation, let restPositions = mesh.vertexBuffers[state.layout.positionBuffer], let outputPositions = state.slots[slot][state.layout.positionBuffer] else {
                continue
            }
            let normalBuffer = state.layout.normalBuffer ?? state.layout.positionBuffer
            guard let restNormals = mesh.vertexBuffers[normalBuffer], let outputNormals = state.slots[slot][normalBuffer] else {
                continue
            }
            var uniforms = state.layout.uniforms
            uniforms.hasSkin = skin == nil ? 0 : 1
            // Same weights as the CPU path: the valid targets, in order.
            let validWeights = zip(entry.morphTargets, weights + Array(repeating: 0, count: max(0, entry.morphTargets.count - weights.count))).filter { $0.0.isValid(vertexCount: mesh.vertexCount) }.map(\.1)
            jobs.append(GPUDeformationJob(
                uniforms: uniforms,
                restPositions: restPositions,
                outputPositions: outputPositions,
                restNormals: restNormals,
                outputNormals: outputNormals,
                weights: validWeights.isEmpty ? [0] : validWeights,
                positionDeltas: state.positionDeltas,
                normalDeltas: state.normalDeltas,
                influences: skin == nil ? nil : state.influences,
                jointMatrices: skin?.jointMatrices() ?? [matrix_identity_float4x4]
            ))
            var deformedMesh = mesh
            deformedMesh.vertexBuffers = state.slots[slot]
            state.current = (revision, deformedMesh, skin == nil ? entry.worldTransform : matrix_identity_float4x4)
        }
        return jobs
    }
}

// Writes the deformed vertices before any pass draws them.
struct DeformationPass: Element {
    var jobs: [GPUDeformationJob]

    var body: some Element {
        get throws {
            let kernel = try DeformationShaders.shared()
            let placeholder = try DeformationShaders.placeholderBuffer()
            return try ComputePass(label: "GPU Deformation") {
                try ComputePipeline(label: "GPU Deformation", computeKernel: kernel) {
                    ForEach(Array(jobs.enumerated()), id: \.offset) { _, job in
                        try ComputeDispatch(
                            threadsPerGrid: MTLSize(width: Int(job.uniforms.vertexCount), height: 1, depth: 1),
                            threadsPerThreadgroup: MTLSize(width: 64, height: 1, depth: 1)
                        )
                        .parameters { parameters in
                            parameters.set("uniforms", value: job.uniforms)
                            parameters.set("restPositions", buffer: job.restPositions)
                            parameters.set("outputPositions", buffer: job.outputPositions)
                            parameters.set("restNormals", buffer: job.restNormals)
                            parameters.set("outputNormals", buffer: job.outputNormals)
                            parameters.set("weights", values: job.weights)
                            parameters.set("positionDeltas", buffer: job.positionDeltas ?? placeholder)
                            parameters.set("normalDeltas", buffer: job.normalDeltas ?? placeholder)
                            parameters.set("influences", buffer: job.influences ?? placeholder)
                            parameters.set("jointMatrices", values: job.jointMatrices)
                        }
                    }
                }
            }
            // Shadow casters, the scene pass and pre-passes read the deformed vertices.
            .barrierAfterPass(after: .dispatch, beforeQueueStages: [.vertex, .dispatch])
        }
    }
}

enum DeformationShaders {
    nonisolated(unsafe) private static var cached: ComputeKernel?
    nonisolated(unsafe) private static var cachedPlaceholder: MTLBuffer?
    private static let lock = NSLock()

    static func shared() throws -> ComputeKernel {
        lock.lock()
        defer { lock.unlock() }
        if let cached {
            return cached
        }
        let kernel: ComputeKernel = try ShaderLibrary(bundle: .sceneSprocketsShaders()).namespaced("Deformation").deform_vertices
        cached = kernel
        return kernel
    }

    // Bound where a mesh has no morph deltas or skin; the kernel does not read it then.
    static func placeholderBuffer() throws -> MTLBuffer {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPlaceholder {
            return cachedPlaceholder
        }
        guard let buffer = _MTLCreateSystemDefaultDevice().makeBuffer(length: 64, options: .storageModeShared) else {
            throw MetalSupportError.resourceCreationFailure("Failed to create GPU deformation placeholder buffer")
        }
        buffer.label = "GPU Deformation Placeholder"
        cachedPlaceholder = buffer
        return buffer
    }
}
