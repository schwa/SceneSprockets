# Using SceneSprockets

Details behind the short examples in the [README](../README.md).

## Build a scene

- **Hierarchy.** `Node(parent:)` adds the node to its parent. You can also use `addChild`, `insertChild(_:at:)`, `removeFromParent()` and `removeAllChildren()`. You cannot set `parent` and `children` directly. A child that would make a cycle causes a precondition failure.
- **Transforms.** A node stores a raw matrix (`transform`) or translation, rotation and scale (`trs`). Edits through `trs` are lossless. If you read `trs` from a matrix node, the matrix is decomposed. `worldTransform` gives the node's world-space matrix.
- **Category masks and order.** Like SceneKit: `node.categoryBitMask` (default 1) is matched against `Camera.categoryBitMask`, a light node's `lightCategoryBitMask` and `hitTest(_:categoryBitMask:)`. `node.renderingOrder` draws lower values first; within one value each renderer keeps its own order. Depth testing stays on, so order alone does not make overlays draw on top; it matters for transparent materials (`ShaderMaterial(isTransparent: true)`), which blend in this order. `SceneView` taps only hit nodes the camera sees, further limited by `hitTestCategoryBitMask`.
- **Visibility.** Set `isVisible = false` to hide a node and its subtree in rendering, queries and bounds.
- **Shapes.** `Node(shape:material:device:)` makes a mesh node from a `SceneGraph.Shape` (box, sphere, plane, cylinder, cone, capsule, torus, extruded text), like SceneKit's `SCNBox` or `SCNText`. Set `node.shape` to change the parameters; the mesh is rebuilt and the materials are kept.
- **Materials.** `.mesh(mesh, material:)` uses one material for all submeshes. `.mesh(mesh, materials:)` sets one material per submesh. The last material is used for submeshes after the end of the array.

## Render

The simplest way is `SceneView`, like SceneKit's SwiftUI `SceneView`:

```swift
SceneView(sceneGraph: sceneGraph, options: [.allowsCameraControl, .autoenablesDefaultLighting], renderers: [BlinnPhongMaterialRenderer()]) { hit in
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
- **Environment.** `sceneGraph.environment` sets the background (`.none`, `.color`, `.environment(blur:)`, or `.gradient(SkyGradient)`, a zenith/horizon/ground sky that works with any renderer) and the image-based lighting map, intensity and rotation. A `PBREnvironment` (procedural, equirectangular or cube map) works as the map. `PBRMaterialRenderer` uses it for lighting and draws the `.environment` background; without a map it uses its own `environment`. Blinn-Phong ignores the map.
- **Fog.** `sceneGraph.fog = SceneGraph.Fog(color:startDistance:endDistance:densityExponent:)`, like SceneKit's fog properties. A screen-space pass after every renderer blends it into geometry by camera distance (the background is not fogged), so it needs the same texture usage as shadows; `SceneView` sets this up.
- **Shadows.** Pass a `SceneGraphShadows` (keep one instance) to `SceneView(shadows:)` or `SceneGraphElement(shadows:)`. Directional, spot and point lights cast shadow maps from meshes with `castsShadow`; a screen-space pass then darkens shadowed pixels, so it works with every renderer. The view's color texture needs `.shaderWrite` and its depth texture `.shaderRead` usage; `SceneView` sets this up.
- **Unclaimed meshes.** The element does not draw meshes whose material type has no renderer.
- **Blinn-Phong only.** `BlinnPhongSceneGraphElement` is a shortcut for a `SceneGraphElement` with only the Blinn-Phong renderer.
- **Keep the PBR renderer.** `PBRMaterialRenderer` caches its `PBRModel` and rebuilds it only for structure changes. Keep one instance across frames, for example in `@State`, so that the cache is used.

### Custom shaders

`ShaderMaterial(vertexShader:fragmentShader:parameters:)` draws a mesh with your own Metal functions, like SceneKit's `SCNProgram`. Add one `ShaderMaterialRenderer()` to the renderers and it draws every `ShaderMaterial`. The vertex function must declare `constant ShaderMaterialTransforms &transforms` (see `ShaderMaterial.h` in `SceneSprocketsShaders`); `parameters` are bound by name. `ShaderMaterial.normals()` and `ShaderMaterial.rim(color:)` are samples.

### Add a material family

```swift
struct UnlitMaterial: SceneSprockets.Material { var color: SIMD3<Float> }

