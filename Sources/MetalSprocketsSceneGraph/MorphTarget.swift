import simd

extension SceneGraph {
    // Per-vertex offsets for one blend shape. Arrays are indexed like the mesh's vertices; empty means no offset.
    public struct MorphTarget: Sendable, Equatable {
        public var positionDeltas: [SIMD3<Float>]
        public var normalDeltas: [SIMD3<Float>]
        public var tangentDeltas: [SIMD3<Float>]

        public init(positionDeltas: [SIMD3<Float>] = [], normalDeltas: [SIMD3<Float>] = [], tangentDeltas: [SIMD3<Float>] = []) {
            self.positionDeltas = positionDeltas
            self.normalDeltas = normalDeltas
            self.tangentDeltas = tangentDeltas
        }

        public func isValid(vertexCount: Int) -> Bool {
            [positionDeltas, normalDeltas, tangentDeltas].allSatisfy { $0.isEmpty || $0.count == vertexCount }
        }
    }
}
