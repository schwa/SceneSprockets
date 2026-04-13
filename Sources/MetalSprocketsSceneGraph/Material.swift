/// A marker protocol for scene graph materials.
///
/// Materials are opaque data attached to mesh nodes. Concrete material types
/// (e.g. PBR, Blinn-Phong) are defined outside this package. At render time,
/// techniques filter nodes by material type and downcast to access material-specific data.
// Not Sendable: materials hold Metal objects (textures, samplers) that are not Sendable, and nodes are not Sendable either.
public protocol Material {
}