struct UnlitRenderer: SceneGraphMaterialRenderer {
    var materialType: any SceneSprockets.Material.Type { UnlitMaterial.self }
    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        // Draw entries[i].mesh.submeshes[entries[i].submeshIndex] at entries[i].worldTransform.
    }
}
```

You do not change the scene graph core.

## Change tracking, bounds, queries

- **Revisions.** `SceneGraph.revision` has a `structure` and a `transform` value. Hierarchy, content, visibility, skin and morph target edits change `structure`. Transform and morph weight edits change `transform`. Compare revisions to skip work.
- **Cached queries.** `meshEntries()`, `lightNodes()` and `cameraNodes()` share one traversal, cached by revision.
- **Hit testing.** `SceneGraph.hitTest(_:)` returns every triangle a GeometryLite3D `Ray3D` hits, nearest first, with node, submesh, triangle index, distance, position and normal. Skinned and morphed meshes use their deformed positions. `ViewProjection.ray(through:)` makes the ray for a point in a view.
- **Bounds.** `Node.meshBounds`, `Node.subtreeBounds`, `SceneGraph.bounds` and `SceneGraph.worldBounds(of:)` return `BoundingBox3D` values. They are cached by revision.

## Animation, morph targets, skins

- **Clips.** `SceneGraph.AnimationClip` has channels that animate node translation, rotation, scale or morph weights. Interpolation can be step, linear (slerp for rotations) or glTF cubic spline. Call `clip.apply(at:looping:)`, or use an `AnimationPlayer` and call `advance(by:)` each frame.
- **Actions.** Like SceneKit's `SCNAction`: `node.run(.sequence([.move(by: [0, 1, 0], duration: 1), .rotate(by: .pi, around: [0, 1, 0], duration: 1)]), forKey: "hop")`. There are move, rotate and scale (by and to), wait, custom, run, hide, unhide, removeFromParent, sequence, group, repeat and repeatForever, with timing modes. Call `sceneGraph.advanceActions(by:)` each frame. `fadeIn`, `fadeOut` and `fadeOpacity(to:)` / `fadeOpacity(by:)` animate the node's opacity.
- **Implicit animation.** Like `SCNTransaction`: `SceneGraph.Transaction.animate(duration: 0.5) { node.trs.translation = [0, 2, 0] }` animates transform and morph weight changes from their old values. It runs as node actions, so it needs `advanceActions(by:)` (SceneView does this). `Transaction.withoutAnimation { }` applies changes at once.
- **Constraints.** Like SceneKit's constraints: `node.constraints = [.lookAt(target: other)]`, `.billboard()` (or `.billboard(freeAxes: .y)`) and `.distance(target:minimum:maximum:)`, plus `.replicator`, `.avoidOccluder`, `.inverseKinematics`, `.acceleration` and `.transform` for a custom closure. `SceneView` applies them each frame after actions; otherwise call `sceneGraph.applyConstraints(pointOfView:)`.
- **Morph targets.** `Node.morphTargets` holds per-vertex deltas. `Node.morphWeights` holds the weights. Morph targets are on the node because `MetalMesh` cannot hold them.
- **Skins.** `Node.skin` (a `SceneGraph.Skin` with joint nodes and inverse bind matrices) and `Node.skinVertices` hold skinning data. Joints are ordinary nodes, so you can animate them like other nodes.

## Demo tests

- **Golden images:** the demo package's tests render some demos offscreen and compare them with images in `Tests/SceneSprocketsDemosTests/Golden Images`. A missing golden fails the test and writes the render to `$TMPDIR/SceneSprocketsDemos-GoldenImages`; check it, then copy it in.
