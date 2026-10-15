# MetalSprocketsSceneGraph

A format-neutral 3D scene graph for [MetalSprockets](https://github.com/schwa/MetalSprockets). You build a tree of nodes with meshes, lights and cameras. Then you render it with one or more material renderers: Blinn-Phong, PBR (through [MetalSprocketsPBR](../MetalSprocketsPBR)), or your own.

## Libraries

| Product | Contents |
|---|---|
| `MetalSprocketsSceneGraph` | `SceneGraph`, `SceneGraph.Node`, transforms (`TRS`), materials protocol, bounds, change tracking, animation clips, morph targets, skins. No renderer code. |
| `MetalSprocketsSceneGraphRenderer` | `SceneGraphElement`, the `SceneGraphMaterialRenderer` protocol, and the Blinn-Phong renderer. |
| `MetalSprocketsSceneGraphPBR` | `PBRSceneMaterial` and `PBRMaterialRenderer`. Depends on `../MetalSprocketsPBR` (local path). |
| `MetalSprocketsSceneGraphModelIO` | `ModelIOSceneGraph(url:device:materials:)`: loads any format `MDLAsset` reads (OBJ, PLY, STL, ABC, USD) into a `SceneGraph`, keeping the object hierarchy, with PBR or Blinn-Phong materials, cameras, lights and keyframed transforms. |
| `MetalSprocketsSceneGraphGLTF` | `GLTFAsset.makeSceneGraph(device:)`: loads a glTF scene (hierarchy, meshes with PBR materials, cameras, lights, skins, morph targets, node animations) into a `SceneGraph`. Depends on `../MetalSprocketsGLTF` (local path). |
| `MetalSprocketsSceneGraphDemos` | All demos, their SwiftUI views and a DemoKit picker (`SceneGraphDemosScene`). Depends on DemoKit and SwiftJolt. |
| `scenegraph-demos` (executable) | Runs the demos from the command line. |

Requirements: iOS 26, macOS 26 or visionOS 26; Swift 6.2.

## Build a scene

```swift
let device = MTLCreateSystemDefaultDevice()!
let box = MetalMesh(mesh: .box(), device: device)

let root = SceneGraph.Node(label: "Root")
let camera = SceneGraph.Node(parent: root, label: "Camera", content: .camera(Camera(projection: PerspectiveProjection(verticalAngleOfView: .degrees(45)))))
camera.trs.translation = [0, 1, 6]
let light = SceneGraph.Node(parent: root, label: "Light", content: .light(Light(type: .point, color: [1, 1, 1], intensity: 20, range: 100)))
light.trs.translation = [2, 3, 2]
let crate = SceneGraph.Node(parent: root, label: "Crate", content: .mesh(box, material: BlinnPhongMaterial(
    ambient: .color(0.1), diffuse: .color([0.8, 0.5, 0.2]), specular: .color(0.3), shininess: 16
)))

let sceneGraph = SceneGraph(root: root)
```

- **Hierarchy.** `Node(parent:)` adds the node to its parent. You can also use `addChild`, `insertChild(_:at:)`, `removeFromParent()` and `removeAllChildren()`. You cannot set `parent` and `children` directly. A child that would make a cycle causes a precondition failure.
- **Transforms.** A node stores a raw matrix (`transform`) or translation, rotation and scale (`trs`). Edits through `trs` are lossless. If you read `trs` from a matrix node, the matrix is decomposed. `worldTransform` gives the node's world-space matrix.
- **Category masks and order.** Like SceneKit: `node.categoryBitMask` (default 1) is matched against `Camera.categoryBitMask`, a light node's `lightCategoryBitMask` and `hitTest(_:categoryBitMask:)`. `node.renderingOrder` draws lower values first; within one value each renderer keeps its own order. Depth testing stays on, so order alone does not make overlays draw on top; it matters for transparent materials (`ShaderMaterial(isTransparent: true)`), which blend in this order. `SceneView` taps only hit nodes the camera sees, further limited by `hitTestCategoryBitMask`.
- **Visibility.** Set `isVisible = false` to hide a node and its subtree in rendering, queries and bounds.
- **Shapes.** `Node(shape:material:device:)` makes a mesh node from a `SceneGraph.Shape` (box, sphere, plane, cylinder, cone, capsule, torus, extruded text), like SceneKit's `SCNBox` or `SCNText`. Set `node.shape` to change the parameters; the mesh is rebuilt and the materials are kept.
- **Materials.** `.mesh(mesh, material:)` uses one material for all submeshes. `.mesh(mesh, materials:)` sets one material per submesh. The last material is used for submeshes after the end of the array.

## Render

The simplest way is `SceneView` (in `MetalSprocketsSceneGraphUI`), like SceneKit's SwiftUI `SceneView`:

```swift
SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl, .autoenablesDefaultLighting]) { hit in
    print(hit?.node.label ?? "nothing")
}
```

It runs node actions every frame, calls an optional `SceneViewDelegate` for per-frame updates, and frames the scene with a default camera when it has no camera node. For more control, put a `SceneGraphElement` in a `RenderView`. Give it one renderer for each material family that the scene uses:

```swift
@State private var pbrRenderer = PBRMaterialRenderer(device: MTLCreateSystemDefaultDevice()!)

RenderView { _, size in
    SceneGraphElement(
        sceneGraph: sceneGraph,
        aspectRatio: Float(size.width / size.height),
        renderers: [BlinnPhongMaterialRenderer(), pbrRenderer]
    )
}
```

- **Camera.** The default camera is the first camera node, placed by its world transform. Use `camera:` to select a different camera node. Use `cameraMatrix:` to override the camera's world transform, for example with an interactive camera.
- **One pass.** All renderers draw in one render pass and share the depth buffer. The pass uses **reversed depth** (near 1, far 0, compare `.greater`), because MetalSprocketsPBR requires it. `SceneGraphRenderContext.projectionMatrix` already contains the depth flip. If you write a renderer, use `.greater` depth tests.
- **Environment.** `sceneGraph.environment` sets the background (`.none`, `.color`, or `.environment(blur:)`) and the image-based lighting map, intensity and rotation. A `PBREnvironment` (procedural, equirectangular or cube map) works as the map. `PBRMaterialRenderer` uses it for lighting and draws the `.environment` background; without a map it uses its own `environment`. Blinn-Phong ignores the map.
- **Fog.** `sceneGraph.fog = SceneGraph.Fog(color:startDistance:endDistance:densityExponent:)`, like SceneKit's fog properties. A screen-space pass after every renderer blends it into geometry by camera distance (the background is not fogged), so it needs the same texture usage as shadows; `SceneView` sets this up.
- **Shadows.** Pass a `SceneGraphShadows` (keep one instance) to `SceneView(shadows:)` or `SceneGraphElement(shadows:)`. Directional, spot and point lights cast shadow maps from meshes with `castsShadow`; a screen-space pass then darkens shadowed pixels, so it works with every renderer. The view's color texture needs `.shaderWrite` and its depth texture `.shaderRead` usage; `SceneView` sets this up.
- **Unclaimed meshes.** The element does not draw meshes whose material type has no renderer.
- **Blinn-Phong only.** `BlinnPhongSceneGraphElement` is a shortcut for a `SceneGraphElement` with only the Blinn-Phong renderer.
- **Keep the PBR renderer.** `PBRMaterialRenderer` caches its `PBRModel` and rebuilds it only for structure changes. Keep one instance across frames, for example in `@State`, so that the cache is used.

### Custom shaders

`ShaderMaterial(vertexShader:fragmentShader:parameters:)` draws a mesh with your own Metal functions, like SceneKit's `SCNProgram`. Add one `ShaderMaterialRenderer()` to the renderers and it draws every `ShaderMaterial`. The vertex function must declare `constant ShaderMaterialTransforms &transforms` (see `ShaderMaterial.h` in `MetalSprocketsSceneGraphShaders`); `parameters` are bound by name. `ShaderMaterial.normals()` and `ShaderMaterial.rim(color:)` are samples.

### Add a material family

```swift
struct UnlitMaterial: MetalSprocketsSceneGraph.Material { var color: SIMD3<Float> }

struct UnlitRenderer: SceneGraphMaterialRenderer {
    var materialType: any MetalSprocketsSceneGraph.Material.Type { UnlitMaterial.self }
    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        // Draw entries[i].mesh.submeshes[entries[i].submeshIndex] at entries[i].worldTransform.
    }
}
```

You do not change the scene graph core.

## Change tracking, bounds, queries

- **Revisions.** `SceneGraph.revision` has a `structure` and a `transform` value. Hierarchy, content, visibility, skin and morph target edits change `structure`. Transform and morph weight edits change `transform`. Compare revisions to skip work.
- **Cached queries.** `meshEntries()`, `lightNodes()` and `cameraNodes()` share one traversal, cached by revision.
- **Hit testing.** `SceneGraph.hitTest(_:)` returns every triangle a `SceneGraph.Ray` hits, nearest first, with node, submesh, triangle index, distance, position and normal. Skinned and morphed meshes use their deformed positions. `Ray(viewPoint:viewSize:cameraMatrix:projectionMatrix:)` makes the ray for a point in a view.
- **Bounds.** `Node.meshBounds`, `Node.subtreeBounds`, `SceneGraph.bounds` and `SceneGraph.worldBounds(of:)` return `BoundingBox` values. They are cached by revision.

## Animation, morph targets, skins

- **Clips.** `SceneGraph.AnimationClip` has channels that animate node translation, rotation, scale or morph weights. Interpolation can be step, linear (slerp for rotations) or glTF cubic spline. Call `clip.apply(at:looping:)`, or use an `AnimationPlayer` and call `advance(by:)` each frame.
- **Actions.** Like SceneKit's `SCNAction`: `node.run(.sequence([.move(by: [0, 1, 0], duration: 1), .rotate(by: .pi, around: [0, 1, 0], duration: 1)]), forKey: "hop")`. There are move, rotate and scale (by and to), wait, custom, run, hide, unhide, removeFromParent, sequence, group, repeat and repeatForever, with timing modes. Call `sceneGraph.advanceActions(by:)` each frame. No fade actions (nodes have no opacity).
- **Implicit animation.** Like `SCNTransaction`: `SceneGraph.Transaction.animate(duration: 0.5) { node.trs.translation = [0, 2, 0] }` animates transform and morph weight changes from their old values. It runs as node actions, so it needs `advanceActions(by:)` (SceneView does this). `Transaction.withoutAnimation { }` applies changes at once.
- **Constraints.** Like SceneKit's constraints: `node.constraints = [.lookAt(target: other)]`, `.billboard()` (or `.billboard(freeAxes: .y)`) and `.distance(target:minimum:maximum:)`. `SceneView` applies them each frame after actions; otherwise call `sceneGraph.applyConstraints(pointOfView:)`. No IK yet.
- **Morph targets.** `Node.morphTargets` holds per-vertex deltas. `Node.morphWeights` holds the weights. Morph targets are on the node because `MetalMesh` cannot hold them.
- **Skins.** `Node.skin` (a `SceneGraph.Skin` with joint nodes and inverse bind matrices) and `Node.skinVertices` hold skinning data. Joints are ordinary nodes, so you can animate them like other nodes.

## Limitations

- Only the PBR renderer draws morph targets and skins. Blinn-Phong draws the base mesh (#34).
- The Blinn-Phong shader supports only point lights. It has no instancing and no transparency (#24, #32).
- Shadows use 8 shadow map slices (a directional or spot light takes one, a point light six), and `receivesShadow` is ignored (every surface behind a caster is darkened).
- glTF loading skips EXT_mesh_gpu_instancing copies, KHR_node_visibility, orthographic cameras and non-node animation channels. USD is a long-term goal (#31).
- Model I/O loading skips skins, blend shapes, orthographic cameras, and normal, metallic, roughness and occlusion textures.
- Position, bounds and PBR conversion read mesh vertex buffers on the CPU. The buffers must use shared storage.

## Demo

The demos live in the `MetalSprocketsSceneGraphDemos` target and use DemoKit for the picker. Each has a scene outline, a node inspector, an interactive camera and click-to-pick.

- **Xcode:** `Demo/MetalSprocketsSceneGraphDemo.xcodeproj` is a thin app around `SceneGraphDemosScene`.
- **Command line:** `xcb run scenegraph-demos` opens the picker. `scenegraph-demos --list` lists demo ids, and `scenegraph-demos --render <id> [file.png] [--size 1280x800] [--frames 60]` renders a demo offscreen to a PNG without opening a window.
