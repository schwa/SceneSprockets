import GeometryLite3D
import Interaction3D
import MetalSprockets
import MetalSprocketsSupport
import MetalSprocketsUI
import simd
import SwiftUI

/// Per-frame callbacks, like SCNSceneRendererDelegate. All are optional.
@MainActor
public protocol ViewDelegate: AnyObject {
    /// Before actions run. Change the scene here.
    func sceneView(updateAtTime time: Float, deltaTime: Float)
    /// After actions ran, before constraints.
    func sceneView(didApplyActionsAtTime time: Float)
    /// After constraints ran, just before the frame is drawn.
    func sceneView(didApplyConstraintsAtTime time: Float)
}

public extension ViewDelegate {
    func sceneView(updateAtTime _: Float, deltaTime _: Float) {}
    func sceneView(didApplyActionsAtTime _: Float) {}
    func sceneView(didApplyConstraintsAtTime _: Float) {}
}

/// Shows a scene graph, like SceneKit's SwiftUI SceneView. Runs node actions every frame.
///
/// Configure it with the `scene…` methods, which return a configured copy:
///
/// ```swift
/// SceneView(sceneGraph, renderers: [BlinnPhongMaterialRenderer()])
///     .sceneCameraControl()
///     .sceneShadows(shadows)
///     .onSceneTap { hit in print(hit?.node.label ?? "nothing") }
/// ```
public struct SceneView: View {
    // Debug settings turned on by environment variables, for a run without editing the call site (#365):
    // SS_SHOWS_STATISTICS, SS_SHOWS_FRAME_TIMING, SS_DISABLES_FRAMEBUFFER_ONLY. They add to the settings in code.
    struct DebugFlags: Equatable {
        var showsStatistics = false
        var showsFrameTiming = false
        var keepsDrawableReadable = false

        init(showsStatistics: Bool = false, showsFrameTiming: Bool = false, keepsDrawableReadable: Bool = false) {
            self.showsStatistics = showsStatistics
            self.showsFrameTiming = showsFrameTiming
            self.keepsDrawableReadable = keepsDrawableReadable
        }

        init(environment: SystemEnvironment) {
            func isOn(_ name: String) -> Bool {
                let value = environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return value.map { ["1", "true", "yes", "y", "on"].contains($0) } ?? false
            }
            self.init(showsStatistics: isOn("SS_SHOWS_STATISTICS"), showsFrameTiming: isOn("SS_SHOWS_FRAME_TIMING"), keepsDrawableReadable: isOn("SS_DISABLES_FRAMEBUFFER_ONLY"))
        }
    }

    private let sceneGraph: SceneGraph
    private let pointOfView: SceneGraph.Node?
    private let renderers: [any MaterialRenderer]
    private var allowsCameraControl = false
    private var usesDefaultLighting = false
    private var settingsShowStatistics = false
    private var settingsShowFrameTiming = false
    private var settingsKeepDrawableReadable = false
    private let environmentFlags: DebugFlags
    private weak var delegate: (any ViewDelegate)?
    private var isPlaying = true
    private var shadows: Shadows?
    private var audio: Audio?
    private var externalCameraMatrix: Binding<simd_float4x4?>?
    private var onTap: ((SceneGraph.Hit?) -> Void)?
    private var onTapID: AnyHashable?
    private var onTapAt: ((SIMD2<Float>, Viewport, SceneGraph.Hit?) -> Void)?
    private var onTapAtID: AnyHashable?
    private var hitTestOptions = SceneGraph.HitTestOptions()
    private var manipulator: (any ViewManipulator)?
    private var decorations: ((RenderContext, SIMD2<Float>) throws -> AnyElement?)?
    private var decorationsID: AnyHashable?
    private var defaultCamera: Camera = .default
    private var cameraOverride: Camera?
    private var cameraTarget: SIMD3<Float>?
    private var overlay: ((Viewport) throws -> AnyElement?)?
    private var overlayID: AnyHashable?
    private var debugMode: DebugMode?
    private var materialChannel: MaterialChannel?
    // Whether the scene had fog or post-processing when this view was made. The body reads them to configure the
    // drawable, so == must notice when they change (#235).
    private let hadScenePostPasses: Bool

