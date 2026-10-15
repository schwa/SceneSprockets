import GeometryLite3D
import simd

extension SceneGraph {
    public struct TRS: Sendable, Equatable {
        public var translation: SIMD3<Float>
        public var rotation: simd_quatf
        public var scale: SIMD3<Float>

        public static let identity = Self()

        public init(translation: SIMD3<Float> = .zero, rotation: simd_quatf = simd_quatf(ix: 0, iy: 0, iz: 0, r: 1), scale: SIMD3<Float> = .one) {
            self.translation = translation
            self.rotation = rotation
            self.scale = scale
        }

        // Lossy for matrices with skew, perspective or negative scale; falls back to identity if not decomposable.
        public init(matrix: simd_float4x4) {
            guard let components = matrix.decompose else {
                self.init()
                return
            }
            self.init(translation: components.translation, rotation: components.rotation, scale: components.scale)
        }

        public var matrix: simd_float4x4 {
            var result = simd_float4x4(rotation)
            result.columns.0 *= scale.x
            result.columns.1 *= scale.y
            result.columns.2 *= scale.z
            result.columns.3 = SIMD4(translation, 1)
            return result
        }
    }

    // A node's local transform: either a raw matrix or decomposed translation/rotation/scale.
    public enum LocalTransform: Sendable {
        case matrix(simd_float4x4)
        case trs(TRS)

        public var matrix: simd_float4x4 {
            switch self {
            case .matrix(let matrix):
                matrix
            case .trs(let trs):
                trs.matrix
            }
        }
    }
}
