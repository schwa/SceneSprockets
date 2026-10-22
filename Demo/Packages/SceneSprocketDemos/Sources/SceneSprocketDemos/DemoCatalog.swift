public enum DemoCatalog {
    // Demos that need only this package, in picker order. Built from SceneGraphDemos.all so there is one list.
    public static let demos: [Demo] = SceneGraphDemos.catalog.map { $0.demo }
}
