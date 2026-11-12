@testable import SceneSprockets
import simd
import Testing

// #312: configurable camera control keeps the camera inside its limits.

private func eye(_ matrix: simd_float4x4) -> SIMD3<Float> {
    [matrix.columns.3.x, matrix.columns.3.y, matrix.columns.3.z]
}

@Test
func cameraInsideLimitsIsUnchanged() {
    let control = CameraControl(distanceRange: 2...20, pitchRange: 0...1.2)
    let camera = CameraControl.lookAt(eye: [0, 2, 8], target: .zero)
    #expect(control.clamped(camera, target: .zero) == camera)
}

@Test
func cameraBelowTheGroundIsLiftedToTheLowestPitch() {
    let control = CameraControl(pitchRange: 0...(.pi / 2))
    let target: SIMD3<Float> = [1, 0, 0]
    let camera = CameraControl.lookAt(eye: target + [0, -3, 4], target: target)
    let clamped = control.clamped(camera, target: target)
    let offset = eye(clamped) - target
    #expect(abs(offset.y) < 1e-4)
    #expect(abs(simd_length(offset) - 5) < 1e-4)
    // Same heading: still in front of the target along +Z.
    #expect(offset.z > 4.9)
    // Still looking at the target (-Z of the camera points at it).
    let forward = -SIMD3<Float>(clamped.columns.2.x, clamped.columns.2.y, clamped.columns.2.z)
    #expect(simd_distance(forward, simd_normalize(target - eye(clamped))) < 1e-4)
}

@Test
func zoomIsLimitedToTheDistanceRange() {
    let control = CameraControl(distanceRange: 3...10)
    let near = CameraControl.lookAt(eye: [0, 0, 1], target: .zero)
    #expect(abs(simd_length(eye(control.clamped(near, target: .zero))) - 3) < 1e-4)
    let far = CameraControl.lookAt(eye: [0, 30, 40], target: .zero)
    let clampedFar = eye(control.clamped(far, target: .zero))
    #expect(abs(simd_length(clampedFar) - 10) < 1e-4)
    // Only the distance changes: same direction.
    #expect(simd_distance(simd_normalize(clampedFar), simd_normalize([0, 30, 40])) < 1e-4)
}

@Test
func speedsScaleTheDefaultTransforms() {
    let base = CameraControl().transforms
    let fast = CameraControl(rotationSpeed: 2, zoomSpeed: 3, panSpeed: 4).transforms
    #expect(fast.yaw(10) == base.yaw(10) * 2)
    #expect(fast.pitch(10) == base.pitch(10) * 2)
    #expect(fast.zoom(10) == base.zoom(10) * 3)
    #expect(fast.pan([10, 5]) == base.pan([10, 5]) * 4)
}
