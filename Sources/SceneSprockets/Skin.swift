import simd

extension SceneGraph {
    /// The joints that deform a skinned mesh.
    ///
    /// Joints are ordinary nodes in the graph, so you can animate them like other nodes. Several meshes can share a skin.
    public final class Skin {
        /// The joint nodes. A ``SkinVertex`` refers to them by index.
        public var joints: [Node]
        /// For each joint, the matrix from model space to the joint's space in the bind pose.
        public var inverseBindMatrices: [simd_float4x4]

        /// Creates a skin. There must be one inverse bind matrix for each joint.
        public init(joints: [Node], inverseBindMatrices: [simd_float4x4]) {
            self.joints = joints
            self.inverseBindMatrices = inverseBindMatrices
        }

        /// One matrix per joint: the joint's world transform times its inverse bind matrix.
        public func jointMatrices() -> [simd_float4x4] {
            zip(joints, inverseBindMatrices).map { $0.worldTransform * $1 }
        }
    }

    /// Up to four joint influences for one vertex.
    public struct SkinVertex: Sendable, Equatable {
        /// The indices of the joints in ``Skin/joints``.
        public var joints: SIMD4<UInt16>
        /// The weight of each joint. The weights add up to 1.
        public var weights: SIMD4<Float>

        /// Creates the joint influences for a vertex.
        public init(joints: SIMD4<UInt16>, weights: SIMD4<Float>) {
            self.joints = joints
            self.weights = weights
        }
    }
}
