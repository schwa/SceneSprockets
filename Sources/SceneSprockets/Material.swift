// Not Sendable: materials hold Metal objects (textures, samplers) that are not Sendable, and nodes are not Sendable either.

/// A marker protocol for scene graph materials.
///
/// Materials are opaque data attached to mesh nodes. Concrete material types
/// (e.g. PBR, Blinn-Phong) are defined outside this package. At render time,
/// techniques filter nodes by material type and downcast to access material-specific data.
public protocol Material {
    // Blends over what is behind it. Transparent entries draw after opaque ones of the same rendering order,
    // farthest first.
    var isTransparent: Bool { get }
    // Whether its renderer multiplies the output alpha by the node's inherited opacity. Other materials ignore
    // node opacity.
    var appliesNodeOpacity: Bool { get }
}

public extension Material {
    var isTransparent: Bool { false }
    var appliesNodeOpacity: Bool { false }
}
