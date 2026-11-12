import GeometryLite3D
import simd

extension SceneGraph {
    /// An immutable copy of what rendering reads from a scene graph, like SceneKit's presentation tree (#386).
    ///
    /// Make one with ``presentation()`` on the thread that edits the graph, then hand it to a renderer on any thread:
    /// it holds values, not live node data. Meshes, materials and particle systems are shared references; the
    /// snapshot does not copy their contents.
    public struct Presentation {
        /// A light with its world transform and its node's light category mask.
        public struct LightEntry {
            public var nodeID: Node.ID
            public var worldTransform: simd_float4x4
            public var light: Light
            public var lightCategoryBitMask: UInt
        }

        /// A camera with its world transform.
        public struct CameraEntry {
            public var nodeID: Node.ID
            public var worldTransform: simd_float4x4
            public var camera: Camera
        }

        /// Node text with its world transform and its node's category mask.
        public struct TextEntry {
            public var text: SceneText
            public var worldTransform: simd_float4x4
            public var categoryBitMask: UInt
        }

        /// The graph's revision when the snapshot was made.
        public var revision: Revision
        /// One entry for each visible submesh.
        public var meshes: [MeshEntry]
        public var lights: [LightEntry]
        public var cameras: [CameraEntry]
        public var texts: [TextEntry]
        /// This frame's edits of every particle system on an active node, hidden or not, each once. Made fresh by each
        /// ``SceneGraph/presentation()`` call, which takes the time advanced since the previous call.
        public var particleFrames: [SceneParticleSystem.Frame]
        /// Indices into ``particleFrames`` of the systems on visible nodes.
        public var visibleParticleIndices: [Int]
        public var environment: Environment
        public var fog: Fog?
        public var postProcessing: PostProcessing?
        /// World-space bounds of every mesh.
        public var bounds: BoundingBox3D?
    }

    /// Returns a snapshot of what rendering reads. Call it on the thread that edits the graph. Parts that only depend
    /// on the revision are reused until it changes.
    public func presentation() -> Presentation {
        let revision = self.revision
        let parts: PresentationParts
        if let presentationCache, presentationCache.revision == revision {
            parts = presentationCache
        } else {
            parts = makePresentationParts(revision: revision)
            presentationCache = parts
        }
        return Presentation(
            revision: revision,
            meshes: parts.meshes,
            lights: parts.lights,
            cameras: parts.cameras,
            texts: parts.texts,
            particleFrames: parts.particleSystems.map { $0.makeFrame() },
            visibleParticleIndices: parts.visibleParticleIndices,
            environment: environment,
            fog: fog,
            postProcessing: postProcessing,
            bounds: parts.bounds
        )
    }

    // The revision-dependent part of a snapshot.
    struct PresentationParts {
        var revision: Revision
        var meshes: [MeshEntry]
        var lights: [Presentation.LightEntry]
        var cameras: [Presentation.CameraEntry]
        var texts: [Presentation.TextEntry]
        var particleSystems: [SceneParticleSystem]
        var visibleParticleIndices: [Int]
        var bounds: BoundingBox3D?
    }

    private func makePresentationParts(revision: Revision) -> PresentationParts {
        let flattened = flattened()
        var texts: [Presentation.TextEntry] = []
        visit { node, worldTransform in
            if let text = node.text, !text.string.isEmpty {
                texts.append(.init(text: text, worldTransform: worldTransform, categoryBitMask: node.categoryBitMask))
            }
        }
        let particleSystems = allParticleSystems()
        let visible = Set(visibleParticleSystems().map(ObjectIdentifier.init))
        return PresentationParts(
            revision: revision,
            meshes: flattened.meshes,
            lights: flattened.lights.map { .init(nodeID: $0.node.id, worldTransform: $0.worldTransform, light: $0.light, lightCategoryBitMask: $0.node.lightCategoryBitMask) },
            cameras: flattened.cameras.map { .init(nodeID: $0.node.id, worldTransform: $0.worldTransform, camera: $0.camera) },
            texts: texts,
            particleSystems: particleSystems,
            visibleParticleIndices: particleSystems.indices.filter { visible.contains(ObjectIdentifier(particleSystems[$0])) },
            bounds: bounds
        )
    }
}
