# Getting Started

Build a tree of nodes and show it in SwiftUI.

## Build a scene

```swift
import SceneSprockets
import SceneSprocketsBlinnPhong

let device = MTLCreateSystemDefaultDevice()!

let root = SceneGraph.Node(label: "Root")

let camera = SceneGraph.Node(parent: root, label: "Camera", content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
camera.trs.translation = [0, 1, 6]

let light = SceneGraph.Node(parent: root, label: "Light", content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20, range: 100)))
light.trs.translation = [2, 3, 2]

let material = BlinnPhongSceneMaterial(ambient: .color(0.1), diffuse: .color([0.8, 0.5, 0.2]), specular: .color(0.3), shininess: 16)
let crate = SceneGraph.Node(parent: root, label: "Crate", shape: .box(), material: material, device: device)

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

- **Hierarchy.** `Node(parent:)` adds the node to its parent. You can also use `addChild`, `insertChild(_:at:)`, `removeFromParent()` and `removeAllChildren()`. You cannot set `parent` and `children` directly. A child that would make a cycle causes a precondition failure.
- **Transforms.** A node stores a matrix (`transform`) or translation, rotation and scale (`trs`). Edits through `trs` do not lose data. If you read `trs` from a matrix node, the matrix is decomposed. `worldTransform` gives the node's world-space matrix.
- **Shapes.** `Node(shape:material:device:)` makes a mesh node from a ``SceneGraph/Shape``: box, sphere, plane, cylinder, cone, capsule, torus or extruded text, like SceneKit's `SCNBox` or `SCNText`. Set `node.shape` to change the parameters. The mesh is rebuilt and the materials are kept.
- **Materials.** `.mesh(mesh, material:)` uses one material for all submeshes. `.mesh(mesh, materials:)` sets one material for each submesh. Submeshes after the end of the array use the last material.
- **Visibility and opacity.** Set `isVisible = false` to hide a node and its subtree in rendering, queries and bounds. `opacity` is multiplied down the tree.
- **Category masks.** Like SceneKit, `node.categoryBitMask` (default 1) is compared with `Camera.categoryBitMask`, a light node's `lightCategoryBitMask` and the mask given to `hitTest`. `SceneView` taps hit only nodes that the camera sees, further limited by `hitTestCategoryBitMask`.
- **Rendering order.** `node.renderingOrder` draws lower values first. In one value, each renderer keeps its own order. Depth testing stays on, so order alone does not draw overlays on top. Order matters for transparent materials, which blend in this order.
