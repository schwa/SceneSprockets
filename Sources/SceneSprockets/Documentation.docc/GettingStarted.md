# Getting Started

Build a tree of nodes and show it in SwiftUI.

## Build a scene

```swift
import SceneSprockets
import SceneSprocketsBlinnPhong

let root = SceneGraph.Node(label: "Root")

let camera = root.addChild(SceneGraph.Node(label: "Camera", content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45))))))
camera.trs.translation = [0, 1, 6]

let light = root.addChild(SceneGraph.Node(label: "Light", content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20, range: 100))))
light.trs.translation = [2, 3, 2]

let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.8, 0.5, 0.2]), specular: .color(0.3), shininess: 16)
let crate = root.addChild(SceneGraph.Node(label: "Crate", shape: .box(), material: material))

let sceneGraph = SceneGraph(root: root)
```

## Show it

``SceneView`` works like SceneKit's SwiftUI `SceneView`. Give it one renderer for each material family that the scene uses:

```swift
SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl], renderers: [BlinnPhongMaterialRenderer()]) { hit in
    print(hit?.node.label ?? "nothing")
}
```

It runs node actions and constraints every frame. If the scene has no camera node, it frames the scene with a default camera.

## Nodes

- **Hierarchy.** `parent.addChild(node)` adds a node and returns it, so `let child = root.addChild(Node(...))` makes and attaches a node in one line. You can also use `insertChild(_:at:)`, `removeFromParent()` and `removeAllChildren()`. You cannot set `parent` and `children` directly. If a new child makes a cycle, a precondition stops the app.
- **Transforms.** A node stores a matrix (`transform`) or translation, rotation and scale (`trs`). Edits through `trs` do not lose data. If you read `trs` from a matrix node, SceneSprockets decomposes the matrix. `worldTransform` gives the node's world-space matrix.
- **Shapes.** `Node(shape:material:)` makes a mesh node from a ``SceneGraph/Shape``: box, sphere, plane, cylinder, cone, capsule, torus or extruded text, like SceneKit's `SCNBox` or `SCNText`. To change the parameters, set `node.shape`. SceneSprockets then rebuilds the mesh and keeps the materials.
- **Materials.** `.mesh(mesh, material:)` uses one material for all submeshes. `.mesh(mesh, materials:)` sets one material for each submesh. Submeshes after the end of the array use the last material.
- **Visibility and opacity.** To hide a node and its subtree in rendering, queries and bounds, set `isVisible = false`. The `opacity` of a node multiplies the opacity of its descendants.
- **Category masks.** Like SceneKit, SceneSprockets compares `node.categoryBitMask` (default 1) with `Camera.categoryBitMask`, the `lightCategoryBitMask` of a light node, and the mask that you give to `hitTest`. A tap in `SceneView` hits only nodes that the camera sees. `hitTestCategoryBitMask` limits these nodes more.
- **Rendering order.** `node.renderingOrder` draws lower values first. In one value, each renderer keeps its own order. Depth testing stays on, so order alone does not draw overlays on top. Order matters for transparent materials, which blend in this order.
