import GeometryLite3D

extension SceneGraph.Node {
    /// A node that holds a light.
    ///
    /// - Parameters:
    ///   - light: The light. It points down the node's -Z axis.
    ///   - label: A name for the node.
    ///   - transform: The node's local transform.
    public static func light(_ light: Light, label: String? = nil, transform: Transform3D = .identity) -> SceneGraph.Node {
        SceneGraph.Node(label: label, transform: transform, content: .light(light))
    }

    /// A node that holds a camera.
    ///
    /// - Parameters:
    ///   - camera: The camera. It looks down the node's -Z axis.
    ///   - label: A name for the node.
    ///   - transform: The node's local transform.
    public static func camera(_ camera: Camera = .default, label: String? = nil, transform: Transform3D = .identity) -> SceneGraph.Node {
        SceneGraph.Node(label: label, transform: transform, content: .camera(camera))
    }
}
