import simd

extension SceneGraph {
    // Joints are nodes in the graph; a skin can be shared by several meshes.
    public final class Skin {
        public var joints: [Node]
        public var inverseBindMatrices: [simd_float4x4]

        public init(joints: [Node], inverseBindMatrices: [simd_float4x4]) {
            self.joints = joints
            self.inverseBindMatrices = inverseBindMatrices
        }

        // One matrix per joint: the joint's world transform times its inverse bind matrix.
        public func jointMatrices() -> [simd_float4x4] {
            zip(joints, inverseBindMatrices).map { $0.worldTransform * $1 }
        }
    }

    // Up to four joint influences for one vertex. Joint values index Skin.joints.
    public struct SkinVertex: Sendable, Equatable {
        public var joints: SIMD4<UInt16>
        public var weights: SIMD4<Float>

        public init(joints: SIMD4<UInt16>, weights: SIMD4<Float>) {
            self.joints = joints
            self.weights = weights
        }
    }
}
