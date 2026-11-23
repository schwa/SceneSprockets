import Metal
import MetalSprockets

/// Where ``SceneGraphElement/renderStage(_:_:)`` content draws in a frame (#512).
public enum RenderStage: Hashable, Sendable, CaseIterable {
    /// In the scene pass, after the opaque meshes (up to the first transparent batch), before ``beforeTransparent``.
    case afterOpaque
    /// In the scene pass, just before the transparent meshes.
    case beforeTransparent
    /// In the scene pass, after every mesh and before decorations and node text.
    case afterTransparent
    /// After the scene and its post passes (shadow mask, fog, color adjustment, exposure), as separate passes: the
    /// element opens its own render or compute passes and can read and write the targets.
    case postProcess
}

/// The view's targets, for ``RenderStage`` content.
public struct RenderStageTargets {
    /// The view's color texture. Readable and writable from compute only with `Shadows.requiredColorUsage`.
    public var color: MTLTexture?
    /// The view's depth texture (reversed depth: compare `.greater`); stored only when a pass needs it.
    public var depth: MTLTexture?
}

/// Content for a ``RenderStage``: called on the thread that draws the frame, so it must not read main-actor state.
/// Return nil to draw nothing.
public typealias RenderStageContent = (RenderContext, RenderStageTargets) throws -> AnyElement?

public extension SceneGraphElement {
    /// Draws `content` at `stage` of every frame (#512); replaces earlier content for the same stage.
    func renderStage(_ stage: RenderStage, _ content: @escaping RenderStageContent) -> Self {
        var copy = self
        copy.stageContent[stage] = content
        return copy
    }

    // Every stage's content at once, for SceneView.
    internal func renderStages(_ content: [RenderStage: RenderStageContent]) -> Self {
        var copy = self
        copy.stageContent.merge(content) { $1 }
        return copy
    }
}
