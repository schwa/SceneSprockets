#if os(visionOS)
import GeometryLite3D
import Metal
import MetalSprockets
import MetalSprocketsUI
import simd

/// Draws a scene in a visionOS immersive space: both eyes at once, into the compositor's layered, reverse-Z targets,
/// inside an `ImmersiveRenderPass` (so progressive immersion masks it).
///
/// The immersive render loop runs off the main actor, so the element never touches the live scene graph: it draws the
/// latest snapshot from a ``ScenePresenter``, which updates the scene on the main actor (#391).
///
/// ```swift
/// let presenter = ScenePresenter(sceneGraph: sceneGraph)
/// presenter.start()
///
/// ImmersiveSpace(id: "Scene") {
///     ImmersiveRenderContent { context in
///         SceneImmersiveElement(presenter: presenter, renderers: [BlinnPhongMaterialRenderer(), PBRMaterialRenderer()], context: context)
///     }
/// }
/// ```
///
/// The space's coordinates are meters, with the floor at y = 0. `sceneTransform` places the scene in them, for example
/// 1.5 m in front of the viewer. Camera nodes are ignored: the viewer's head is the camera, and constraints see it
/// through the presenter.
///
/// Not drawn in immersive spaces yet: shadows, fog, ambient occlusion and color adjustment (#382). The compositor's
/// pass can be foveated, which allows only triangles, so avoid wireframe and point or line meshes.
public struct SceneImmersiveElement: Element {
    var presenter: ScenePresenter
    var renderers: [any MaterialRenderer]
    var context: ImmersiveContext
    var sceneTransform: simd_float4x4
    var defaultLight: Light?

    /// Creates an element that draws a presenter's scene in an immersive space.
    ///
    /// - Parameters:
    ///   - presenter: The presenter whose latest snapshot is drawn.
    ///   - renderers: One renderer for each material family that the scene uses.
    ///   - context: The immersive context from `ImmersiveRenderContent`.
    ///   - sceneTransform: Where the scene's origin is in the immersive space.
    ///   - defaultLight: A light at the viewer when the scene has no lights.
    public init(presenter: ScenePresenter, renderers: [any MaterialRenderer], context: ImmersiveContext, sceneTransform: simd_float4x4 = matrix_identity_float4x4, defaultLight: Light? = nil) {
        self.presenter = presenter
        self.renderers = renderers
        self.context = context
        self.sceneTransform = sceneTransform
        self.defaultLight = defaultLight
    }

    /// The eyes, with view matrices in the scene's space.
    var stereoViews: StereoViews {
        var views = context.stereoViews
        views.viewMatrices = views.viewMatrices.map { $0 * sceneTransform }
        return views
    }

    public var body: some Element {
        let stereoViews = stereoViews
        presenter.setViewerTransform(stereoViews.centerCameraMatrix)
        var element = SceneGraphElement(
            presentation: presenter.takePresentation(),
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