    private var showsStatistics: Bool { settingsShowStatistics || environmentFlags.showsStatistics }
    private var showsFrameTiming: Bool { settingsShowFrameTiming || environmentFlags.showsFrameTiming }
    private var keepsDrawableReadable: Bool { settingsKeepDrawableReadable || environmentFlags.keepsDrawableReadable }

    @Environment(\.displayScale) private var displayScale
    @Environment(\.sceneCameraControl) private var cameraControl
    // Decided at the first change of each drag: whether it started on the manipulator.
    @State private var manipulatorDragClaim: Bool?
    // The same for two-finger pinch and twist (iOS, visionOS).
    @State private var twoFingerClaim: Bool? // periphery:ignore - read in the gesture handlers

    @State private var internalCameraMatrix: simd_float4x4?
    @State private var controlledCameraMatrix: simd_float4x4 = matrix_identity_float4x4
    @State private var viewSize: CGSize = .zero
    // Fixed when the view appears: recomputing it from the bounds every frame makes the camera chase objects that
    // move far away (for example a body falling forever).
    @State private var orbitTarget: SIMD3<Float>?
    @State private var clock = SceneClock()
    @State private var frameTimingStatistics: FrameTimingStatistics?

    /// Creates a view that shows a scene graph.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene to show.
    ///   - pointOfView: The camera node to look through. Nil: the first camera node, or a camera that frames the scene
    ///     when there is none.
    ///   - renderers: One renderer for each material family the scene uses, for example `BlinnPhongMaterialRenderer`
    ///     (SceneSprocketsBlinnPhong) or `PBRMaterialRenderer` (SceneSprocketsPBR). A mesh whose material has no
    ///     renderer is not drawn, and a warning is logged once.
    public init(_ sceneGraph: SceneGraph, pointOfView: SceneGraph.Node? = nil, renderers: [any MaterialRenderer]) {
        self.sceneGraph = sceneGraph
        self.pointOfView = pointOfView
        self.renderers = renderers
        self.hadScenePostPasses = sceneGraph.fog != nil || sceneGraph.postProcessing != nil
        self.environmentFlags = DebugFlags(environment: .current)
    }

    private func with(_ change: (inout Self) -> Void) -> Self {
        var copy = self
        change(&copy)
        return copy
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
                defaultLight: usesDefaultLighting ? Light(type: .directional, color: [1, 1, 1], intensity: 1) : nil,
                shadows: shadows,
                storesDepth: overlay != nil,
                decorations: decorations.map { decorations in
                    { context in try decorations(context, SIMD2<Float>(Float(size.width), Float(size.height))) }
                },
                debugMode: debugMode,
                materialChannel: materialChannel
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
        .metalFramebufferOnly(!needsPostPasses && !keepsDrawableReadable)
        .metalDepthStencilAttachmentTextureUsage(needsPostPasses ? [.renderTarget, .shaderRead] : [.renderTarget])
        .metalDepthStencilStorageMode(needsPostPasses || overlay != nil ? .private : .memoryless)
        .modifier(CameraControlModifier(isEnabled: allowsCameraControl, cameraMatrix: $controlledCameraMatrix, target: cameraTarget ?? orbitTarget ?? viewpoint.target, configuration: cameraControl))
        // Camera control edits a stable @State; these keep it and the source in step (#231).
        .onChange(of: cameraMatrix ?? viewpoint.matrix, initial: true) { _, newValue in
            if controlledCameraMatrix != newValue {
                controlledCameraMatrix = newValue
            }
        }
        .onChange(of: controlledCameraMatrix) { _, newValue in
            guard newValue != (cameraMatrix ?? viewpoint.matrix) else {
                return
            }
            if let externalCameraMatrix {
                externalCameraMatrix.wrappedValue = newValue
            } else {
                internalCameraMatrix = newValue
            }
        }
        // Camera control leaves drags that start on the manipulator alone.
        .interactionDragFilter(LocationFilter { location in !manipulatorHit(at: location) })
        .interactionMagnifyFilter(LocationFilter { location in !manipulatorClaimsTwoFingers(at: location) })
        #if os(iOS) || os(visionOS)
        .simultaneousGesture(twoFingerGesture, including: manipulator != nil ? .all : .subviews)
        #endif
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
            // With a manipulator, its zero-distance drag wins over this tap; manipulatorDrag reports taps instead.
            guard manipulator == nil else {
                return
            }
            reportTap(at: location)
        }
        .onFrameTimingChange { statistics in
            // Only stored while shown; otherwise every frame would update the view.
            if showsFrameTiming {
                frameTimingStatistics = statistics
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsFrameTiming, let frameTimingStatistics {
                FrameTimingView(statistics: frameTimingStatistics, options: .all)
                    .padding()
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsStatistics {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                    let statistics = sceneGraph.statistics
                    Text("\(statistics.meshCount) meshes \u{00B7} \(statistics.triangleCount) triangles \u{00B7} \(statistics.lightCount) lights")
                        .font(.caption.monospacedDigit())
                        // A tight badge inset; the default padding is too large for caption text.
                        .padding(4)
                        .background(.black.opacity(0.6), in: .rect(cornerRadius: 4))
                        .foregroundStyle(.white)
                        .padding()
                }
            }
        }
    }

