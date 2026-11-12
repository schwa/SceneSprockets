#if os(visionOS)
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsUI
import simd

/// Draws a scene graph in a visionOS immersive space: both eyes at once, into the compositor's layered, reverse-Z
/// targets, inside an `ImmersiveRenderPass` (so progressive immersion masks it).
///
/// ```swift
/// ImmersiveSpace(id: "Scene") {
///     ImmersiveRenderContent { context in
///         SceneImmersiveElement(sceneGraph, renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()], context: context)
///     }
/// }
/// ```
///
/// The space's coordinates are meters, with the floor at y = 0. `sceneTransform` places the scene in them, for example
/// 1.5 m in front of the viewer. Camera nodes are ignored: the viewer's head is the camera. Each frame advances actions,
/// particles and constraints by the frame's time, like ``SceneView``.
///
/// Not drawn in immersive spaces yet: shadows, fog, ambient occlusion and color adjustment (#382); particles and
/// MetalSprocketsAddOns content draw one eye only. The compositor's pass can be foveated, which allows only triangles,
/// so avoid wireframe and point or line meshes.
public struct SceneImmersiveElement: Element {
    var sceneGraph: SceneGraph
    var renderers: [any MaterialRenderer]
    var context: ImmersiveContext
    var sceneTransform: simd_float4x4
    var defaultLight: Light?
    var isPlaying: Bool

    @MSState private var clock = SceneClock()

    /// Creates an element that draws a scene graph in an immersive space.
    ///
    /// - Parameters:
    ///   - sceneGraph: The scene to draw.
    ///   - renderers: One renderer for each material family that the scene uses.
    ///   - context: The immersive context from `ImmersiveRenderContent`.
    ///   - sceneTransform: Where the scene's origin is in the immersive space.
    ///   - defaultLight: A light at the viewer when the scene has no lights.
    ///   - isPlaying: False freezes scene time: actions, particles and constraints stop.
    public init(_ sceneGraph: SceneGraph, renderers: [any MaterialRenderer], context: ImmersiveContext, sceneTransform: simd_float4x4 = matrix_identity_float4x4, defaultLight: Light? = nil, isPlaying: Bool = true) {
        self.sceneGraph = sceneGraph
        self.renderers = renderers
        self.context = context
        self.sceneTransform = sceneTransform
        self.defaultLight = defaultLight
        self.isPlaying = isPlaying
    }

    /// The eyes, with view matrices in the scene's space.
    var stereoViews: StereoViews {
        var views = context.stereoViews
        views.viewMatrices = views.viewMatrices.map { $0 * sceneTransform }
        return views
    }

    public var body: some Element {
        let stereoViews = stereoViews
        let (_, deltaTime) = clock.advance(to: Float(context.time), isPaused: !isPlaying)
        sceneGraph.advanceActions(by: deltaTime)
        sceneGraph.advanceParticles(by: deltaTime)
        sceneGraph.applyConstraints(pointOfView: stereoViews.centerCameraMatrix, deltaTime: deltaTime)
        var element = SceneGraphElement(
            sceneGraph: sceneGraph,
            aspectRatio: 1,
            renderers: renderers,
            defaultCamera: Camera(projection: PerspectiveProjection()),
            cameraOverride: Camera(projection: PerspectiveProjection()),
            defaultLight: defaultLight,
            stereoViews: stereoViews
        )
        element.immersiveContext = context
        return element
    }
}
#endif
