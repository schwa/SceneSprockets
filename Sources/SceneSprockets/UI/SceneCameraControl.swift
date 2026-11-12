import Interaction3D
import simd
import SwiftUI

/// How ``SceneView``'s built-in camera control behaves, like SceneKit's `SCNCameraController`.
///
/// Set it with the `sceneCameraControl(_:)` view modifier. It only has an effect when camera control is on
/// (``SceneView/sceneCameraControl(_:)``). Set the orbit target with ``SceneView/sceneCamera(matrix:target:override:)``.
public struct SceneCameraControl: Sendable, Equatable {
    /// How a drag rotates the camera.
    public enum Mode: Sendable, Equatable {
        /// Yaw around the up axis and pitch toward or away from it. The horizon stays level.
        case turntable
        /// Free rotation, as if turning a ball under the cursor. The camera can roll.
        case arcball
    }

    /// How a drag rotates the camera.
    public var mode: Mode
    /// Multiplies the rotation for a drag. 1 is the default speed.
    public var rotationSpeed: Float
    /// Multiplies the zoom for a scroll or pinch. 1 is the default speed.
    public var zoomSpeed: Float
    /// Multiplies the pan for a drag. 1 is the default speed.
    public var panSpeed: Float
    /// The closest and farthest the camera can be from the target, or `nil` for no limit.
    public var distanceRange: ClosedRange<Float>?
    /// The lowest and highest angle, in radians, of the camera above the target's horizontal plane, or `nil` for no
    /// limit. For example, `0...(.pi / 2)` keeps the camera above the ground.
    public var pitchRange: ClosedRange<Float>?

    /// Creates a camera control configuration.
    ///
    /// - Parameters:
    ///   - mode: How a drag rotates the camera.
    ///   - rotationSpeed: Multiplies the rotation speed.
    ///   - zoomSpeed: Multiplies the zoom speed.
    ///   - panSpeed: Multiplies the pan speed.
    ///   - distanceRange: The camera's distance limits from the target.
    ///   - pitchRange: The camera's angle limits above the target's horizontal plane, in radians.
    public init(mode: Mode = .turntable, rotationSpeed: Float = 1, zoomSpeed: Float = 1, panSpeed: Float = 1, distanceRange: ClosedRange<Float>? = nil, pitchRange: ClosedRange<Float>? = nil) {
        self.mode = mode
        self.rotationSpeed = rotationSpeed
        self.zoomSpeed = zoomSpeed
        self.panSpeed = panSpeed
        self.distanceRange = distanceRange
        self.pitchRange = pitchRange
    }

    var interactionMode: InteractiveCameraMode {
        switch mode {
        case .turntable: .turntable()
        case .arcball: .arcball()
        }
    }

    var transforms: InteractionAxisTransforms {
        let base = interactionMode.defaultTransforms
        let rotation = Double(rotationSpeed), zoom = Double(zoomSpeed), pan = Double(panSpeed)
        return InteractionAxisTransforms(
            yaw: base.yawScale * rotation,
            pitch: base.pitchScale * rotation,
            zoom: base.zoomScale * zoom,
            pan: base.panScale * pan
        )
    }

    /// The camera matrix moved inside the limits, keeping its direction from the target where it can. Returns the
    /// matrix unchanged when it is already inside them.
    func clamped(_ cameraMatrix: simd_float4x4, target: SIMD3<Float>) -> simd_float4x4 {
        guard distanceRange != nil || pitchRange != nil else {
            return cameraMatrix
        }
        let eye = SIMD3<Float>(cameraMatrix.columns.3.x, cameraMatrix.columns.3.y, cameraMatrix.columns.3.z)
        let offset = eye - target
        let distance = simd_length(offset)
        guard distance > 1e-5 else {
            return cameraMatrix
        }
        var newDistance = distance
        if let distanceRange {
            newDistance = min(max(distance, distanceRange.lowerBound), distanceRange.upperBound)
        }
        let pitch = asin(min(max(offset.y / distance, -1), 1))
        var newPitch = pitch
        if let pitchRange {
            newPitch = min(max(pitch, pitchRange.lowerBound), pitchRange.upperBound)
        }
        guard newDistance != distance || newPitch != pitch else {
            return cameraMatrix
        }
        // Keep the heading around the up axis; straight up or down has none, so use the camera's own facing.
        var heading = SIMD2<Float>(offset.x, offset.z)
        if simd_length(heading) < 1e-5 {
            heading = -SIMD2<Float>(cameraMatrix.columns.2.x, cameraMatrix.columns.2.z)
        }
        heading = simd_length(heading) < 1e-5 ? [0, 1] : simd_normalize(heading)
        let direction = SIMD3<Float>(heading.x * cos(newPitch), sin(newPitch), heading.y * cos(newPitch))
        return Self.lookAt(eye: target + direction * newDistance, target: target)
    }

    // A camera at `eye` looking at `target` (-Z forward), with +Y up.
    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let back = simd_normalize(eye - target)
        var up = SIMD3<Float>(0, 1, 0)
        if abs(simd_dot(back, up)) > 0.999 {
            up = [0, 0, -1]
        }
        let right = simd_normalize(simd_cross(up, back))
        let trueUp = simd_cross(back, right)
        return simd_float4x4(columns: (SIMD4(right, 0), SIMD4(trueUp, 0), SIMD4(back, 0), SIMD4(eye, 1)))
    }
}

extension EnvironmentValues {
    @Entry var sceneCameraControl = SceneCameraControl()
}

public extension View {
    /// Sets how the built-in camera control of the ``SceneView``s in this view behaves.
    ///
    /// - Parameter configuration: The camera control configuration.
    /// - Returns: A view that uses `configuration` for camera control.
    func sceneCameraControl(_ configuration: SceneCameraControl) -> some View {
        environment(\.sceneCameraControl, configuration)
    }
}