    private func reportTap(at location: CGPoint) {
        guard onTap != nil || onTapAt != nil else {
            return
        }
        let hit = hit(at: location)
        onTap?(hit)
        if let onTapAt, let viewport = viewport() {
            onTapAt([Float(location.x), Float(location.y)], viewport, hit)
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
            .onEnded { value in
                if manipulatorDragClaim == true {
                    manipulator?.endDrag()
                } else if manipulator != nil, hypot(value.translation.width, value.translation.height) < 4 {
                    reportTap(at: value.location)
                }
                manipulatorDragClaim = nil
            }
    }

    private func manipulatorClaimsTwoFingers(at location: CGPoint) -> Bool {
        guard let manipulator, let viewport = viewport() else {
            return false
        }
        return manipulator.claimsTwoFingerGesture(at: [Float(location.x), Float(location.y)], viewport: viewport)
    }

    #if os(iOS) || os(visionOS)
    private var twoFingerGesture: some Gesture {
        MagnifyGesture().simultaneously(with: RotateGesture())
            .onChanged { value in
                guard let manipulator, let viewport = viewport() else {
                    return
                }
                if twoFingerClaim == nil {
                    guard let start = value.first?.startLocation else {
                        return
                    }
                    let claimed = manipulatorClaimsTwoFingers(at: start)
                    twoFingerClaim = claimed
                    if claimed {
                        manipulator.beginTwoFingerGesture(viewport: viewport)
                    }
                }
                if twoFingerClaim == true {
                    manipulator.twoFingerGesture(scale: Float(value.first?.magnification ?? 1), rotation: Float(value.second?.rotation.radians ?? 0), viewport: viewport)
                }
            }
            .onEnded { _ in
                if twoFingerClaim == true {
                    manipulator?.endTwoFingerGesture()
                }
                twoFingerClaim = nil
            }
    }
    #endif

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
    private func viewport(drawableSize: CGSize? = nil) -> Viewport? {
        guard viewSize.width > 0, viewSize.height > 0 else {
            return nil
        }
        let size = SIMD2<Float>(Float(viewSize.width), Float(viewSize.height))
        let drawable = drawableSize.map { SIMD2<Float>(Float($0.width), Float($0.height)) } ?? size * Float(displayScale)
        return Viewport(cameraMatrix: currentCameraMatrix, camera: activeCamera, viewSize: size, drawableSize: drawable)
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

    /// The camera that the view uses when the scene has no camera node.
    @available(*, deprecated, renamed: "Camera.default")
    public static var defaultCamera: Camera {
        .default
    }

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
        allowsCameraControl || externalCameraMatrix?.wrappedValue != nil
    }

    // The world transform the frame is drawn from.
    private var currentCameraMatrix: simd_float4x4 {
        if usesFreeCamera {
            return cameraMatrix ?? viewpoint.matrix
        }
        return activeCameraNode?.worldTransform ?? viewpoint.matrix
    }

    private func hit(at location: CGPoint) -> SceneGraph.Hit? {
        guard let viewport = viewport() else {
            return nil
        }
        return sceneGraph.hitTest(viewport.ray(through: [Float(location.x), Float(location.y)]), options: Self.tapHitTestOptions(hitTestOptions, cameraCategoryBitMask: activeCamera.categoryBitMask)).first
    }

    // Like SceneKit, taps only hit nodes the camera can see: the camera's mask narrows the options' mask.
    static func tapHitTestOptions(_ options: SceneGraph.HitTestOptions, cameraCategoryBitMask: UInt) -> SceneGraph.HitTestOptions {
        var options = options
        options.categoryBitMask &= cameraCategoryBitMask
        return options
    }
}

// Scene time that stops while paused. A class so the render closure can advance it without invalidating the view.
final class SceneClock {
    private var lastFrameTime: Float?
    private var time: Float = 0

