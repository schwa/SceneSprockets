import GeometryLite3D
import simd

// The editor's camera. SceneView's camera control (Interaction3D) orbits `matrix` around `target`; framing moves both.
struct EditorCamera: Equatable {
    var matrix: simd_float4x4
    var target: SIMD3<Float> = .zero

    static let distanceRange: ClosedRange<Float> = 0.05 ... 10_000

    init() {
        let yaw: Float = .pi / 6
        let pitch: Float = -.pi / 8
        let direction = SIMD3<Float>(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
        matrix = LookAt(position: direction * 8, target: .zero, up: [0, 1, 0]).cameraMatrix
    }

    // Keeps the view direction, and fits a sphere around `bounds` in a view `fieldOfView` degrees high.
    mutating func frame(_ bounds: BoundingBox3D, fieldOfView: Float) {
        target = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 0.1)
        let halfAngle = fieldOfView.clamped(to: 1 ... 179) * .pi / 360
        let distance = (radius / sin(halfAngle) * 1.1).clamped(to: Self.distanceRange)
        // The camera looks down -Z, so +Z points back from the target to the camera.
        let backward = simd_normalize(matrix.columns.2.xyz)
        matrix = LookAt(position: target + backward * distance, target: target, up: [0, 1, 0]).cameraMatrix
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}
