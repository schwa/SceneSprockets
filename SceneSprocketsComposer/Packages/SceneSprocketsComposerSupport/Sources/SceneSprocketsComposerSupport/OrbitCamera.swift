import GeometryLite3D
import simd

// The editor's camera: orbits `target` at `distance`. Yaw turns about +Y, pitch tilts up and down (radians).
struct OrbitCamera: Equatable {
    var target: SIMD3<Float> = .zero
    var yaw: Float = .pi / 6
    var pitch: Float = -.pi / 8
    var distance: Float = 8

    static let pitchLimit: Float = .pi / 2 - 0.01
    static let distanceRange: ClosedRange<Float> = 0.05 ... 10_000

    var position: SIMD3<Float> {
        let direction = SIMD3<Float>(cos(pitch) * sin(yaw), -sin(pitch), cos(pitch) * cos(yaw))
        return target + direction * distance
    }

    var matrix: simd_float4x4 {
        LookAt(position: position, target: target, up: [0, 1, 0]).cameraMatrix
    }

    // `delta` in view points.
    mutating func orbit(by delta: SIMD2<Float>) {
        let radiansPerPoint: Float = 0.01
        yaw -= delta.x * radiansPerPoint
        pitch = (pitch - delta.y * radiansPerPoint).clamped(to: -Self.pitchLimit ... Self.pitchLimit)
    }

    // Moves the target in the view plane; `delta` in view points, scaled so the scene roughly follows the pointer.
    mutating func pan(by delta: SIMD2<Float>) {
        let cameraMatrix = matrix
        let right = cameraMatrix.columns.0.xyz
        let up = cameraMatrix.columns.1.xyz
        let worldPerPoint = distance * 0.002
        target += (-right * delta.x + up * delta.y) * worldPerPoint
    }

    // Positive `amount` moves closer.
    mutating func zoom(by amount: Float) {
        distance = (distance * exp(-amount)).clamped(to: Self.distanceRange)
    }

    // Keeps the direction, and fits a sphere around `bounds` in a view `fieldOfView` degrees high.
    mutating func frame(_ bounds: BoundingBox3D, fieldOfView: Float) {
        target = (bounds.min + bounds.max) / 2
        let radius = max(simd_length(bounds.max - bounds.min) / 2, 0.1)
        let halfAngle = fieldOfView.clamped(to: 1 ... 179) * .pi / 360
        distance = (radius / sin(halfAngle) * 1.1).clamped(to: Self.distanceRange)
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
