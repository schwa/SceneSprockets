import GeometryLite3D
import MetalSprockets
import simd

// The camera a SceneView draws with, for overlays and pointer input. Points are view coordinates (origin top-left,
// y down); `drawableSize` is in pixels.
public struct SceneViewport {
    public var cameraMatrix: simd_float4x4
    // Standard depth (near 0, far 1), whatever depth the scene itself uses.
    public var projectionMatrix: simd_float4x4
    public var viewSize: SIMD2<Float>
    public var drawableSize: SIMD2<Float>

    public init(cameraMatrix: simd_float4x4, projectionMatrix: simd_float4x4, viewSize: SIMD2<Float>, drawableSize: SIMD2<Float>) {
        self.cameraMatrix = cameraMatrix
        self.projectionMatrix = projectionMatrix
        self.viewSize = viewSize
        self.drawableSize = drawableSize
    }

    public var viewMatrix: simd_float4x4 {
        cameraMatrix.inverse
    }

    public var viewProjection: ViewProjection {
        ViewProjection(viewMatrix: viewMatrix, projectionMatrix: projectionMatrix, isReversedDepth: false, viewSize: viewSize)
    }

    public func ray(through point: SIMD2<Float>) -> Ray3D {
        viewProjection.ray(through: point)
    }

    // The point in view coordinates and its depth; nil behind the camera.
    public func project(_ worldPoint: SIMD3<Float>) -> SIMD3<Float>? {
        viewProjection.project(worldPoint)
    }

    // World units per view point at `worldPoint`, for things drawn at a constant size on screen.
    public func worldSizeOfPoint(at worldPoint: SIMD3<Float>) -> Float {
        let right = simd_normalize(cameraMatrix.columns.0.xyz)
        guard let a = project(worldPoint), let b = project(worldPoint + right) else {
            return 1
        }
        return 1 / max(simd_distance(a.xy, b.xy), .ulpOfOne)
    }
}

// Something a SceneView draws on top of the scene and that can take pointer drags before camera control does, such
// as a transform gizmo. SceneView asks `hitTest` while the pointer hovers; a hit routes the next drag here.
@MainActor
public protocol SceneViewManipulator: AnyObject {
    // Drawn after the scene, in its own render pass that loads the scene's color and clears depth to 1 (standard).
    func overlay(viewport: SceneViewport) throws -> AnyElement?
    // Whether a drag starting at `point` belongs to the manipulator. May update hover state.
    func hitTest(_ point: SIMD2<Float>, viewport: SceneViewport) -> Bool
    func beginDrag(at point: SIMD2<Float>, viewport: SceneViewport)
    func drag(to point: SIMD2<Float>, viewport: SceneViewport)
    func endDrag()
}

// The manipulator's overlay over the finished scene: keeps the color, clears depth so it is never hidden.
struct ManipulatorOverlayPass: Element {
    var content: AnyElement

    var body: some Element {
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
