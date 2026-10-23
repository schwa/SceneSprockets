import GeometryLite3D
import Interaction3D
import MetalSprockets
import MetalSprocketsUI
import simd
import SwiftUI

// Per-frame callbacks, like SCNSceneRendererDelegate. All are optional.
@MainActor
public protocol SceneViewDelegate: AnyObject {
    // Before actions run. Change the scene here.
    func sceneView(updateAtTime time: Float, deltaTime: Float)
    // After actions ran, before constraints.
    func sceneView(didApplyActionsAtTime time: Float)
    // After constraints ran, just before the frame is drawn.
    func sceneView(didApplyConstraintsAtTime time: Float)
}

public extension SceneViewDelegate {
    func sceneView(updateAtTime time: Float, deltaTime: Float) {}
    func sceneView(didApplyActionsAtTime time: Float) {}
    func sceneView(didApplyConstraintsAtTime time: Float) {}
}

// Shows a scene graph, like SceneKit's SwiftUI SceneView. Runs node actions every frame.
public struct SceneView: View {
    public struct Options: OptionSet, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        // Orbit, pan and zoom with the mouse or trackpad. The point of view's node is not moved.
        public static let allowsCameraControl = Options(rawValue: 1 << 0)
        // Adds a white directional light at the camera when the scene has no lights.
        public static let autoenablesDefaultLighting = Options(rawValue: 1 << 1)
        // Overlays frame rate and scene statistics, like SCNView.showsStatistics.
        public static let showsStatistics = Options(rawValue: 1 << 2)
        // Keeps the drawable readable (framebufferOnly false) even without post passes, for example to inspect it in a
        // GPU capture. Costs some bandwidth.
        public static let disablesFramebufferOnly = Options(rawValue: 1 << 3)
    }

    private let sceneGraph: SceneGraph
    private let pointOfView: SceneGraph.Node?
    private let options: Options
    private let renderers: [any SceneGraphMaterialRenderer]
    private weak var delegate: (any SceneViewDelegate)?
    private let isPlaying: Bool
    private let shadows: SceneGraphShadows?
    private let audio: SceneAudio?
    private let externalCameraMatrix: Binding<simd_float4x4?>?
    private let onTap: ((SceneGraph.Hit?) -> Void)?
    private let hitTestCategoryBitMask: UInt
    private let manipulator: (any SceneViewManipulator)?
    private let decorations: ((SceneGraphRenderContext, SIMD2<Float>) throws -> AnyElement?)?
    private let defaultCamera: Camera
    private let cameraOverride: Camera?
    private let overlay: ((SceneViewport) throws -> AnyElement?)?

    @Environment(\.displayScale) private var displayScale
    // Decided at the first change of each drag: whether it started on the manipulator.
    @State private var manipulatorDragClaim: Bool?

    @State private var internalCameraMatrix: simd_float4x4?
    @State private var viewSize: CGSize = .zero
    // Fixed when the view appears: recomputing it from the bounds every frame makes the camera chase objects that
    // move far away (for example a body falling forever).
    @State private var orbitTarget: SIMD3<Float>?
    @State private var clock = SceneClock()

    // `pointOfView` defaults to the first camera node; with no camera node a camera framing the scene is used.
    // `renderers` draw the material families, e.g. BlinnPhongMaterialRenderer (SceneSprocketsBlinnPhong) or
    // PBRMaterialRenderer (SceneSprocketsPBR). `isPlaying` false freezes scene time (delegate time and actions).
    // `cameraMatrix` exposes the camera-control transform (nil: start from the point of view; set nil to reset).
    // Without `.allowsCameraControl`, a non-nil `cameraMatrix` still sets the camera, for callers with their own
    // camera control.
    // `onTap` gets the nearest hit under a tap or click. `manipulator` draws over the scene and takes drags that start
    // on it (for example a transform gizmo). `decorations` draws extra content in the scene pass after the meshes, with
    // the scene's reversed depth (compare `.greater`), given the frame's context and drawable size in pixels; for
    // editor aids such as grids that objects should hide.
    public init(
        sceneGraph: SceneGraph,
        pointOfView: SceneGraph.Node? = nil,
        options: Options = [],
        renderers: [any SceneGraphMaterialRenderer],
        delegate: (any SceneViewDelegate)? = nil,
        isPlaying: Bool = true,
        shadows: SceneGraphShadows? = nil,
        audio: SceneAudio? = nil,
        cameraMatrix: Binding<simd_float4x4?>? = nil,
        hitTestCategoryBitMask: UInt = .max,
        // Used when the scene has no camera node.
        defaultCamera: Camera = SceneView.defaultCamera,
        // Replaces the camera node's camera (projection, masks), for editor cameras. The transform still comes from
        // `cameraMatrix` or the node.
        camera: Camera? = nil,
        manipulator: (any SceneViewManipulator)? = nil,
        onTap: ((SceneGraph.Hit?) -> Void)? = nil,
        // After `onTap`, so a trailing closure still means `onTap`.
        decorations: ((SceneGraphRenderContext, SIMD2<Float>) throws -> AnyElement?)? = nil,
        // Passes after the scene and before the manipulator, such as selection outlines. They see the finished color
        // and can load the scene depth (reversed: nearer is greater). Start passes that read the drawable with a barrier.
        overlay: ((SceneViewport) throws -> AnyElement?)? = nil
    ) {
        self.overlay = overlay
        self.decorations = decorations
        self.defaultCamera = defaultCamera
        self.cameraOverride = camera
        self.sceneGraph = sceneGraph
        self.pointOfView = pointOfView
        self.options = options
        self.renderers = renderers
        self.delegate = delegate
        self.isPlaying = isPlaying
        self.shadows = shadows
        self.audio = audio
        self.externalCameraMatrix = cameraMatrix
        self.onTap = onTap
        self.hitTestCategoryBitMask = hitTestCategoryBitMask
        self.manipulator = manipulator
    }

    private var cameraMatrix: simd_float4x4? {
        externalCameraMatrix?.wrappedValue ?? internalCameraMatrix
    }

    public var body: some View {
        RenderView { context, size in
            let (time, deltaTime) = clock.advance(to: context.frameUniforms.time, isPaused: !isPlaying)
            let _ = delegate?.sceneView(updateAtTime: time, deltaTime: deltaTime)
            let _ = sceneGraph.advanceActions(by: deltaTime)
            let _ = sceneGraph.advanceParticles(by: deltaTime)
            let _ = delegate?.sceneView(didApplyActionsAtTime: time)
            let _ = sceneGraph.applyConstraints(pointOfView: currentCameraMatrix, deltaTime: deltaTime)
            let _ = delegate?.sceneView(didApplyConstraintsAtTime: time)
            // The listener is the camera. Audio failures leave the frame drawing.
            let _ = try? audio?.update(sceneGraph: sceneGraph, listener: currentCameraMatrix)
            SceneGraphElement(
                sceneGraph: sceneGraph,
                camera: pointOfView,
                cameraMatrix: usesFreeCamera ? cameraMatrix ?? viewpoint.matrix : nil,
                aspectRatio: size.height > 0 ? Float(size.width / size.height) : 1,
                renderers: renderers,
                defaultCamera: defaultCamera,
                cameraOverride: cameraOverride,
                defaultLight: options.contains(.autoenablesDefaultLighting) ? Light(type: .directional, color: [1, 1, 1], intensity: 1) : nil,
                shadows: shadows,
                storesDepth: overlay != nil,
                decorations: decorations.map { decorations in
                    { context in try decorations(context, SIMD2<Float>(Float(size.width), Float(size.height))) }
                }
            )
            if let overlay, let viewport = viewport(drawableSize: size), let element = try overlay(viewport) {
                element
            }
            if let overlay = manipulatorOverlay(drawableSize: size) {
                ManipulatorOverlayPass(content: overlay)
            }
        }
        .metalDepthStencilPixelFormat(.depth32Float)
        // Shadows and fog change the drawable from compute passes that also read depth.
        .metalFramebufferOnly(!needsPostPasses && !options.contains(.disablesFramebufferOnly))
        .metalDepthStencilAttachmentTextureUsage(needsPostPasses ? [.renderTarget, .shaderRead] : [.renderTarget])
        .metalDepthStencilStorageMode(needsPostPasses || overlay != nil ? .private : .memoryless)
        .modifier(CameraControl(isEnabled: options.contains(.allowsCameraControl), cameraMatrix: cameraBinding, target: orbitTarget ?? viewpoint.target))
        // Camera control leaves drags that start on the manipulator alone.
        .interactionDragFilter { location in !manipulatorHit(at: location) }
        .onAppear {
            orbitTarget = viewpoint.target
        }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { viewSize = $0 }
        .onContinuousHover { phase in
            // Hover only updates highlighting; drags are routed at drag start.
            guard manipulatorDragClaim != true else {
                return
            }
            switch phase {
            case .active(let location):
                _ = manipulatorHit(at: location)
            case .ended:
                _ = manipulatorHit(at: CGPoint(x: -1_000_000, y: -1_000_000))
            }
        }
        .simultaneousGesture(manipulatorDrag, including: manipulator != nil ? .all : .subviews)
        .onTapGesture { location in
            guard let onTap else {
                return
            }
            onTap(hit(at: location))
        }
        .overlay(alignment: .bottomLeading) {
            if options.contains(.showsStatistics) {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let statistics = sceneGraph.statistics
                    Text("\(clock.framesPerSecond, format: .number.precision(.fractionLength(0))) fps \u{00B7} \(statistics.meshCount) meshes \u{00B7} \(statistics.triangleCount) triangles \u{00B7} \(statistics.lightCount) lights")
                        .font(.caption.monospacedDigit())
                        .padding(4)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding(8)
                }
            }
        }
    }

    private var manipulatorDrag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard let manipulator, let viewport = viewport() else {
                    return
                }
                if manipulatorDragClaim == nil {
                    let claimed = manipulatorHit(at: value.startLocation)
                    manipulatorDragClaim = claimed
                    if claimed {
                        manipulator.beginDrag(at: [Float(value.startLocation.x), Float(value.startLocation.y)], viewport: viewport)
                    }
                }
                if manipulatorDragClaim == true {
                    manipulator.drag(to: [Float(value.location.x), Float(value.location.y)], viewport: viewport)
                }
            }
            .onEnded { _ in
                if manipulatorDragClaim == true {
                    manipulator?.endDrag()
                }
                manipulatorDragClaim = nil
            }
    }

    private func manipulatorHit(at location: CGPoint) -> Bool {
        guard let manipulator, let viewport = viewport() else {
            return false
        }
        return manipulator.hitTest([Float(location.x), Float(location.y)], viewport: viewport)
    }

    private func manipulatorOverlay(drawableSize: CGSize) -> AnyElement? {
        guard let manipulator, let viewport = viewport(drawableSize: drawableSize) else {
            return nil
        }
        return try? manipulator.overlay(viewport: viewport)
    }

    // The camera the frame is drawn with. `drawableSize` defaults to the view size at the display scale.
    private func viewport(drawableSize: CGSize? = nil) -> SceneViewport? {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let projection = activeCamera.projection
        let size = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))
        let matrix = projection.projectionMatrix(aspectRatio: size.x / size.y)
        let drawable = drawableSize.map { SIMD2<Float>(Float($0.width), Float($0.height)) } ?? size * Float(displayScale)
        return SceneViewport(cameraMatrix: currentCameraMatrix, projectionMatrix: projection.isReversedDepth ? .reversedDepth * matrix : matrix, viewSize: size, drawableSize: drawable)
    }

    private var activeCameraNode: (node: SceneGraph.Node, camera: Camera, worldTransform: simd_float4x4)? {
        let cameras = sceneGraph.cameraNodes()
        guard let entry = pointOfView.flatMap({ node in cameras.first { $0.node === node } }) ?? cameras.first else {
            return nil
        }
        return (entry.node, entry.camera, entry.worldTransform)
    }

    private var activeCamera: Camera {
        cameraOverride ?? activeCameraNode?.camera ?? defaultCamera
    }

    // Read when SwiftUI updates the view; setting fog later needs a view update to take effect.
    private var needsPostPasses: Bool {
        shadows != nil || sceneGraph.fog != nil || sceneGraph.postProcessing != nil
    }

    private var cameraBinding: Binding<simd_float4x4> {
        Binding(get: { cameraMatrix ?? viewpoint.matrix }, set: { newValue in
            if let externalCameraMatrix {
                externalCameraMatrix.wrappedValue = newValue
            } else {
                internalCameraMatrix = newValue
            }
        })
    }

    public static let defaultCamera = Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(60), depthMode: .standard(zClip: 0.01 ... 1000)))

    // The starting camera transform, and the point camera control orbits around.
    private var viewpoint: (matrix: simd_float4x4, target: SIMD3<Float>) {
        let bounds = sceneGraph.bounds
        let center = bounds.map { ($0.min + $0.max) / 2 } ?? .zero
        if let entry = activeCameraNode {
            return (entry.worldTransform, center)
        }
        let radius = bounds.map { max(simd_length($0.max - $0.min) / 2, 0.5) } ?? 1
        return (LookAt(position: center + [0, radius * 0.5, radius * 2.5], target: center, up: [0, 1, 0]).cameraMatrix, center)
    }

    // Drawn from `cameraMatrix` rather than a camera node: with camera control, or when the caller sets the matrix
    // (for its own camera control).
    private var usesFreeCamera: Bool {
        options.contains(.allowsCameraControl) || externalCameraMatrix?.wrappedValue != nil
    }

    // The world transform the frame is drawn from.
    private var currentCameraMatrix: simd_float4x4 {
        if usesFreeCamera {
            return cameraMatrix ?? viewpoint.matrix
        }
        return activeCameraNode?.worldTransform ?? viewpoint.matrix
    }

    private func hit(at location: CGPoint) -> SceneGraph.Hit? {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let camera = activeCamera
        let matrix = currentCameraMatrix
        let size = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))
        let ray = ViewProjection(viewMatrix: matrix.inverse, projection: camera.projection, viewSize: size).ray(through: [Float(location.x), Float(location.y)])
        // Like SceneKit, taps only hit nodes the camera can see, further limited by hitTestCategoryBitMask.
        return sceneGraph.hitTest(ray, categoryBitMask: camera.categoryBitMask & hitTestCategoryBitMask).first
    }
}

// Scene time that stops while paused. A class so the render closure can advance it without invalidating the view.
final class SceneClock {
    private var lastFrameTime: Float?
    private var time: Float = 0
    // Smoothed from real frame intervals, paused or not.
    private(set) var framesPerSecond: Double = 0

    func advance(to frameTime: Float, isPaused: Bool) -> (time: Float, deltaTime: Float) {
        let interval = max(frameTime - (lastFrameTime ?? frameTime), 0)
        if interval > 0 {
            framesPerSecond = framesPerSecond == 0 ? 1 / Double(interval) : framesPerSecond * 0.9 + 0.1 / Double(interval)
        }
        // Clamped, so a stall does not jump animations.
        let deltaTime = isPaused ? 0 : min(interval, 1.0 / 15)
        lastFrameTime = frameTime
        time += deltaTime
        return (time, deltaTime)
    }
}

private struct CameraControl: ViewModifier {
    var isEnabled: Bool
    @Binding var cameraMatrix: simd_float4x4
    var target: SIMD3<Float>

    func body(content: Content) -> some View {
        if isEnabled {
            content.interactiveCamera(cameraMatrix: $cameraMatrix, target: target)
        } else {
            content
        }
    }
}

