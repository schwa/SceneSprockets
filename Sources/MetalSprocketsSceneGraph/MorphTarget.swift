import simd

extension SceneGraph {
    // Per-vertex offsets for one blend shape. Arrays are indexed like the mesh's vertices; empty means no offset.
    // Offsets from the base mesh make weights behave like SCNMorpher's .normalized mode: base + sum of weight * offset
    // equals (1 - sum of weights) * base + sum of weight * target.
    public struct MorphTarget: Sendable, Equatable {
        public var name: String?
        public var positionDeltas: [SIMD3<Float>]
        public var normalDeltas: [SIMD3<Float>]
        public var tangentDeltas: [SIMD3<Float>]

        public init(name: String? = nil, positionDeltas: [SIMD3<Float>] = [], normalDeltas: [SIMD3<Float>] = [], tangentDeltas: [SIMD3<Float>] = []) {
            self.name = name
            self.positionDeltas = positionDeltas
            self.normalDeltas = normalDeltas
            self.tangentDeltas = tangentDeltas
        }

        public func isValid(vertexCount: Int) -> Bool {
            [positionDeltas, normalDeltas, tangentDeltas].allSatisfy { $0.isEmpty || $0.count == vertexCount }
        }
    }
}

extension SceneGraph.Node {
    // The weight of the first morph target named `name`; nil when there is none. Like SCNMorpher.weight(forTargetNamed:).
    public func morphWeight(forTargetNamed name: String) -> Float? {
        guard let index = morphTargets.firstIndex(where: { $0.name == name }) else {
            return nil
        }
        return index < morphWeights.count ? morphWeights[index] : 0
    }

    // Sets the weight of the first morph target named `name`, growing morphWeights if needed. Does nothing when no
    // target has that name.
    public func setMorphWeight(_ weight: Float, forTargetNamed name: String) {
        guard let index = morphTargets.firstIndex(where: { $0.name == name }) else {
            return
        }
        var weights = morphWeights
        if weights.count <= index {
            weights += Array(repeating: 0, count: index + 1 - weights.count)
        }
        weights[index] = weight
        morphWeights = weights
    }
}