    func advance(to frameTime: Float, isPaused: Bool) -> (time: Float, deltaTime: Float) {
        let interval = max(frameTime - (lastFrameTime ?? frameTime), 0)
        // Clamped, so a stall does not jump animations.
        let deltaTime = isPaused ? 0 : min(interval, 1.0 / 15)
        lastFrameTime = frameTime
        time += deltaTime
        return (time, deltaTime)
    }
}

// Configuration, like SwiftUI's Text modifiers: each returns a configured copy (#369).
public extension SceneView {
    /// Turns on orbit, pan and zoom with the mouse, trackpad or touch. The point of view's node is not moved. Tune
    /// it with the `sceneCameraControl(_:)` view modifier that takes a ``CameraControl``.
    func sceneCameraControl(_ enabled: Bool = true) -> Self {
        with { $0.allowsCameraControl = enabled }
    }

    /// Adds a white directional light at the camera when the scene has no lights.
    func sceneDefaultLighting(_ enabled: Bool = true) -> Self {
        with { $0.usesDefaultLighting = enabled }
    }

    /// Draws shadows. Keep the same instance across updates: it holds the shadow map.
    func sceneShadows(_ shadows: Shadows?) -> Self {
        with { $0.shadows = shadows }
    }

    /// Plays the audio players of the scene's nodes, with the camera as the listener.
    func sceneAudio(_ audio: Audio?) -> Self {
        with { $0.audio = audio }
    }

    /// Calls the delegate every frame, like SCNSceneRendererDelegate. The view does not keep it alive.
    func sceneDelegate(_ delegate: (any ViewDelegate)?) -> Self {
        with { $0.delegate = delegate }
    }

    /// False freezes scene time: actions, particles and delegate time stop.
    func scenePlaying(_ isPlaying: Bool) -> Self {
        with { $0.isPlaying = isPlaying }
    }

    /// Camera settings.
    ///
    /// - Parameters:
    ///   - matrix: Exposes the camera transform that camera control edits (nil: start from the point of view; set nil
    ///     to reset). Without camera control, a non-nil value still sets the camera, for your own camera control.
    ///   - target: The point camera control orbits. Nil: the scene's center when the view appears.
    ///   - override: Replaces the camera node's camera (projection, masks), for editor cameras. The transform still
    ///     comes from `matrix` or the node.
    func sceneCamera(matrix: Binding<simd_float4x4?>? = nil, target: SIMD3<Float>? = nil, override: Camera? = nil) -> Self {
        with {
            $0.externalCameraMatrix = matrix
            $0.cameraTarget = target
            $0.cameraOverride = override
        }
    }

    /// The camera to use when the scene has no camera node. The default is ``Camera/default``.
    func sceneDefaultCamera(_ camera: Camera) -> Self {
        with { $0.defaultCamera = camera }
    }

    /// How taps hit-test the scene, with the same options as `SceneGraph.hitTest(_:options:)`. Taps only hit nodes the
    /// camera can see, so the camera's `categoryBitMask` further narrows `options.categoryBitMask`.
    func sceneHitTestOptions(_ options: SceneGraph.HitTestOptions) -> Self {
        with { $0.hitTestOptions = options }
    }

    /// Calls `action` with the nearest hit under a tap or click, or nil.
    ///
    /// - Parameters:
    ///   - id: Identifies what the closure captures. While it stays the same, the view treats the closure as
    ///     unchanged and can skip updates (#235). Nil: the closure always counts as changed.
    ///   - action: The closure to call.
    func onSceneTap(id: AnyHashable? = nil, perform action: @escaping (SceneGraph.Hit?) -> Void) -> Self {
        with {
            $0.onTap = action
            $0.onTapID = id
        }
    }

