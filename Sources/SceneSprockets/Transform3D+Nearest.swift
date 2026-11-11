import GeometryLite3D
import simd

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
