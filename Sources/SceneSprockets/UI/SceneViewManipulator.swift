import GeometryLite3D
import MetalSprockets
import simd

/// The camera a SceneView draws with, for overlays and pointer input. Points are view coordinates (origin top-left,
/// y down); `drawableSize` is in pixels.
public struct SceneViewport {
    /// The camera's world transform.
    public var cameraMatrix: simd_float4x4
    /// Standard depth (near 0, far 1), whatever depth the scene itself uses.
    public var projectionMatrix: simd_float4x4
    /// The size of the view, in points.
    public var viewSize: SIMD2<Float>
    /// The size of the drawable, in pixels.
    public var drawableSize: SIMD2<Float>

    /// Creates a viewport.
    ///
    /// - Parameters:
    ///   - cameraMatrix: The camera's world transform.
    ///   - projectionMatrix: The projection, with standard depth.
    ///   - viewSize: The size of the view, in points.
    ///   - drawableSize: The size of the drawable, in pixels.
    public init(cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4, viewSize: SIMD2<Float>, drawableSize: SIMD2<Float>) {
        self.cameraMatrix = cameraMatrix
        self.projectionMatrix = projectionMatrix
        self.viewSize = viewSize
        self.drawableSize = drawableSize
    }

    /// The viewport `camera` sees from `cameraMatrix`, as SceneView draws and hit tests it (#240). Reversed-depth
    /// projections are converted to standard depth.
    public init(cameraMatrix: simd_float4x4, camera: Camera, viewSize: SIMD2<Float>, drawableSize: SIMD2<Float>) {
        let projection = camera.projection
        let matrix = projection.projectionMatrix(aspectRatio: viewSize.x / viewSize.y)
        self.init(cameraMatrix: cameraMatrix, projectionMatrix: projection.isReverseZ ? .reverseZ * matrix : matrix, viewSize: viewSize, drawableSize: drawableSize)
    }

    /// The view matrix: the inverse of ``cameraMatrix``.
    public var viewMatrix: simd_float4x4 {
        cameraMatrix.inverse
    }

    /// The view matrix without translation, for drawing camera-relative positions.
    ///
    /// It is the inverse of the camera's rotation alone, so it stays precise when the camera is far from the world
    /// origin.
    public var rotationOnlyViewMatrix: simd_float4x4 {
        var rotation = cameraMatrix
        rotation.columns.3 = [0, 0, 0, 1]
        return rotation.inverse
    }

    /// The view and projection, for projecting points and making rays.
    public var viewProjection: ViewProjection {
        ViewProjection(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, isReverseZ: false, viewSize: viewSize)
    }

    /// Returns the world-space ray through a point in view coordinates.
    public func ray(through point: SIMD2<Float>) -> Ray3D {
        viewProjection.ray(through: point)
    }

    /// The point in view coordinates and its depth; nil behind the camera.
    public func project(_ worldPoint: SIMD3<Float>) -> SIMD3<Float>? {
        viewProjection.project(worldPoint)
    }

    /// World units per view point at `worldPoint`, for things drawn at a constant size on screen.
    public func worldSizeOfPoint(at worldPoint: SIMD3<Float>) -> Float {
        let right = simd_normalize(cameraMatrix.columns.0.xyz)
        // Camera-relative, so the size stays precise far from the world origin (#262).
        let relative = cameraRelative(worldPoint, to: cameraMatrix.columns.3.xyz)
        let viewProjection = ViewProjection(viewMatrix: rotationOnlyViewMatrix, projectionMatrix: projectionMatrix, isReverseZ: false, viewSize: viewSize)
        guard let a = viewProjection.project(relative), let b = viewProjection.project(relative + right) else {
            return 1
        }
        return 1 / max(simd_distance(a.xy, b.xy), .ulpOfOne)
    }
}

/// Something a SceneView draws on top of the scene and that can take pointer drags before camera control does, such
/// as a transform gizmo. SceneView asks `hitTest` at the start of each drag; a hit routes that drag here
/// and keeps camera control off it. It also asks while the pointer hovers, for highlighting.
@MainActor
public protocol SceneViewManipulator: AnyObject {
    /// Returns an element to draw after the scene, or `nil` to draw nothing.
    ///
    /// The element draws in its own render pass. The pass loads the scene's color and clears depth to 1, for standard
    /// depth.
    func overlay(viewport: SceneViewport) throws -> AnyElement?
    /// Returns whether a drag that starts at a point belongs to the manipulator. The method can update hover state.
    func hitTest(_ point: SIMD2<Float>, viewport: SceneViewport) -> Bool
    /// Starts a drag at a point that ``hitTest(_:viewport:)`` claimed.
    func beginDrag(at point: SIMD2<Float>, viewport: SceneViewport)
    /// Continues a drag to a point.
    func drag(to point: SIMD2<Float>, viewport: SceneViewport)
    /// Ends a drag.
    func endDrag()
    /// Returns whether a two-finger pinch and twist that starts at a point belongs to the manipulator.
    ///
    /// Two-finger gestures are available on iOS and visionOS. If the manipulator claims a gesture, camera control does
    /// not zoom with it. The default implementation returns false.
    func claimsTwoFingerGesture(at point: SIMD2<Float>, viewport: SceneViewport) -> Bool
    /// Starts a two-finger gesture that the manipulator claimed.
    func beginTwoFingerGesture(viewport: SceneViewport)
    /// Continues a two-finger gesture.
    ///
    /// - Parameters:
    ///   - scale: The pinch scale, relative to the start of the gesture.
    ///   - rotation: The twist angle in radians, clockwise on screen, relative to the start of the gesture.
    ///   - viewport: The camera and view size.
    func twoFingerGesture(scale: Float, rotation: Float, viewport: SceneViewport)
    /// Ends a two-finger gesture.
    func endTwoFingerGesture()
}

public extension SceneViewManipulator {
    func claimsTwoFingerGesture(at _: SIMD2<Float>, viewport _: SceneViewport) -> Bool {
        false
    }

    func beginTwoFingerGesture(viewport _: SceneViewport) {
    }

    func twoFingerGesture(scale _: Float, rotation _: Float, viewport _: SceneViewport) {
    }

    func endTwoFingerGesture() {
    }
}

/// A render pass that draws a manipulator's overlay over the finished scene.
///
/// The pass keeps the scene's color and clears depth, so the overlay is never hidden. `SceneView` uses it for its
/// `manipulator`. Use it after a ``SceneGraphElement`` in your own `RenderView`.
public struct ManipulatorOverlayPass: Element {
    var content: AnyElement

    /// Creates the pass, usually with the element that ``SceneViewManipulator/overlay(viewport:)`` returns.
    public init(content: AnyElement) {
        self.content = content
    }

    public var body: some Element {
        get throws {
            try RenderPass(label: "Manipulator") {
                // Metal 4 does not order passes: without this, blending loaded scene color that the scene pass (and
                // post passes) had not finished writing, and the overlay flickered with garbage tiles.
                QueueBarrier(after: [.fragment, .dispatch], before: .fragment)
                content
            }
            .renderPassDescriptorModifier { descriptor in
                descriptor.colorAttachments[0].loadAction = .load
                descriptor.depthAttachment.loadAction = .clear
                descriptor.depthAttachment.clearDepth = 1
                descriptor.depthAttachment.storeAction = .dontCare
            }
        }
    }
}