    /// Like ``onSceneTap(id:perform:)-(_,(SceneGraph.Hit?)->Void)``, with the tap point in view coordinates and the
    /// viewport, for picking things the mesh hit test cannot see, such as editor icons.
    func onSceneTap(id: AnyHashable? = nil, perform action: @escaping (SIMD2<Float>, Viewport, SceneGraph.Hit?) -> Void) -> Self {
        with {
            $0.onTapAt = action
            $0.onTapAtID = id
        }
    }

    /// Draws over the scene and takes drags that start on it, for example a transform gizmo.
    func sceneManipulator(_ manipulator: (any ViewManipulator)?) -> Self {
        with { $0.manipulator = manipulator }
    }

    /// Draws extra content in the scene pass after the meshes, with the scene's reversed depth (compare `.greater`),
    /// given the frame's context and drawable size in pixels. For editor aids such as grids that objects should hide.
    func sceneDecorations(id: AnyHashable? = nil, _ decorations: ((RenderContext, SIMD2<Float>) throws -> AnyElement?)?) -> Self {
        with {
            $0.decorations = decorations
            $0.decorationsID = id
        }
    }

    /// Passes after the scene and before the manipulator, such as selection outlines. They see the finished color and
    /// can load the scene depth (reversed: nearer is greater). Start passes that read the drawable with a barrier.
    /// Nil removes the overlay; an overlay makes the view keep its depth texture.
    func sceneOverlay(id: AnyHashable? = nil, _ overlay: ((Viewport) throws -> AnyElement?)?) -> Self {
        with {
            $0.overlay = overlay
            $0.overlayID = id
        }
    }

    /// Draws every mesh in a debug view instead of its material (#132).
    func sceneDebugMode(_ mode: DebugMode?) -> Self {
        with { $0.debugMode = mode }
    }

    /// Shows one material value instead of lighting (#195).
    func sceneMaterialChannel(_ channel: MaterialChannel?) -> Self {
        with { $0.materialChannel = channel }
    }

    /// Overlays scene statistics (meshes, triangles, lights), like SCNView.showsStatistics. Also on when the
    /// `SS_SHOWS_STATISTICS` environment variable is set.
    func sceneStatistics(_ shown: Bool = true) -> Self {
        with { $0.settingsShowStatistics = shown }
    }

    /// Overlays MetalSprocketsUI's frame timing readout. Also on when `SS_SHOWS_FRAME_TIMING` is set.
    func sceneFrameTiming(_ shown: Bool = true) -> Self {
        with { $0.settingsShowFrameTiming = shown }
    }

    /// Keeps the drawable readable (framebufferOnly false) even without post passes, for example to inspect it in a
    /// GPU capture. Costs some bandwidth. Also on when `SS_DISABLES_FRAMEBUFFER_ONLY` is set.
    func sceneReadableDrawable(_ enabled: Bool = true) -> Self {
        with { $0.settingsKeepDrawableReadable = enabled }
    }
}

// Lets SwiftUI skip SceneView's body when its inputs have not changed (#235). Objects compare by identity; closures by
// the id given with them; renderers that are not Equatable, and closures without an id, always count as changed.
extension SceneView: @MainActor Equatable {
    public static func == (lhs: SceneView, rhs: SceneView) -> Bool {
        // The camera binding compares by value: callers pass key-path bindings to the same model.
        isSameClosure(lhs.onTap == nil, lhs.onTapID, rhs.onTap == nil, rhs.onTapID)
            && isSameClosure(lhs.onTapAt == nil, lhs.onTapAtID, rhs.onTapAt == nil, rhs.onTapAtID)
            && isSameClosure(lhs.decorations == nil, lhs.decorationsID, rhs.decorations == nil, rhs.decorationsID)
            && isSameClosure(lhs.overlay == nil, lhs.overlayID, rhs.overlay == nil, rhs.overlayID)
            && lhs.sceneGraph === rhs.sceneGraph
            && lhs.hadScenePostPasses == rhs.hadScenePostPasses
            && lhs.pointOfView === rhs.pointOfView
            && lhs.allowsCameraControl == rhs.allowsCameraControl
            && lhs.usesDefaultLighting == rhs.usesDefaultLighting
            && lhs.showsStatistics == rhs.showsStatistics
            && lhs.showsFrameTiming == rhs.showsFrameTiming
            && lhs.keepsDrawableReadable == rhs.keepsDrawableReadable
            && lhs.renderers.count == rhs.renderers.count
            && zip(lhs.renderers, rhs.renderers).allSatisfy(Self.isSameRenderer)
            && lhs.delegate === rhs.delegate
            && lhs.isPlaying == rhs.isPlaying
            && lhs.shadows === rhs.shadows
            && lhs.audio === rhs.audio
            && (lhs.externalCameraMatrix == nil) == (rhs.externalCameraMatrix == nil)
            && lhs.externalCameraMatrix?.wrappedValue == rhs.externalCameraMatrix?.wrappedValue
            && isSameHitTestOptions(lhs.hitTestOptions, rhs.hitTestOptions)
            && lhs.manipulator === rhs.manipulator
            && Self.isSameCamera(lhs.defaultCamera, rhs.defaultCamera)
            && Self.isSameCamera(lhs.cameraOverride, rhs.cameraOverride)
            && lhs.cameraTarget == rhs.cameraTarget
            && lhs.debugMode == rhs.debugMode
            && lhs.materialChannel == rhs.materialChannel
    }

