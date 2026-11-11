import GeometryLite3D
import simd

extension SceneGraph {
    /// A node's local transform: either a raw matrix or decomposed translation/rotation/scale.
    public enum LocalTransform: Sendable {
        /// A matrix.
        case matrix(simd_float4x4)
        /// Translation, rotation and scale.
        case trs(Transform3D)

        /// The transform as a matrix.
        public var matrix: simd_float4x4 {
            switch self {
            case .matrix(let matrix):
                matrix
            case .trs(let trs):
                trs.matrix
            }
        }

        /// The transform as translation, rotation and scale. A matrix is decomposed.
        public var trs: Transform3D {
            switch self {
            case .trs(let trs):
                trs
            case .matrix(let matrix):
                Transform3D(nearestTo: matrix)
            }
        }
    }
}

extension Transform3D {
    // Unlike GeometryLite3D's init?(decomposing:), keeps the nearest TRS for matrices with skew, perspective or negative
    // scale, and falls back to identity if the matrix does not decompose.
    package init(nearestTo matrix: simd_float4x4) {
        guard let components = matrix.decompose else {
            self = .identity
            return
        }
        self.init(translation: components.translation, rotation: components.rotation, scale: components.scale)
    }
}
