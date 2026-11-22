/// Something a ``GLTFAsset`` load skipped or could not do exactly, with a ``kind`` to check in code and a
/// ``description`` to show (#562).
public struct GLTFWarning: Sendable, Equatable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable {
        /// The file requires extensions this load does not support; it was loaded anyway
        /// (``GLTFLoadOptions/loadsUnsupportedRequiredExtensions``).
        case requiredExtensionsLoadedAnyway([String])
        /// A mesh primitive could not be built and was left out.
        case primitiveSkipped(mesh: String, primitive: Int)
        /// An animation channel cannot be used, for example one that animates a node that uses `matrix`.
        case animationChannelSkipped(animation: String)
        /// A KHR_animation_pointer target this package does not animate.
        case animationPointerUnsupported(String)
        /// An EXT_lights_image_based light could not be decoded.
        case imageBasedLightSkipped(index: Int)
        /// A texture a material uses has no loadable source.
        case textureSkipped(index: Int)
        /// An image a material uses failed to decode.
        case imageFailed(index: Int)
        /// A texture's sampler index is out of range; it uses the default sampler.
        case samplerOutOfRange(texture: Int, sampler: Int)
    }

    public var kind: Kind
    public var description: String

    public init(_ kind: Kind, _ description: String) {
        self.kind = kind
        self.description = description
    }
}