    // HitTestOptions holds a node, so it is not Equatable; the node compares by identity.
    private static func isSameHitTestOptions(_ lhs: SceneGraph.HitTestOptions, _ rhs: SceneGraph.HitTestOptions) -> Bool {
        (lhs.categoryBitMask, lhs.backFaceCulling, lhs.boundingBoxOnly, lhs.firstFoundOnly, lhs.maximumDistance) == (rhs.categoryBitMask, rhs.backFaceCulling, rhs.boundingBoxOnly, rhs.firstFoundOnly, rhs.maximumDistance)
            && lhs.rootNode === rhs.rootNode
    }

    // Both absent, or both present with the same non-nil id. Closures cannot be compared themselves.
    private static func isSameClosure(_ lhsIsNil: Bool, _ lhsID: AnyHashable?, _ rhsIsNil: Bool, _ rhsID: AnyHashable?) -> Bool {
        if lhsIsNil || rhsIsNil {
            return lhsIsNil == rhsIsNil
        }
        return lhsID != nil && lhsID == rhsID
    }

    private static func isSameRenderer(_ lhs: any MaterialRenderer, _ rhs: any MaterialRenderer) -> Bool {
        func isEqual<T: Equatable>(_ lhs: T, _ rhs: Any) -> Bool {
            (rhs as? T) == lhs
        }
        guard let lhs = lhs as? any Equatable else {
            return false
        }
        return isEqual(lhs, rhs)
    }

    // Projections are not Equatable; their matrices and depth direction say what they do.
    private static func isSameCamera(_ lhs: Camera?, _ rhs: Camera?) -> Bool {
        guard let lhs, let rhs else {
            return lhs == nil && rhs == nil
        }
        return lhs.categoryBitMask == rhs.categoryBitMask
            && lhs.projection.isReverseZ == rhs.projection.isReverseZ
            && lhs.projection.projectionMatrix(aspectRatio: 1) == rhs.projection.projectionMatrix(aspectRatio: 1)
    }
}

private struct CameraControlModifier: ViewModifier {
    var isEnabled: Bool
    @Binding var cameraMatrix: simd_float4x4
    var target: SIMD3<Float>
    var configuration: CameraControl

    func body(content: Content) -> some View {
        if isEnabled, configuration.mode == .fly {
            content.fpvMovement(cameraMatrix: $cameraMatrix, settings: configuration.flySettings)
        } else if isEnabled {
            // Changes from the interaction are kept inside the configuration's limits (#312).
            let clamped = Binding(
                get: { cameraMatrix },
                set: { [configuration, target] newValue in cameraMatrix = configuration.clamped(newValue, target: target) }
            )
            content.interactiveCamera(cameraMatrix: clamped, mode: configuration.interactionMode, transforms: configuration.transforms, target: target)
        } else {
            content
        }
    }
}

// Adapts a closure to Interaction3D's location filters.
private struct LocationFilter: InteractionLocationFilter {
    let accepts: @MainActor (CGPoint) -> Bool

    func accepts(_ location: CGPoint) -> Bool {
        accepts(location)
    }
}
