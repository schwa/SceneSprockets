import Metal

// @unchecked: MTLTexture is not Sendable. Renderers only read it, and Metal allows that from any thread.

/// Screen-space ambient occlusion for one frame, read by shaders with `Lighting::screenOcclusion`.
public struct LightingAmbientOcclusion: @unchecked Sendable {
    /// A 2D texture with one texel per render target pixel; the red channel is the occlusion (1 is unoccluded).
    public var texture: MTLTexture
    /// 0 leaves indirect light unchanged, 1 applies the full occlusion.
    public var strength: Float

    public init(texture: MTLTexture, strength: Float = 1) {
        self.texture = texture
        self.strength = strength
    }
}
