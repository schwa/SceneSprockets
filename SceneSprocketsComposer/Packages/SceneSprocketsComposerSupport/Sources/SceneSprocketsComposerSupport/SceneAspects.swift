// What an edit changes, so EditorModel.notify(_:) can refresh the views that show it (#236).
struct SceneAspects: OptionSet {
    let rawValue: Int

    static let transform = Self(rawValue: 1 << 0)
    static let visibility = Self(rawValue: 1 << 1)
    static let label = Self(rawValue: 1 << 2)
    // Lights, materials and other node content.
    static let content = Self(rawValue: 1 << 3)
    // Nodes added, removed or moved in the tree.
    static let structure = Self(rawValue: 1 << 4)
    static let environment = Self(rawValue: 1 << 5)
}
