# ISSUES.md

---

## 1: Scene is too dark — crank up lighting

+++
status: closed
priority: high
kind: bug
created: 2026-04-14T19:38:13Z
updated: 2026-04-14T19:39:49Z
closed: 2026-04-14T19:39:49Z
+++

Everything renders very dark. Increase ambient light, light intensities, and material ambient values.

- `2026-04-14T19:39:49Z`: Increased ambient light, light intensities, and material ambient/specular values.

---

## 2: Add interactive camera support from Interaction3D

+++
status: closed
priority: high
kind: feature
created: 2026-04-14T19:38:16Z
updated: 2026-04-14T19:40:52Z
closed: 2026-04-14T19:40:52Z
+++

Integrate the Interaction3D package's interactive camera modifier so the user can orbit/pan/zoom the camera in the demo.

- `2026-04-14T19:40:52Z`: Added Interaction3D import and .interactiveCamera(cameraMatrix:) modifier. Camera matrix is now a @State driving the view/camera matrices for the render pass.

---

## 3: Add NavigationSplitView with scene outline sidebar

+++
status: closed
priority: high
kind: feature
created: 2026-04-14T19:38:20Z
updated: 2026-04-14T19:39:52Z
closed: 2026-04-14T19:39:52Z
+++

Wrap the demo render view in a NavigationSplitView. Put a scene graph outline (tree of nodes with icons for mesh/light/camera/empty) in the sidebar.

- `2026-04-14T19:39:52Z`: Added NavigationSplitView with SceneOutlineView sidebar showing node tree with icons for mesh/light/camera/empty.

---

## 4: Move demo scene creation into a reusable package

+++
status: closed
priority: medium
kind: feature
created: 2026-04-14T19:39:20Z
updated: 2026-04-14T19:53:52Z
closed: 2026-04-14T19:53:52Z
+++

Extract the demo scene setup (makeScene) into the MetalSprocketsSceneGraphDemoSupport package (or a new package) so it can be reused by other projects.

- `2026-04-14T19:53:52Z`: Moved demo scene creation (makeDemoScene) into MetalSprocketsSceneGraphDemoSupport target in root Package.swift. Removed old Demo/Packages/MetalSprocketsSceneGraphDemoSupport local package.

---

## 5: Move RenderPass into a separate reusable target

+++
status: closed
priority: medium
kind: feature
created: 2026-04-14T19:40:18Z
updated: 2026-04-14T19:53:52Z
closed: 2026-04-14T19:53:52Z
+++

Extract the BlinnPhong RenderPass rendering code into a new target that depends on the main MetalSprocketsSceneGraph target, so other projects can reuse the scene graph rendering pipeline without duplicating it.

- `2026-04-14T19:53:52Z`: Extracted BlinnPhong render pass into MetalSprocketsSceneGraphRenderer target with renderBlinnPhongSceneGraph() public function. Returns AnyElement for use in RenderView closures.

---

## 6: Add editor/inspector for tapped nodes

+++
status: closed
priority: medium
kind: feature
created: 2026-04-14T19:42:12Z
updated: 2026-04-14T20:14:27Z
closed: 2026-04-14T20:14:27Z
+++

When a node is selected in the scene outline sidebar, show an inspector panel with editable properties (transform, material, light params, etc.).

- `2026-04-14T20:14:27Z`: Added NodeInspectorView as trailing inspector panel. Shows general info, transform matrix, and content-specific sections (light color/intensity, mesh material properties with color swatches, camera projection).

---

## 7: Remove MetalSprockets from target names

+++
status: closed
priority: low
kind: enhancement
labels: effort:xs, area:build
created: 2026-04-14T20:11:34Z
updated: 2026-10-11T21:28:29Z
closed: 2026-10-11T21:28:29Z
+++

Shorten target names by dropping the MetalSprockets prefix (e.g. MetalSprocketsSceneGraphRenderer → SceneGraphRenderer, MetalSprocketsSceneGraphDemoSupport → SceneGraphDemoSupport).

- `2026-10-11T21:28:29Z`: Won't fix: prefix matches sibling packages (MetalSprocketsAddOns etc.) and a bare SceneGraph module would collide with the SceneGraph type.

---

## 8: renderBlinnPhongSceneGraph should be an Element type

+++
status: closed
priority: medium
kind: enhancement
created: 2026-04-14T20:14:19Z
updated: 2026-04-14T20:20:07Z
closed: 2026-04-14T20:20:07Z
+++

Refactor renderBlinnPhongSceneGraph from a free function into a proper MetalSprockets Element struct containing a RenderPass. This would make it composable within the MetalSprockets DSL.

- `2026-04-14T20:20:07Z`: Refactored into BlinnPhongSceneGraphElement struct conforming to Element protocol. Contains RenderPass in its body property. Old free function removed.

---

## 9: Renderer assumes all meshes share the first mesh's vertex descriptor

+++
status: closed
priority: high
kind: bug
labels: effort:m, area:renderer
created: 2026-05-14T15:57:05Z
updated: 2026-10-11T21:36:06Z
closed: 2026-10-11T21:36:06Z
+++

BlinnPhongSceneGraphElement passes `firstMesh.mesh.vertexDescriptor` to the render pipeline, but then draws every mesh through that single pipeline. If any other mesh in the scene has a different attribute layout (e.g. textured vs untextured, different normal format, separate-buffer layout), Metal will either fetch garbage or fail to compile the pipeline.

Repro: add one mesh with normals + texcoords and another with only positions to the same SceneGraph — only the first descriptor wins.

Options:
- Group meshes by vertex descriptor and emit one pipeline per group.
- Require a canonical descriptor and assert/convert on insertion.
- Build a union descriptor and ensure all meshes conform.

---

## 10: SceneGraph.Node mutability is unsafe and ergonomically weak

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-05-14T15:57:11Z
updated: 2026-10-12T15:03:18Z
closed: 2026-10-12T15:03:18Z
+++

`SceneGraph.Node` is a class with mutable `parent`/`children` that callers mutate by hand. Risks:

- No cycle detection (a node can become its own ancestor).
- `parent` and `children` can desync because both are set manually at call sites.
- No reparenting/remove helpers — every demo redefines `addChild`.

Consider:
- `addChild(_:)` / `removeFromParent()` API on Node that maintains invariants.
- Make `parent` weak and read-only from outside.
- Optional debug assertions for cycles.

---

## 11: No frustum culling, sorting, or instancing in renderer

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:renderer
created: 2026-05-14T15:57:17Z
updated: 2026-10-12T15:06:48Z
closed: 2026-10-12T15:06:48Z
+++

BlinnPhongSceneGraphElement draws every mesh entry in traversal order with no:

- Frustum culling (bounds vs camera frustum).
- Sort by material/pipeline (state thrash) or front-to-back (overdraw).
- Opaque vs transparent split.
- Instancing for repeated meshes (e.g. the physics demo stacks 15 identical crates — 15 draw calls).

For non-trivial scenes this is the difference between toy and usable.

- `2026-10-11T21:31:54Z`: MetalSprocketsPBR already does culling, batching and merging, so the PBR path (#26) gets these mostly for free. This issue is now about the Blinn-Phong renderer and about renderer-independent inputs: bounds (#28) and instancing data on the graph.
- `2026-10-12T15:06:48Z`: Done: frustum culling and front-to-back sorting in the Blinn-Phong renderer (PBR already culls). Instancing and opaque/transparent split moved to #32.

---

## 12: castsShadow/receivesShadow flags are dead metadata

+++
status: closed
priority: medium
kind: bug
labels: effort:l, area:renderer
created: 2026-05-14T15:57:22Z
updated: 2026-10-13T21:24:15Z
closed: 2026-10-13T21:24:15Z
+++

`SceneGraph.Node.Content.mesh` carries `castsShadow` / `receivesShadow` flags, and `SceneGraph` exposes `shadowCasters()` / `shadowReceivers()`, but the renderer (BlinnPhongSceneGraphElement) doesn't implement a shadow pass. The flags currently do nothing.

Either:
- Implement a shadow pass (depth-only pre-pass per shadow-casting light, sampled in fragment shader), or
- Remove the flags + helpers until the feature exists, so the API doesn't lie.

- `2026-10-11T21:31:55Z`: PBR has its own approach to lighting; decide whether shadows are per-renderer or a shared scene graph feature.
- `2026-10-11T21:43:47Z`: Looked at both options. MetalSprocketsPBR has no shadow support at all, and the Blinn-Phong path would need AddOns' ShadowMapTechnique wired into BlinnPhongMaterialRenderer plus shader sampling. So implementing means shadow work in two renderers (one in another repo); removing the flags is an API decision. Punting: needs a product call. Unblocker: choose (a) remove castsShadow/receivesShadow and shadowCasters()/shadowReceivers() until a shadow feature exists, or (b) keep them and implement shadows, Blinn-Phong first via ShadowMapTechnique, PBR later.
- `2026-10-12T15:21:28Z`: Decision: deferred. Revisit when a shadow feature is planned.
- `2026-10-13T21:24:15Z`: Implemented renderer-agnostic shadow maps: SceneGraphShadows (directional lights, castsShadow honored) + AddOns ShadowMaskPass in screen space; SceneView(shadows:) configures the drawable. Test renders a box over a floor offscreen and checks the shadowed spot darkens (and does not for castsShadow: false). Not verified in the app. receivesShadow still ignored; filed follow-up.

---

## 13: Support multiple material types and renderers per scene

+++
status: closed
priority: high
kind: enhancement
labels: effort:l, area:renderer
created: 2026-05-14T15:57:27Z
updated: 2026-10-11T21:39:14Z
closed: 2026-10-11T21:39:14Z
+++

meshNodes(withMaterial:) filters by one concrete material type, and BlinnPhongSceneGraphElement only draws BlinnPhongMaterial. The scene graph should support several material families (Blinn-Phong, PBR, and more later) in one scene.

Want:
- A material protocol that each renderer family conforms to.
- A SceneGraph element that partitions mesh nodes by material family in one traversal and runs each family's renderer, sharing camera, lights and depth.
- Adding a new family should not need changes to the scene graph core.

Blocks mixed scenes for #26 (PBR renderer).

---

## 14: Traversal allocates arrays every frame

+++
status: closed
priority: low
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-05-14T15:57:33Z
updated: 2026-10-12T15:17:11Z
closed: 2026-10-12T15:17:11Z
+++

`nodesWithWorldTransforms`, `meshNodes`, `lightNodes`, `cameraNodes` all allocate fresh `[(...)]` arrays per call. The renderer calls several of these per frame.

For a static scene graph this is wasted work and GC pressure. Options:

- Visitor APIs that don't materialize arrays.
- Cached flattened views invalidated on graph mutation.
- A dirty-flag world-transform cache so unchanged subtrees aren't re-multiplied each frame.

- `2026-10-11T21:31:55Z`: Related: #29 (change tracking).
- `2026-10-12T15:17:10Z`: Done: meshEntries/lightNodes/cameraNodes now share one traversal, cached by revision (#29), so static scenes do no traversal per frame and a frame's queries do one. Not done: per-subtree world-transform caching; any transform change still re-walks the whole graph. File separately if profiling shows it matters.

---

## 15: Node animation clips

+++
status: closed
priority: medium
kind: feature
labels: area:animation, effort:l
created: 2026-05-14T15:57:38Z
updated: 2026-10-12T15:08:11Z
closed: 2026-10-12T15:08:11Z
+++

SceneGraph supports static transforms only. Add format-neutral animation data: clips with channels that target node translation/rotation/scale (#20) and morph weights (#21), with step/linear/cubic interpolation, plus a player that samples a clip into the graph.

The glTF package already has this logic (GLTFAnimation, GLTFAnimationController, GLTFAnimationStateMachine). Move what glTF needs here as generic types, so other loaders can use it. Do not try to cover USD's animation features yet.

Skins: #30. Morph targets: #21.

- `2026-10-11T21:27:49Z`: Morph targets are also tracked separately in #21.

---

## 16: Load glTF into a SceneGraph

+++
status: closed
priority: high
kind: feature
labels: area:assets, effort:l
created: 2026-05-14T15:57:43Z
updated: 2026-10-13T20:37:09Z
closed: 2026-10-13T20:37:09Z
+++

Every scene is hand-built in code. Make MetalSprocketsGLTF able to produce a SceneGraph (nodes, TRS transforms, meshes with per-submesh PBR materials, lights, cameras, skins, morph weights, animations), so glTF scenes can be edited in code and rendered with the scene graph renderers.

Keep the scene graph format-neutral: no glTF types in this repo. The glue lives in the GLTF package or a small adapter target. See MetalSprocketsGLTF #121.

USD/USDZ: #31.

Depends on #19, #20, #26.

\- `2026-10-12T15:11:47Z`: Investigated; punting for design decisions that span repos. Scene graph side is ready (#19 per-submesh materials, #20 TRS, #26 PBR, #15 clips, #21 morphs, #30 skins).

Findings:
- GLTFAnimationClip.Channel/Target are internal, so an adapter outside MetalSprocketsGLTF cannot read animations. The adapter has to live in the GLTF package (new target, e.g. MetalSprocketsGLTFSceneGraph, depending on ../MetalSprocketsSceneGraph) or GLTF has to make those public.
- Geometry: GLTFAsset.meshes holds PBRModel.Primitives in merged buffers (baseVertex/indexStart, no per-primitive buffers). Plan: copy each glTF mesh into one MetalMesh, one submesh per primitive (rebased indices, per-submesh PBRSceneMaterial from asset.materials), and concatenate skin vertices and morph deltas into Node.skinVertices / Node.morphTargets.
- Lights/cameras: map KHR_lights_punctual per node (node.punctualLight) to scene graph Light, and glTF cameras to Camera(PerspectiveProjection). Orthographic cameras have no scene graph equivalent yet.

Unblocker: confirm (1) the adapter goes in MetalSprocketsGLTF as a new target and I may commit there, and (2) the one-MetalMesh-per-glTF-mesh mapping.

- `2026-10-12T15:21:28Z`: Decisions: adapter lives in MetalSprocketsSceneGraph (not GLTF); one MetalMesh per glTF mesh, one submesh per primitive.
- `2026-10-12T15:24:17Z`: Upstream: MetalSprocketsGLTF #153 (expose animation channels). Geometry, materials, hierarchy, skins and morphs can be loaded before that lands; animations wait for #153.
- `2026-10-13T20:37:09Z`: Added MetalSprocketsSceneGraphGLTF: GLTFAsset.makeSceneGraph(device:) loads hierarchy/TRS, one MetalMesh per glTF mesh (submesh per primitive, PBRSceneMaterial per primitive), perspective cameras, KHR_lights_punctual, skins, morph targets/weights, node animation channels. Not mapped: EXT_mesh_gpu_instancing, KHR_node_visibility, orthographic cameras, pointer animation channels (reported in warnings).

---

## 17: No tests for SceneGraph or renderer

+++
status: closed
priority: medium
kind: task
labels: effort:m, area:testing
created: 2026-05-14T15:57:47Z
updated: 2026-10-12T15:14:17Z
closed: 2026-10-12T15:14:17Z
+++

Verify and add coverage:

- Traversal order and accumulated world transforms.
- Material-typed filtering in `meshNodes(withMaterial:)`.
- Camera/light queries.
- Node parent/child invariants (once issue #10 lands).
- Snapshot or hash-of-render tests for BlinnPhongSceneGraphElement against a known scene.

---

## 18: Documentation is sparse

+++
status: closed
priority: low
kind: documentation
labels: effort:m, area:docs
created: 2026-05-14T15:57:54Z
updated: 2026-10-12T15:17:56Z
closed: 2026-10-12T15:17:56Z
+++

Public types (`SceneGraph`, `SceneGraph.Node`, `Light`, `Camera`, `BlinnPhongSceneGraphElement`) have minimal or no doc comments. Add:

- DocC comments on every public symbol.
- A README / DocC article covering: building a scene graph, attaching cameras/lights, rendering with BlinnPhongSceneGraphElement, current limitations.

---

## 19: Materials attach per node, not per submesh

+++
status: closed
priority: high
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-11T21:26:55Z
updated: 2026-10-11T21:37:29Z
closed: 2026-10-11T21:37:29Z
+++

Node.Content.mesh holds one material for the whole MetalMesh. glTF (and most formats) assign a material per primitive/submesh, so multi-material meshes can't be represented without splitting into child nodes.

- `2026-10-11T21:31:55Z`: Needed by #16 (glTF primitives each have their own material) and #26.

---

## 20: Node transform is a raw matrix with no TRS form

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s, area:scenegraph
created: 2026-10-11T21:26:55Z
updated: 2026-10-12T15:02:08Z
closed: 2026-10-12T15:02:08Z
+++

Node.transform is a float4x4 only. Animation systems (glTF channels target translation/rotation/scale separately) need decomposed TRS, and editing rotation/scale from a matrix is lossy.

- `2026-10-11T21:31:55Z`: Needed by #15 (animation channels target T/R/S separately).

---

## 21: No morph target support

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:animation
created: 2026-10-11T21:26:55Z
updated: 2026-10-12T15:09:18Z
closed: 2026-10-12T15:09:18Z
+++

Meshes have no blend shape/morph target data or per-node weights. Needed for glTF morph targets. Related to #15.

- `2026-10-11T21:27:49Z`: Overlaps with the morph-target bullet in umbrella #15.
- `2026-10-11T21:31:55Z`: Scope: blend-shape data on meshes and weights on nodes, format-neutral, enough for glTF morph targets. Animated by #15.

---

## 22: Renderer hardcodes uint32 indices and triangle primitives

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:renderer
created: 2026-10-11T21:26:55Z
updated: 2026-10-12T15:01:04Z
closed: 2026-10-12T15:01:04Z
+++

BlinnPhongSceneGraphElement draws every submesh with indexType .uint32 and primitiveType .triangle. Meshes with uint16 indices, lines, points, or strips render wrong.

- `2026-10-11T21:42:01Z`: Checked: SwiftMesh's MetalMesh.Submesh has no index type or primitive type; it is documented as UInt32 triangles and every MetalMesh init produces that. So the renderer's .uint32/.triangle matches every mesh this scene graph can hold today, and there is no failing case to reproduce here. Punting: the fix starts in SwiftMesh (add indexType/primitiveType to MetalMesh.Submesh) or in a scene graph mesh type that is not MetalMesh (likely needed for glTF, #16). Unblocker: decide which, then the renderer change is small. Note the PBR path (#26) already passes primitiveType through PBRGeometryBuilder.
- `2026-10-11T21:48:27Z`: Filed upstream: SwiftMesh #108 (add indexType/primitiveType to MetalMesh.Submesh).

---

## 23: Renderer ignores camera node's transform

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:renderer
created: 2026-10-11T21:26:55Z
updated: 2026-10-11T21:43:02Z
closed: 2026-10-11T21:43:02Z
+++

BlinnPhongSceneGraphElement takes cameraMatrix as a parameter and only uses the first camera node's projection. The camera node's world transform is ignored, so cameras placed in the scene graph have no effect on the view. Other camera nodes are also ignored.

- `2026-10-11T21:31:55Z`: Also applies to the PBR renderer (#26): the camera node's world transform should drive the view matrix in every renderer.

---

## 24: Blinn-Phong lights use only position, not orientation

+++
status: closed
priority: medium
kind: bug
labels: area:renderer, effort:m
created: 2026-10-11T21:26:55Z
updated: 2026-10-12T15:38:55Z
closed: 2026-10-12T15:38:55Z
+++

The renderer builds Lighting from each light node's world translation only. Directional and spot lights need the node's orientation, which is dropped.

- `2026-10-11T21:31:55Z`: Also applies to the PBR renderer (#26): PBRLight needs a direction from the node's world rotation.
- `2026-10-11T21:43:31Z`: PBR path: fixed in #26 (pbrLight maps node -Z to PBRLight.direction); regression test pbrLightDirectionFollowsNodeRotation added. Blinn-Phong: punting. The AddOns Blinn-Phong shader (BlinnPhongShaders.metal) treats every light as a point light and Lighting only carries lightPositions, so there is nowhere to pass a direction from here. Unblocker: add light directions (and directional/spot handling) to Lighting + BlinnPhongShaders in MetalSprocketsAddOns, then pass the node's -Z axis from BlinnPhongMaterialRenderer.
- `2026-10-12T15:22:46Z`: Upstream: MetalSprocketsAddOns #91 (directional/spot lights in Blinn-Phong). Plan: implement there, push, then pass node directions from BlinnPhongMaterialRenderer.

---

## 25: BlinnPhongMaterial conformance uses @unchecked Sendable

+++
status: closed
priority: low
kind: task
labels: effort:s, area:renderer
created: 2026-10-11T21:26:55Z
updated: 2026-10-12T15:15:27Z
closed: 2026-10-12T15:15:27Z
+++

Material requires Sendable, so the renderer adds a retroactive @unchecked Sendable to BlinnPhongMaterial. This hides possible data races. Related to #10.

- `2026-10-12T15:15:27Z`: Fixed by dropping the Sendable requirement from Material. A checked retroactive conformance is not allowed (Sendable must be declared in the type's file), and MTLTexture/MTLSamplerState are not Sendable in the current SDK, so BlinnPhongMaterial can never be checked-Sendable. Node is a non-Sendable class anyway, so the requirement bought nothing. No regression test: this is a compile-time property.

---

## 26: Render a SceneGraph with MetalSprocketsPBR

+++
status: closed
priority: high
kind: feature
labels: effort:l, area:renderer
created: 2026-10-11T21:31:42Z
updated: 2026-10-11T21:41:44Z
closed: 2026-10-11T21:41:44Z
+++

Add a PBR renderer next to the Blinn-Phong one. Build a PBRModel and PBRPose from the scene graph's mesh nodes with PBR materials and draw with PBRScene, so scenes get PBR, IBL, transmission, culling and batching. Needs a PBR material type usable on nodes. See MetalSprocketsGLTF #121. Depends on #13 for mixed-material scenes.

---

## 27: Per-node visibility

+++
status: closed
priority: low
kind: feature
labels: effort:s, area:scenegraph
created: 2026-10-11T21:31:42Z
updated: 2026-10-12T15:16:17Z
closed: 2026-10-12T15:16:17Z
+++

Add a visibility flag on Node that hides the node and its subtree in every renderer. glTF KHR_node_visibility needs it.

---

## 28: Per-node and per-mesh bounds

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-11T21:31:43Z
updated: 2026-10-12T15:05:41Z
closed: 2026-10-12T15:05:41Z
+++

Nodes have no bounding boxes. Add local mesh bounds and cached world bounds per node. Needed for culling (#11), camera framing and picking. Should be renderer-independent.

---

## 29: Change tracking for cheap renderer updates

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-11T21:31:43Z
updated: 2026-10-12T15:04:39Z
closed: 2026-10-12T15:04:39Z
+++

Renderers rebuild everything each frame. Track what changed (transforms only vs structure, materials, meshes) so a renderer can update a pose without rebuilding its model. Matters most for the PBR path, where PBRModel is costly to build. Related to #14.

---

## 30: Skins and joints in the scene graph

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:animation
created: 2026-10-11T21:31:43Z
updated: 2026-10-12T15:11:01Z
closed: 2026-10-12T15:11:01Z
+++

Add format-neutral skin data: joint node references, inverse bind matrices, and per-vertex joints/weights on meshes. Renderers compute joint palettes from node world transforms. Scope to what glTF needs. Split from #15.

---

## 31: Load USD/USDZ into a SceneGraph

+++
status: open
priority: low
kind: feature
labels: effort:xl, area:assets, deferred
created: 2026-10-11T21:31:43Z
updated: 2026-10-13T21:08:07Z
+++

Long-term goal: import USD/USDZ into a SceneGraph (via ModelIO or USD bindings), getting the same rendering and animation as glTF. Depends on the scene graph staying format-neutral. Split from #16.

- `2026-10-12T15:58:57Z`: Decision: use USDKit (new in the 27 SDKs) instead of ModelIO or USD bindings. From the macOS 27 swiftinterface, USDKit exposes core USD: USDStage, USDLayer, USDPrim, Attribute, Relationship, USDTransformOperation, TimeCode, variant sets, and vector/matrix/quaternion types. It has no typed UsdGeom/UsdShade/UsdSkel/UsdLux schema wrappers, so the importer reads schema attributes by name (points, faceVertexCounts/Indices, normals, primvars:st, xformOps, material bindings, skel joints/bindTransforms/jointIndices/jointWeights, blendShapes, time samples for animation). Raises the minimum OS for the importer target to 27; keep it in its own target so the core stays on 26.
- `2026-10-12T16:16:55Z`: Related: #37 (ModelIO importer; also reads USD via ModelIO, but USDKit is the full-featured path).
- `2026-10-13T20:21:49Z`: Related: #37 (ModelIO path also reads USD).

---

## 32: Blinn-Phong renderer: instancing and opaque/transparent split

+++
status: closed
priority: low
kind: enhancement
labels: effort:m, area:renderer
created: 2026-10-12T15:06:44Z
updated: 2026-10-12T15:40:10Z
closed: 2026-10-12T15:40:10Z
+++

Split from #11 (culling and front-to-back sorting are done).

Remaining:
- Instancing: repeated mesh+material entries (e.g. the 15 crates in the physics demo) still draw one call each. The AddOns BlinnPhongShader takes one model matrix per draw, so instancing needs per-instance matrices in the shader (MetalSprocketsAddOns) first.
- Opaque vs transparent: BlinnPhongMaterial has no alpha or blend mode, so there is nothing to split on yet. Needs a material alpha first, then draw transparent entries back-to-front after opaque ones.

The PBR renderer already does both.

- `2026-10-12T15:22:46Z`: Upstream for instancing: MetalSprocketsAddOns #92.
- `2026-10-12T15:40:10Z`: Instancing done with BlinnPhongShader(instanced:) (AddOns #92). Transparency split moved to #36 (blocked on material alpha).

---

## 33: Animation layers, blending and state machine

+++
status: closed
priority: low
kind: feature
labels: effort:l, area:animation
created: 2026-10-12T15:08:08Z
updated: 2026-10-12T15:29:03Z
closed: 2026-10-12T15:29:03Z
+++

Split from #15. #15 added clips (TRS + weights channels, step/linear/cubic), AnimationClip.apply and a single-clip AnimationPlayer.

Not yet moved from MetalSprocketsGLTF: weighted layers and blending (GLTFAnimationLayer, additive deltas, rotation blending), root motion, and GLTFAnimationStateMachine. Also KHR_animation_pointer targets beyond nodes (materials, lights, cameras, visibility).

Do this when glTF loading (#16) needs it.

- `2026-10-12T15:29:03Z`: Done: AnimationLayer, AnimationMixer (override blending with rest fill, nlerp rotations, additive layers, root motion), AnimationController (cross-fades, phase-synced blend, additive tracks, root motion measurement) and AnimationStateMachine, ported from MetalSprocketsGLTF to scene graph nodes. Not done: KHR_animation_pointer targets beyond nodes (materials, lights, cameras, visibility); scene graph clips only target node TRS and morph weights.

---

## 34: Blinn-Phong renderer ignores morph targets and skins

+++
status: closed
priority: low
kind: enhancement
labels: effort:m, area:renderer
created: 2026-10-12T15:09:16Z
updated: 2026-10-12T15:26:52Z
closed: 2026-10-12T15:26:52Z
+++

Split from #21. Morph targets (Node.morphTargets + morphWeights) render in the PBR path only. The AddOns Blinn-Phong shader has no morph input, so Blinn-Phong meshes draw their base shape. Options: CPU-blend into a per-node vertex buffer when weights change, or add morph deltas to the AddOns shader. Also Node.meshBounds (#28) ignores morph offsets.

- `2026-10-12T15:11:01Z`: Also skins (#30): Blinn-Phong draws skinned meshes at their node transform in bind pose; Node.meshBounds ignores skinning.
- `2026-10-12T15:26:52Z`: Done for rendering: CPU morph + skin in core (MeshEntry.deformed), used by BlinnPhongMaterialRenderer. Not done: Node.meshBounds/subtreeBounds still ignore morph and skin deformation (deformed entries skip Blinn-Phong culling to stay correct). Tangents are not deformed.

---

## 35: DocC comments on public symbols

+++
status: open
priority: low
kind: documentation
labels: effort:m, area:docs, deferred
created: 2026-10-12T15:17:53Z
updated: 2026-10-13T21:08:12Z
+++

Split from #18, which got a README guide (scene building, rendering, custom renderers, reversed depth, change tracking, bounds, animation, limitations). Per-symbol DocC comments were left out on purpose: the API is changing quickly, and AGENTS.md asks for no doc comments unless asked. Do this once the API settles (after glTF loading, #16).

---

## 36: Blinn-Phong transparency: opaque/transparent split

+++
status: open
priority: high
kind: enhancement
labels: effort:m, area:renderer
created: 2026-10-12T15:40:04Z
updated: 2026-10-15T02:31:15Z
+++

Split from #32 (instancing done). BlinnPhongMaterial (MetalSprocketsAddOns) has no alpha or blend mode, so the renderer cannot tell transparent entries apart. Needs: alpha/blend mode on the material (upstream in MetalSprocketsAddOns, plus blending in BlinnPhongShader), then draw opaque first, transparent back-to-front with depth writes off. PBR already does this.

- `2026-10-14T13:31:44Z`: Related: #65 (renderingOrder demo needs transparency).
- `2026-10-14T13:36:18Z`: Looked at it. Punting: BlinnPhongMaterial and its shader live in MetalSprocketsAddOns, a remote dependency on main. The fragment shader always returns alpha 1, and the material has no opacity or blend mode, so transparency needs an upstream change. Options: (a) add opacity/blend mode to BlinnPhongMaterial and alpha output to BlinnPhongShader in MetalSprocketsAddOns (commit there; you push), then do the opaque-then-sorted-transparent split here; (b) give this repo its own Blinn-Phong shader in MetalSprocketsSceneGraphShaders with opacity, which duplicates AddOns code. Which do you want?
- `2026-10-14T13:54:48Z`: Decision: bring our own Blinn-Phong material and shaders into this repo (MetalSprocketsSceneGraphShaders + renderer target) and stop using BlinnPhongMaterial/BlinnPhongShader from MetalSprocketsAddOns. Then do the opaque/transparent split.
- `2026-10-15T02:31:16Z`: Related: #83, #96.

---

## 37: Load ModelIO formats (OBJ, PLY, STL, ABC, USD) into a SceneGraph

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:assets
created: 2026-10-12T16:16:53Z
updated: 2026-10-13T20:40:29Z
closed: 2026-10-13T20:40:29Z
+++

Import any format MDLAsset reads into a SceneGraph, keeping the hierarchy (unlike SwiftMesh's [Mesh](mdlAsset:), which flattens).

Plan:
- Walk MDLAsset's MDLObject tree: one Node per object, local transform from MDLTransformComponent. Keyframed transforms (transform.localTransform(atTime:)) sampled into an AnimationClip.
- MDLMesh -> MTKMesh -> MetalMesh (SwiftMesh MetalMesh(mtkMesh:)), one submesh per MDLSubmesh with its own material.
- MDLMaterial -> PBRSceneMaterial (baseColor, metallic, roughness, emission, textures), Blinn-Phong fallback option.
- MDLLight / MDLCamera -> scene graph Light / Camera.
- Skinning/blend shapes only exist for USD sources in ModelIO; leave to the USDKit importer (#31).

Own target (e.g. MetalSprocketsSceneGraphModelIO), macOS/iOS 26, so users only pay for the formats they use. Related: #16 (glTF), #31 (USDKit).

- `2026-10-13T20:21:49Z`: Related: #31 (USD via ModelIO overlaps the dedicated USD loader).
- `2026-10-13T20:40:29Z`: Added MetalSprocketsSceneGraphModelIO (ModelIOSceneGraph). Hierarchy, local transforms, sampled keyframe animation, meshes (repacked to position/normal/texcoord, normals generated if missing), per-submesh PBR or Blinn-Phong materials (base color, metallic, roughness, emission; base color and emission textures), perspective cameras, lights. Not done: normal/metallic/roughness/occlusion textures, orthographic cameras; skins and blend shapes left to #31. Tests cover an OBJ with two materials and USDA hierarchy; cameras, lights, textures and animation are not unit tested.

---

## 38: Physics as part of the scene graph

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:physics
created: 2026-10-12T16:17:40Z
updated: 2026-10-14T13:54:48Z
+++

Physics exists only in the demo app: PhysicsSimulation (Demo/.../PhysicsDemo.swift) steps a Jolt world and copies body positions/rotations onto node transforms each frame. No library target knows about physics, and SwiftJolt is linked by an absolute Scratch path.

Want a physics layer in its own target (e.g. MetalSprocketsSceneGraphPhysics):
- Per-node physics data: body type (static/dynamic/kinematic), shape (box, sphere, capsule, convex hull or mesh from MetalMesh/bounds #28), mass, friction, restitution.
- A world that creates bodies from the graph, steps, and writes results to node TRS (#20), bumping only the transform revision (#29).
- Kinematic nodes driven by animation (#15/#33) push into the simulation.
- Adding/removing nodes adds/removes bodies.

Prerequisite: SwiftJolt needs a proper dependency (git URL or relative path), not the absolute Scratch path. Then move the physics demo into DemoSupport.

- `2026-10-12T16:28:54Z`: SwiftJolt needs: #43 (set body position/rotation, move kinematic) for kinematic/reset support; #3/#5/#1/#6 for mesh/convex/capsule/compound colliders; #25 mass/damping; #27 contact events; #41 remote binary; #42 init. Also #44 (license) and #45 (example product) before depending on it.
- `2026-10-13T20:21:45Z`: Related: #53 (per-frame update hooks).
- `2026-10-14T13:44:42Z`: Checked prerequisites. Punting: blocked on SwiftJolt. It is still linked by an absolute Scratch path with no remote, and the APIs this needs are all open there: #43 (set position/rotation, kinematic moves), #25 (mass/damping), #27 (contacts), #1/#3/#5/#6 (capsule/mesh/convex/compound shapes), #42 (engine init), #44 (license). Unblocker: land SwiftJolt #43 and #25 and give it a git URL, or decide on a backend-neutral physics protocol in this repo first (body type, shape, mass and material on nodes, with a pluggable world), with Jolt as one implementation.
- `2026-10-14T13:54:48Z`: Decision: depend on SwiftJolt by local path for now; sort out paths later.

---

## 39: Hit testing: ray picking against the scene graph

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-13T20:20:22Z
updated: 2026-10-13T20:42:32Z
closed: 2026-10-13T20:42:32Z
+++

Can't find which node or submesh a screen point or a world ray hits. SceneKit has `hitTest(_:options:)` and `rayTestWithSegment`.

Want: a ray-to-scene query that returns the nodes and submeshes it hits, sorted by distance, with the world position, the normal and the triangle index. Also a helper that makes the ray for a screen point from the camera and viewport.

- `2026-10-13T20:21:45Z`: Related: #47 (hit-test category masks).

---

## 40: Node constraints (look-at, billboard, distance, IK)

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-13T20:20:22Z
updated: 2026-10-13T21:19:39Z
closed: 2026-10-13T21:19:39Z
+++

Nothing changes a node's transform automatically from other nodes. SceneKit has `SCNLookAtConstraint`, `SCNBillboardConstraint`, `SCNDistanceConstraint`, `SCNIKConstraint` and others.

Want: constraints on a node that run after animation and before rendering. Start with look-at and billboard.

- `2026-10-13T21:19:39Z`: Implemented look-at, billboard (all axes or Y only) and distance. IK not done; filed as a follow-up.

---

## 41: Actions: SCNAction-style procedural animation

+++
status: closed
priority: high
kind: feature
labels: area:animation, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T21:13:48Z
closed: 2026-10-13T21:13:48Z
+++

Only keyframe clips exist. SceneKit has `SCNAction` (move, rotate, scale, fade, wait, sequence, group, repeat, custom block, timing modes).

Want: actions that a node runs, advanced by the same clock as `AnimationPlayer`.

---

## 42: Implicit animation of node property changes

+++
status: closed
priority: medium
kind: feature
labels: area:animation, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T21:25:23Z
closed: 2026-10-13T21:25:23Z
+++

Changing a node property has an immediate effect. SceneKit animates property changes made in an `SCNTransaction` (duration, timing function, completion).

Want: a way to animate transform and morph weight changes over time without making a clip.

- `2026-10-13T21:25:23Z`: SceneGraph.Transaction.animate(duration:timingMode:_:completion:) animates transform and morphWeights changes via node actions. Known gap: if a later animation replaces a running one, the first one's completion is not called.

---

## 43: Scene environment: background, skybox and IBL

+++
status: closed
priority: medium
kind: feature
labels: area:renderer, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T20:44:45Z
closed: 2026-10-13T20:44:45Z
+++

The scene graph has no background or environment. The PBR environment is set on `PBRMaterialRenderer`, not on the scene. SceneKit has `scene.background` and `scene.lightingEnvironment`.

Want: a background (color, cube map or equirect) and an IBL environment that belong to the scene and are used by all renderers.

- `2026-10-13T20:21:45Z`: Related: #45 (HDR/tone mapping), #44 (fog).
- `2026-10-13T20:44:45Z`: Added SceneGraph.environment (background none/color/environment(blur:), map: any EnvironmentMap, intensity, rotation), SceneGraphBackgroundRenderer, PBREnvironment: EnvironmentMap. Color backgrounds set the pass clear color; PBR draws the environment background. Blinn-Phong ignores the IBL map. Not visually verified in the demo.

---

## 44: Fog

+++
status: closed
priority: medium
kind: feature
labels: area:renderer, effort:s
created: 2026-10-13T20:20:23Z
updated: 2026-10-14T13:43:34Z
closed: 2026-10-14T13:43:34Z
+++

No renderer supports fog. SceneKit has `fogStartDistance`, `fogEndDistance`, `fogColor` and `fogDensityExponent`.

Want: fog settings on the scene, used by Blinn-Phong and PBR.

- `2026-10-13T20:21:45Z`: Related: #43 (scene environment).

---

## 45: Camera post-processing: HDR, bloom, DOF, SSAO, tone mapping

+++
status: open
priority: low
kind: feature
labels: area:renderer, effort:l
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T20:21:45Z
+++

Cameras have only a projection. SceneKit cameras have HDR, exposure, bloom, depth of field, motion blur, SSAO, vignette and color grading.

Want: post-processing settings on `Camera`, applied after the scene pass. Start with HDR, tone mapping and bloom.

- `2026-10-13T20:21:45Z`: Related: #43 (scene environment).

---

## 46: Level of detail per node

+++
status: closed
priority: low
kind: feature
labels: area:renderer, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-15T03:14:09Z
closed: 2026-10-15T03:14:09Z
+++

A node always draws the same mesh. SceneKit has `SCNLevelOfDetail` (other geometry by screen-space radius or distance).

Want: LOD meshes on a mesh node; `meshEntries()` (or the renderer) picks one by camera distance or screen size.

---

## 47: Category bitmasks and rendering order

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T21:27:33Z
closed: 2026-10-13T21:27:33Z
+++

Lights affect all nodes, cameras see all nodes, and there is no way to set draw order. SceneKit has `categoryBitMask` (with light `categoryBitMask`, camera and hit-test masks) and `renderingOrder`.

Want: a category bitmask on nodes, and filter masks on lights, cameras and queries. Also a rendering order value for transparent or overlay content.

- `2026-10-13T20:21:45Z`: Related: #39 (hit-test masks).
- `2026-10-13T21:27:33Z`: Added Node.categoryBitMask (default 1), Camera.categoryBitMask, Node.lightCategoryBitMask (for light nodes), hitTest(_:categoryBitMask:), Node.renderingOrder. SceneGraphElement batches entries by order and affecting lights. Also fixed PBRMaterialRenderer's model cache, which keyed only on revision and would return the wrong model for a second entry set in one frame. Rendering order does not turn off depth testing.

---

## 48: Custom shaders per material without a new renderer

+++
status: closed
priority: medium
kind: feature
labels: area:renderer, effort:l
created: 2026-10-13T20:20:23Z
updated: 2026-10-14T13:51:10Z
closed: 2026-10-14T13:51:10Z
+++

To use a custom shader you must write a whole `SceneGraphMaterialRenderer`. SceneKit has shader modifiers and `SCNProgram` on a single material.

Want: an easier way to change shading for one material, for example shader modifier hooks in Blinn-Phong or PBR, or a generic renderer that takes a shader.

- `2026-10-14T13:51:10Z`: Added ShaderMaterial + ShaderMaterialRenderer (SCNProgram-style). Shader modifiers (snippet injection into Blinn-Phong/PBR) not done; they need upstream shader changes.

---

## 49: Built-in shape and text node helpers

+++
status: closed
priority: high
kind: enhancement
labels: effort:s, area:scenegraph
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T21:11:43Z
closed: 2026-10-13T21:11:43Z
+++

SceneKit has `SCNBox`, `SCNSphere`, `SCNText` and others as node geometry with editable parameters. Here you must build a `MetalMesh` from a SwiftMesh shape yourself.

Want: helpers that make mesh nodes for common shapes and text. Check what SwiftMesh already gives first (it has shape generators and `TextExtrusion`).

---

## 50: Particle systems

+++
status: open
priority: low
kind: feature
labels: area:renderer, effort:l
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T20:21:45Z
+++

No particles. SceneKit has `SCNParticleSystem` attached to nodes.

Want: a particle emitter as node content, with a GPU simulation and a renderer for it.

---

## 51: Positional audio

+++
status: open
priority: low
kind: feature
labels: area:audio, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T20:21:45Z
+++

No audio. SceneKit has `SCNAudioSource`, `SCNAudioPlayer` and `audioListener`.

Want: audio sources on nodes, positioned in 3D from the world transform, and a listener node (default: the camera). Probably with AVAudioEngine.

---

## 52: Save and load a scene graph

+++
status: open
priority: medium
kind: feature
labels: area:assets, effort:l, deferred
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T20:50:31Z
+++

A scene graph can't be saved. SceneKit can archive `SCNScene` (`.scn`) and export it.

Want: a file format for the node tree, transforms, content, materials, animation, skins and morph targets. Mesh data could be stored inline or as external references. Different from glTF and USD import (#16, #31).

- `2026-10-13T20:21:45Z`: Related: #16, #31, #37 (importers).
- `2026-10-13T20:45:21Z`: Looked at the model. Punting: this needs design decisions that the code cannot answer. (1) Materials are 'any Material' and projections 'any ProjectionProtocol' (open protocols), so decoding needs a type registry or a closed set of types. (2) Textures (MTLTexture inside PBRMaterial/BlinnPhongMaterial) and PBREnvironment maps have no source data to write back. (3) Container format: one JSON file with base64 mesh data, a package directory (scene.json + .bin buffers + images), or glTF export instead of a new format. Proposal: a package directory: scene.json (Codable nodes, TRS, skins by node id, morphs, clips, environment settings), one .bin per MetalMesh (vertex/index buffers + descriptor), PNG/EXR for textures read back from the GPU, and a MaterialCodec registry that renderer modules register (PBR, Blinn-Phong). Unblocker: OK this design (or prefer glTF export), and say if reading textures back from the GPU is acceptable.
- `2026-10-13T20:50:31Z`: Deferred: scene graphs are built by hand (or imported) for now.

---

## 53: Per-frame update hooks and a scene view wrapper

+++
status: closed
priority: low
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-13T21:18:24Z
closed: 2026-10-13T21:18:24Z
+++

There is only `RenderView` plus `SceneGraphElement`. SceneKit has `SCNView` and an `SCNSceneRendererDelegate` with update, apply-animations, simulate-physics and will-render callbacks.

Want: a ready-made SwiftUI view that has a camera, a frame clock and update hooks, so apps don't have to build the loop themselves.

- `2026-10-13T20:21:45Z`: Related: #38 (physics step hook).
- `2026-10-13T21:05:11Z`: Related: #56 (SceneView). #56 likely covers this issue.
- `2026-10-13T21:18:24Z`: Covered by #56 (SceneView + SceneViewDelegate).

---

## 54: glTF scene graph loader: orthographic cameras, pointer animations

+++
status: open
priority: low
kind: enhancement
labels: area:assets, effort:m
created: 2026-10-13T20:37:21Z
updated: 2026-10-15T02:59:59Z
+++

MetalSprocketsSceneGraphGLTF (#16) does not map these glTF features into the scene graph:

- EXT_mesh_gpu_instancing copies.
- KHR_node_visibility. The `isVisible` property is internal in MetalSprocketsGLTF.
- Orthographic cameras. The scene graph has no orthographic projection.
- KHR_animation_pointer channels for materials, lights, cameras and visibility.

The loader adds a warning for skipped cameras and channels.

- `2026-10-15T02:31:16Z`: Related: #87.
- `2026-10-15T02:59:59Z`: Done: EXT_mesh_gpu_instancing copies become child nodes (skinned meshes keep one), KHR_node_visibility sets isVisible. Left: orthographic cameras (needs #87) and KHR_animation_pointer channels (needs key-path animation targets, #89).

---

## 55: ModelIO loader: normal, metallic, roughness and occlusion textures

+++
status: closed
priority: low
kind: enhancement
labels: area:assets, effort:s
created: 2026-10-13T20:40:29Z
updated: 2026-10-15T02:55:06Z
closed: 2026-10-15T02:55:06Z
+++

MetalSprocketsSceneGraphModelIO (#37) reads only base color and emission textures. Model I/O keeps normal, metallic, roughness and ambient occlusion maps as separate textures. The PBR material expects the glTF layout: one metallic-roughness texture (roughness in green, metallic in blue) and a tangent attribute for normal maps.

Want: pack the metallic and roughness maps into one texture, add tangents when a normal map exists, and bind the normal and occlusion textures.

---

## 56: SceneView: SwiftUI view modeled on SceneKit's SceneView

+++
status: closed
priority: high
kind: feature
labels: area:renderer, effort:l
created: 2026-10-13T21:05:11Z
updated: 2026-10-13T21:18:24Z
closed: 2026-10-13T21:18:24Z
+++

Showing a scene graph today means building it by hand from `RenderView`, `SceneGraphElement`, `.interactiveCamera`, a frame clock, a tap-to-pick handler and size tracking, as `DemoView` in the demo app does. SceneKit has `SceneView(scene:pointOfView:options:delegate:)`.

Want: a `SceneView` that looks and feels like SceneKit's:

- `SceneView(sceneGraph:pointOfView:options:renderers:)`. Default renderers: Blinn-Phong and PBR.
- Options like SceneKit's: `.allowsCameraControl`, `.autoenablesDefaultLighting`, `.rendersContinuously`, `.jitteringEnabled` (if it applies), `.temporalAntialiasingEnabled` (if it applies).
- Per-frame update hooks (see #53).
- Optional hit-test helper for taps, using `SceneGraph.hitTest`.
- `pointOfView` binding to a camera node; with camera control the user camera moves that node or an internal free camera, as in SceneKit.

Then replace the demo app's `DemoView` plumbing with it.

Related: #53 (update hooks and view wrapper; may be closed by this issue).

- `2026-10-13T21:18:24Z`: Not verified in the running app (camera control, picking, pause); tests and Demo build pass. Not implemented: rendersContinuously, jittering and temporal antialiasing options.

---

## 57: Inverse kinematics constraint

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, effort:m
created: 2026-10-13T21:19:39Z
updated: 2026-10-15T03:15:38Z
closed: 2026-10-15T03:15:38Z
+++

Constraints (#40) cover look-at, billboard and distance. SceneKit also has SCNIKConstraint: a chain of joint nodes is turned so that its end reaches a target, with angle limits per joint.

Want: `.inverseKinematics(chainRoot:target:)`, using CCD or FABRIK, with optional joint angle limits.

- `2026-10-15T02:31:16Z`: Related: #91.

---

## 58: Honor receivesShadow and add point/spot light shadows

+++
status: closed
priority: medium
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-13T21:24:15Z
updated: 2026-10-14T13:39:33Z
closed: 2026-10-14T13:39:33Z
+++

Shadows (#12) use a shadow map per directional light and a screen-space mask pass. Because the mask darkens every pixel behind a caster, `receivesShadow: false` has no effect. Point and spot lights cast no shadows.

Want:
- Exclude non-receivers from the mask, for example with a stencil bit or a receiver mask texture written in the scene pass.
- Perspective shadow maps for spot lights and cube shadow maps for point lights.

- `2026-10-14T13:31:44Z`: Related: #59, #60 (other shadow issues).
- `2026-10-14T13:39:33Z`: Spot (1 perspective slice) and point (6 x 90 degree slices) shadows done, within AddOns ShadowMap's 8 slices. receivesShadow not done: needs a receiver mask in AddOns ShadowMaskPass; split into a new issue.

---

## 59: Rare random shadow flicker on self-shadowed surfaces

+++
status: open
priority: medium
kind: bug
labels: area:renderer, effort:m, deferred
created: 2026-10-14T01:11:25Z
updated: 2026-10-14T13:31:44Z
+++

In the Imported Assets demo, shadowed pixels sometimes flash unshadowed for a frame. It is mostly the fox's self-shadowed side. It happens with the camera still and the animation paused (speed 0). The flashes are random and rare. They are clearly less frequent with the inspector sidebar closed, so they likely depend on frame timing.

Context: SceneGraphShadows draws a shadow map per directional light (ShadowCasterDepthPass), then the AddOns ShadowMaskPass darkens the drawable in screen space using the view's depth texture. Up to 3 frames are in flight, and they share one depth texture.

Fixed already: a whole-shadow blink while rotating the camera. The scene pass now starts with QueueBarrier(after: .dispatch, before: [.vertex, .fragment]).

Tried, no effect:
- `.barrierAfterPass(after: .dispatch, beforeQueueStages: [.vertex, .fragment])` on the mask pass.
- 6 shadow map slots instead of 3.

Verified with per-frame logging: every frame drew shadows, and the depth and mask passes used the same shadow map slot. Presentation (signalDrawable) comes after the whole command buffer.

Next steps: capture a GPU trace of a flashing frame, or render into renderer-owned depth textures, one per frame in flight, so frames share nothing.

- `2026-10-14T01:14:55Z`: Possibly caused by shadow acne (#60): borderline texels flip between lit and shadowed. Check again after fixing #60.

---

## 60: Shadow acne on lit surfaces (depth bias ineffective)

+++
status: open
priority: medium
kind: bug
labels: area:renderer, effort:s, deferred
created: 2026-10-14T01:14:55Z
updated: 2026-10-14T13:31:44Z
+++

Surfaces that face the light show a fine dotted shadow pattern, and shadow edges are stepped. It is clearly visible on the fox's head in the Imported Assets demo. It may also cause the random flicker in #59, because borderline texels flip between lit and shadowed.

Cause: the hardware depth bias does almost nothing with the depth32Float shadow map. The constant bias is measured in float ULPs, so depthBias = 2 is close to zero. Only the slope part helps, and only on steep faces. The shadow map also covers the whole scene bounds (about 6 units) at 2048², so the fox gets few texels.

Fix: apply a world-space depth offset in the ShadowCasters vertex shaders. Push caster depth away from the light by about 1 to 2 texels, computed as orthoSize * 2 / resolution and converted to clip z through the orthographic range. Make it a property of SceneGraphShadows. Optionally fit the shadow map tighter (casters plus receivers in view), or raise the resolution.

Related: #59.

---

## 61: Demo: shape nodes

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-14T01:31:47Z
updated: 2026-10-14T13:30:12Z
closed: 2026-10-14T13:30:12Z
+++

Shapes (#49) have no demo. Add one that shows every SceneGraph.Shape (box, sphere, plane, cylinder, cone, capsule, torus, extruded text). Include sliders that change one shape's parameters live through `node.shape`.

---

## 62: Demo: node actions

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-14T01:31:47Z
updated: 2026-10-14T13:30:12Z
closed: 2026-10-14T13:30:12Z
+++

Actions (#41) have no demo. The demo app advances actions every frame, but no demo runs any. Add one that runs move, rotate and scale actions with sequence, group, repeatForever and timing modes, and has a toolbar action that starts a one-shot sequence.

---

## 63: Demo: constraints

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-14T01:31:47Z
updated: 2026-10-14T13:30:12Z
closed: 2026-10-14T13:30:12Z
+++

Constraints (#40) have no demo. Add one with a camera or spotlight that follows a moving node (`.lookAt`), billboarded quads that face the camera (`.billboard()` and `.billboard(freeAxes: .y)`), and a node held between distances from a target (`.distance`).

---

## 64: Demo: implicit animation (Transaction)

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-14T01:31:47Z
updated: 2026-10-14T13:30:12Z
closed: 2026-10-14T13:30:12Z
+++

Implicit animation (#42) has no demo. Add one where clicking a node, or pressing a toolbar button, moves, rotates or scales it inside `SceneGraph.Transaction.animate`. Show the timing modes and `withoutAnimation`.

---

## 65: Demo: category masks and rendering order

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:s
created: 2026-10-14T01:31:47Z
updated: 2026-10-14T13:53:06Z
closed: 2026-10-14T13:53:06Z
+++

Category masks and rendering order (#47) have no demo. Add one where a light lights only some nodes (`lightCategoryBitMask`), a toggle hides a category from the camera (`Camera.categoryBitMask`), picking is limited to one category (`hitTest(_:categoryBitMask:)`), and `renderingOrder` matters, for example for transparent objects.

- `2026-10-14T13:30:12Z`: SceneKit Features demo covers lightCategoryBitMask and Camera.categoryBitMask. Still missing: hitTest(_:categoryBitMask:) in picking, and a visible renderingOrder example.
- `2026-10-14T13:31:44Z`: Related: #36 (Blinn-Phong transparency; a renderingOrder demo needs blended content).
- `2026-10-14T13:53:06Z`: SceneKit Features demo now has: picking limited to category 1 (SceneView hitTestCategoryBitMask, plus SceneView taps honor the camera mask), and two translucent ShaderMaterial panes whose renderingOrder swaps. Added ShaderMaterial.isTransparent (alpha blend, no depth write) to make order visible.

---

## 66: Honor receivesShadow in the shadow mask

+++
status: closed
priority: medium
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-14T13:39:33Z
updated: 2026-10-15T02:49:25Z
closed: 2026-10-15T02:49:25Z
+++

Split from #58. The screen-space ShadowMaskPass (MetalSprocketsAddOns) darkens every pixel behind a caster, so `receivesShadow: false` has no effect.

Want: the scene pass marks the pixels of receivers, for example with a stencil bit or a small receiver mask texture, and the mask pass skips the other pixels. This needs ShadowMaskPass to accept the mask (an upstream change in MetalSprocketsAddOns) or a mask kernel in MetalSprocketsSceneGraphShaders.

- `2026-10-14T13:55:09Z`: Related: #36 (own Blinn-Phong shaders could write a receiver mask), #58.

---

## 67: Demo: shadow controls (on/off, per light type)

+++
status: open
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-14T15:18:06Z
updated: 2026-10-14T15:42:08Z
+++

Spot and point light shadows (#58) appear in SceneKit Features only because its lights happen to cast. No control turns shadows off, and no demo compares directional, spot and point shadows on their own.

Want: a shadows toggle and a light-type picker (directional / spot / point) in a demo, so each kind of shadow can be seen alone.

- `2026-10-14T15:42:08Z`: Related: #71 (shadow light-type controls would help isolate it).

---

## 68: Report when lights exceed the 8 shadow map slices

+++
status: closed
priority: low
kind: enhancement
labels: area:renderer, effort:xs
created: 2026-10-14T15:18:06Z
updated: 2026-10-15T02:52:57Z
closed: 2026-10-15T02:52:57Z
+++

SceneGraphShadows has 8 shadow map slices: a directional or spot light uses 1, a point light 6. Shadow views past 8 are dropped without any notice. SceneKit Features already uses all 8 (sun + spotlight + red point light), so adding a light there silently removes its shadows.

Want: a way to see this, for example a `droppedLightCount` on SceneGraphShadows or a one-time log message, and a note in the README.

- `2026-10-14T15:42:08Z`: Related: #71 (SceneKit Features uses all 8 slices).

---

## 69: PBR skinned tube collapses in the Morphs & Skinning demo

+++
status: closed
priority: medium
kind: bug
labels: area:renderer, effort:m
created: 2026-10-14T15:24:41Z
updated: 2026-10-14T17:25:19Z
closed: 2026-10-14T17:25:19Z
+++

In the Morphs & Skinning demo (formerly the Skinning demo), the tube bent by a three-joint skeleton renders correctly with Blinn-Phong (CPU skinning). The PBR copy (GPU skinning through PBRMaterialRenderer) collapses into a lump on the floor near its skeleton. Hiding everything else does not change it, so this is not caused by the demo merge. The old Skinning demo used identical code, so it was probably already broken. The skinned glTF fox (PBR) renders correctly.

Differences from the fox:
- The skin vertices come from SceneGraph.SkinVertex with ushort4 joints. The fox reads float4 joints back from the PBR mesh.
- The inverse bind matrices are computed from the joints' world transforms at setup. The skeleton node is offset in x; the tube node is at the origin.

Suspects: pbrPrimitiveInput (joint/weight attributes added after the dependency update), PBRNodeLayout joint indexing, or the joint matrix/pose path for skins whose mesh node is not under the skeleton. Repro: render DeformationDemo offscreen and hide everything except "PBR Tube".

- `2026-10-14T15:42:08Z`: Related: #70 (same demo).
- `2026-10-14T17:25:19Z`: Not a renderer bug: the demo's inverse bind matrices came from the joints' world transforms while the tube is modelled at the origin, so both renderers swung it around joints 1.5 away (CPU and GPU math agree). Fixed by computing them relative to the skeleton. Regression test: deformationDemoTubesFollowTheirSkeletons.

---

## 70: Morphs & Skinning demo: morphed blobs look wrong

+++
status: closed
priority: low
kind: bug
labels: area:demo, effort:s
created: 2026-10-14T15:36:23Z
updated: 2026-10-14T17:25:19Z
closed: 2026-10-14T17:25:19Z
+++

The blend-shape blobs in the Morphs & Skinning demo (formerly Morph Targets) look odd. In an offscreen render the "Spiky" target gives a fuzzy, noisy shell instead of clean spikes, on both the Blinn-Phong (CPU morph) and PBR (GPU morph) blobs.

The spiky target displaces each vertex along its normal by max(0, sin(18x) sin(18y) sin(18z)) * 0.45. On an icosphere with 4 subdivisions that frequency is probably too high for the mesh, so neighbouring vertices jump by very different amounts. Normals are not morphed for it either, so the lighting stays that of the sphere.

Want: a cleaner shape, for example fewer and broader spikes or a twist/bulge target, with normal deltas so the lighting follows the shape. Check whether the CPU and GPU blobs match.

- `2026-10-14T15:42:08Z`: Related: #69 (same demo).
- `2026-10-14T17:25:19Z`: Cause: the icosphere has separate vertices per face with face normals; displacing along normals tore faces apart. Now bumps follow the direction from the center, with normal deltas from welded smooth normals. Regression test: deformationDemoMorphKeepsSurfaceClosed.

---

## 71: Shadows badly broken in demos since the demo consolidation

+++
status: open
priority: high
kind: bug
labels: area:renderer, effort:m
created: 2026-10-14T15:36:23Z
updated: 2026-10-15T02:49:40Z
+++

Reported: shadows have been badly broken in the demos since the demo consolidation. Exact symptoms not yet recorded (wrong place, missing, all dark, flickering?) and which demos (SceneKit Features, Imported Assets).

Changes in that period that could cause it:
- #58 added spot (1 slice) and point (6 slices) light shadows. SceneKit Features now uses all 8 slices (sun + spotlight + red point light); before, only the sun cast. Perspective shadow views, their near/far fit, and how the AddOns mask combines slices (shadow factors are multiplied) are untested beyond a single box-over-floor scene.
- #65 added translucent panes (castsShadow false) and transparent ShaderMaterials. #48 added ShaderMaterial drawing.
- #44 fog pass runs after the shadow mask.

Next: get a screenshot or description, then render SceneKit Features offscreen with the sun only, the spot only, and the point only to find which light type is wrong.

- `2026-10-14T15:42:08Z`: needs-info: what the broken shadows look like (wrong place, missing, all dark, flicker?) and in which demos. Related: #67, #68.
- `2026-10-14T15:48:46Z`: Symptoms (SceneKit Features, screenshot 2026-10-14 11.46.47): (1) acne/z-fighting-like shadow pattern on the extruded text (see #60); (2) a giant dark, flickering wedge over the front of the floor, shaped like a light frustum. Probably a spot or point-light shadow view from #58 treating a large area as shadowed. Also only ~31 FPS with all 8 shadow views. Workaround: shadows toggle in the demo, default off.
- `2026-10-15T02:44:10Z`: Investigated offscreen (DemoSnapshot with Shadows on, each light alone, diffed against shadows off). Cause: the screen-space shadow mask multiplies every light's shadow factor and darkens the pixel, whatever light actually lights it. So (1) surfaces facing away from the red point light or the spotlight are 'self-shadowed' in those lights' maps and get darkened even where the sun lights them (all shapes go dark), (2) the red light only lights category 2 but its shadows darken everything, giving the large wedge-shaped dark areas on the floor. The geometry of each light's shadow alone looks right. Punting: a real fix needs per-light shadow factors inside the lighting shaders (MetalSprocketsAddOns Blinn-Phong and MetalSprocketsPBR), or a design call such as SceneKit-style per-light castsShadow (SceneKit defaults it to false) so only chosen lights cast. Which do you want?
- `2026-10-15T02:49:40Z`: Update after #66: the shadow mask kernel now lives in MSSG (SceneShadowMask). A fix without other libraries is possible: per pixel, weight each light's shadow by that light's contribution (N·L from depth-reconstructed normals, range/cone falloff, color*intensity) so a light that does not light a surface cannot darken it; and write each mesh's categoryBitMask into the mask pass so lightCategoryBitMask is respected. Say if you want that instead of per-light castsShadow.

---

## 72: Use DemoKit for the demo app

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:m
created: 2026-10-14T15:38:43Z
updated: 2026-10-14T17:08:24Z
closed: 2026-10-14T17:08:24Z
+++

The demo app has its own catalog and sidebar: DemoCatalog, Demo, DemoScene, ContentView. DemoKit (https://github.com/schwa/DemoKit, a SwiftUI library for putting demo views in one app with a searchable sidebar) already does this and is used by MetalSprocketsExamples.

Want: make each demo a DemoKit `DemoView` with `metadata`, replace the custom catalog and sidebar with DemoKit, and keep the per-demo inspector, toolbar actions and SceneView. Drop code that DemoKit makes redundant.

Related: the demos-in-own-target issue (so demos can also run from the CLI).

---

## 73: Put demos in their own SPM target, runnable from the CLI

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:m
created: 2026-10-14T15:38:44Z
updated: 2026-10-14T17:08:24Z
closed: 2026-10-14T17:08:24Z
+++

Demos live in MetalSprocketsSceneGraphDemoSupport plus the Xcode demo app. The physics demo is in the app because it needs JoltPhysics. Running a demo needs Xcode and the app project.

Want: a demos target with all demos (physics too, once SwiftJolt is a package dependency, #38), plus an executable product so a demo can run from the CLI, for example `xcb run <demo-runner> -- <demo-id>`, opening a window or rendering frames offscreen to PNG. The Xcode app becomes a thin shell over the same target.

Related: Use DemoKit for the demo app.

---

## 74: Demo content and inspector extend under the toolbar with DemoKit

+++
status: blocked
priority: medium
kind: bug
labels: area:demo, effort:s, blocked
created: 2026-10-14T16:40:19Z
updated: 2026-10-15T02:31:13Z
+++

Since moving the demos to DemoKit (#72), the top of the demo view sits under the window toolbar. The FPS overlay (topTrailing, padded) is partly hidden, and the configuration inspector's Form starts under the toolbar (the first rows are cut off). Screenshots: 2026-10-14 12.16.32 and 12.21.40.

What is known:
- DemoKit's own description overlay on the same content is placed correctly, so its container respects the safe area.
- MetalSprocketsExamples uses the same pattern (RenderView, .interactiveCamera, a topTrailing frame-timing overlay, .demoConfiguration { Form }) and, as far as known, looks fine.
- Switching from our own .inspector to .demoConfiguration did not fix it.

The difference must be in SceneDemoView or SceneView: .onGeometryChange, .onTapGesture, the CameraControl modifier, the demo .toolbar items, or the metal view settings that change with shadows. Next: run the app and bisect those modifiers.

- `2026-10-14T16:47:38Z`: View hierarchy (MetalSprocketsSceneGraphDemo[49042].viewhierarchy): every split item, including the detail and the inspector hosting views, is full window height (1031 pt), which is normal on macOS 26. The visible rect starts 52 pt down (under the toolbar). The MTKView platform host frame is also 1031 pt tall from y=0, so SwiftUI lays out our detail content (and the inspector Form) with no top safe-area inset. Nothing in MetalSprocketsUI, Interaction3D or SceneView calls ignoresSafeArea. DemoKit's description overlay (a ScrollView) is inset correctly. Hypothesis, not verified: DemoKit's detail wrapper (ZStack { Color.clear; content }.clipped(), with .inspector applied inside it) loses the safe area for non-scroll content; the old ContentView put the demo directly in the split view's detail and was fine. Check: does MetalSprocketsExamples show its frame-timing overlay under the toolbar too?
- `2026-10-14T17:07:28Z`: Also happens in MetalSprockets-Examples, so it's in DemoKit. Filed DemoKit #22 (content underlaps toolbar) and added findings to DemoKit #21 (inspector). Blocked on those.

---

## 75: Reach 120 fps in every demo

+++
status: open
priority: medium
kind: enhancement
labels: area:renderer, effort:l
created: 2026-10-14T16:41:14Z
updated: 2026-10-15T02:31:13Z
+++

Target: 120 fps (8.3 ms frames) on a ProMotion display in every demo. Some demos drop well below that.

Known so far:
- SceneKit Features with shadows on: about 31 fps (30 ms frames, 3.1 ms GPU). All 8 shadow views run: sun + spotlight + six for the red point light. Shadows are now off by default (#71).
- Imported Assets: about 90 fps before GPU skinning for shadow casters; CPU shadow prep went from 2.8 ms to 0.13 ms. Not re-measured since.
- The demo frame meter shows CPU frame time well above GPU time in several demos, so the main thread is probably the limit, not the GPU.

Likely CPU costs per frame: SceneGraphElement rebuilding element trees; meshEntries/bounds traversal; CPU deformation (Blinn-Phong skin/morph, deformed() copies); ShaderMaterialRenderer creating one RenderPipeline per entry; renderBatches grouping; SceneView reading bounds each frame for the viewpoint; SwiftUI updates from the DemoScene observation and frame-timing overlay.

Plan: measure each demo (CPU and GPU, Instruments time profile), list the top costs per demo, fix them one by one, and add a CLI timing mode (scenegraph-demos --bench <id>, see #73) to track regressions.

---

## 76: Node opacity and fade actions

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:06Z
updated: 2026-10-15T02:31:14Z
+++

SceneKit has SCNNode.opacity (inherited by children) and fadeIn/fadeOut/fadeOpacity actions. Nodes here have no opacity, so there are no fade actions either. Want: Node.opacity applied by every renderer, plus the fade actions. See docs/SceneKitComparison.md.

---

## 77: Node flattenedClone

+++
status: open
priority: low
kind: feature
labels: effort:s, area:scenegraph
created: 2026-10-15T02:28:06Z
updated: 2026-10-15T03:10:47Z
+++

Missing SceneKit equivalents: clone()/flattenedClone(), childNode(withName:recursively:), replaceChildNode(_:with:), and enumerateHierarchy's stop flag. Want them on SceneGraph.Node and SceneGraph.visit. See docs/SceneKitComparison.md.

- `2026-10-15T03:10:47Z`: Done: clone(), childNode(withLabel:recursively:), replaceChild(_:with:), SceneGraph.traverse with skipChildren/stop. Left: flattenedClone (merging meshes needs matching vertex layouts).

---

## 78: Node pivot

+++
status: closed
priority: low
kind: feature
labels: effort:s, area:scenegraph
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T03:12:20Z
closed: 2026-10-15T03:12:20Z
+++

SCNNode.pivot offsets the node's rotation and scale origin. Nodes here have no pivot, so you have to add an extra parent node. Want a pivot transform applied before the local transform. See docs/SceneKitComparison.md.

---

## 79: Transform helpers: Euler angles, world setters, space conversion, look(at:)

+++
status: open
priority: medium
kind: enhancement
labels: effort:m, area:scenegraph
depends: 97
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:35:20Z
+++

Missing SceneKit equivalents: eulerAngles; settable worldPosition/worldOrientation/worldTransform; convertPosition/convertVector/convertTransform(from:/to:); and a one-shot look(at:up:localFront:) that targets a point. Today look-at only exists as a constraint on a node. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #97 (GeometryLite3D has Euler and LookAt).
- `2026-10-15T02:35:20Z`: Depends on #97: build these helpers on GeometryLite3D (Euler, LookAt, matrix accessors), adding what is missing there first, not as new local math in MSSG.

---

## 80: Shape options: segment counts, box chamfer, geodesic sphere, plane corner radius

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:14Z
+++

SceneGraph.Shape has no segment counts, no box chamferRadius, no sphere isGeodesic, and no plane corner radius. SCNText's chamfer, flatness, container frame and wrapping are missing too. Needs SwiftMesh support for some of these. See docs/SceneKitComparison.md.

---

## 81: New shapes: tube, pyramid, floor, extruded Bézier path

+++
status: open
priority: low
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:14Z
+++

SceneKit has SCNTube, SCNPyramid, SCNFloor (infinite, with optional reflections) and SCNShape (an extruded Bézier path). Shape has none of them. See docs/SceneKitComparison.md.

---

## 82: Subdivision and tessellation

+++
status: open
priority: low
kind: feature
labels: effort:l, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:14Z
+++

SceneKit has subdivisionLevel, wantsAdaptiveSubdivision, the SCNGeometryTessellator and edge creases. There is no equivalent here. See docs/SceneKitComparison.md.

---

## 83: Blinn-Phong material: normal maps, emission, cull mode

+++
status: open
priority: medium
kind: enhancement
labels: effort:m, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:16Z
+++

BlinnPhongMaterial has only ambient, diffuse and specular color sources and shininess. It has no normal map, no emission, and no double-sided/cull mode setting. Transparency is #36. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #36.

---

## 84: Material settings: blend modes, depth read/write, color write mask, wireframe

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:14Z
+++

SceneKit materials have blendMode (alpha, add, subtract, multiply, screen, replace), writesToDepthBuffer/readsFromDepthBuffer, colorBufferWriteMask and fillMode .lines. Here only ShaderMaterial.isTransparent and PBR alphaMode exist. Want these settings to work across the material families. See docs/SceneKitComparison.md.

---

## 85: Shader modifiers

+++
status: open
priority: low
kind: feature
labels: effort:xl, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:14Z
+++

SceneKit shader modifiers inject code at geometry, surface, lighting and fragment entry points of the built-in materials. ShaderMaterial (like SCNProgram) replaces the whole shader. Want a way to tweak the built-in Blinn-Phong/PBR shading without rewriting it. See docs/SceneKitComparison.md.

---

## 86: Light gaps: ambient node, attenuation, temperature, IES and area lights

+++
status: open
priority: low
kind: feature
labels: effort:l, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:14Z
+++

Missing SceneKit equivalents: an ambient light type as a node (today it is per renderer: BlinnPhongMaterialRenderer.ambientLightColor), attenuationStartDistance and attenuationFalloffExponent, color temperature, and IES, area and probe lights. See docs/SceneKitComparison.md.

---

## 87: Orthographic cameras

+++
status: open
priority: medium
kind: feature
labels: effort:s, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T02:31:16Z
+++

GeometryLite3D only has PerspectiveProjection, so there is no orthographic camera. The glTF and Model I/O loaders skip orthographic cameras with a warning. Needs a projection type in GeometryLite3D first. Also unblocks part of #54. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #97 (orthographic projection belongs in GeometryLite3D), #54.

---

## 88: Shadow gaps: cascades, per-light settings

+++
status: open
priority: low
kind: enhancement
labels: effort:l, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T03:04:56Z
+++

SceneGraphShadows is one global setting. Missing: shadowColor (today only intensity toward black), soft shadows (shadowRadius, shadowSampleCount), cascades, and per-light castsShadow, resolution and bias. See docs/SceneKitComparison.md.

- `2026-10-15T03:04:56Z`: Done: SceneGraphShadows.color (shadow tint) and softness (PCF radius). Left: cascades and per-light castsShadow/resolution/bias (ties into the #71 decision).

---

## 89: Animation gaps: events, autoreverse, repeat count, timing, key-path targets

+++
status: closed
priority: low
kind: enhancement
labels: effort:l, area:animation
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T03:07:43Z
closed: 2026-10-15T03:07:43Z
+++

AnimationClip/AnimationPlayer has no animation events, no autoreverse, no fixed repeat count (only looping), and no Bézier timing functions. Channels can target only translation, rotation, scale and morph weights, not material, light or camera properties. See docs/SceneKitComparison.md.

---

## 90: Action gaps: reversed, speed, random wait, action(forKey:), Euler rotate, timing function

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:animation
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T02:56:51Z
closed: 2026-10-15T02:56:51Z
+++

Missing SCNAction features: reversed(), per-action and per-node speed, wait(duration:withRange:), an action(forKey:) getter, rotateBy/rotateTo with Euler angles, and a custom timingFunction. See docs/SceneKitComparison.md.

---

## 91: Constraint gaps: acceleration, slider, influence factor, enabled flag

+++
status: open
priority: low
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T03:17:39Z
+++

Missing: SCNReplicatorConstraint, SCNAccelerationConstraint, SCNSliderConstraint, SCNAvoidOccluderConstraint and SCNTransformConstraint; influenceFactor, isEnabled and isIncremental; and billboard with any set of free axes (today only .all or .y). IK is #57. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #57 (IK).
- `2026-10-15T03:17:39Z`: Done: replicator, avoidOccluder, transform constraints, and billboard with any set of free axes. Left: acceleration (needs frame time passed to applyConstraints and per-node state), slider (needs physics, #38), and influenceFactor/isEnabled/isIncremental (Constraint is an enum; these need a wrapper type, which is an API decision).

---

## 92: Morph targets: names and normalized mode

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:animation
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T02:58:08Z
closed: 2026-10-15T02:58:08Z
+++

SCNMorpher can set weights by target name and has a normalized calculation mode. Here morphWeights are by index only, and blending is always additive. See docs/SceneKitComparison.md.

---

## 93: Hit-test gaps: options, segment and subtree tests, richer results

+++
status: closed
priority: low
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T03:03:32Z
closed: 2026-10-15T03:03:32Z
+++

SceneGraph.hitTest always tests both faces, returns every hit, and runs on the whole graph with an infinite ray. Missing: SceneKit options (backFaceCulling, boundingBoxOnly, firstFoundOnly), segment tests, tests on one subtree, and local coordinates, barycentrics and texture coordinates in Hit. See docs/SceneKitComparison.md.

---

## 94: Scene queries: project/unproject point, frustum queries

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:scenegraph
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T02:52:11Z
closed: 2026-10-15T02:52:11Z
+++

Missing SceneKit renderer APIs: projectPoint, unprojectPoint (Ray(viewPoint:) covers part of this), nodesInsideFrustum(of:) and isNode(_:insideFrustumOf:). Frustum culling exists but is internal to the Blinn-Phong renderer. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:17Z`: Related: #97 (frustum test could move to GeometryLite3D).

---

## 95: Renderer and view gaps: MSAA, prepare

+++
status: open
priority: low
kind: enhancement
labels: effort:l, area:renderer
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T03:09:12Z
+++

SceneView/SceneGraphElement have no multisampling, no debug overlays or statistics, and no way to build pipelines/PBR models ahead of time (like SCNSceneRenderer.prepare). SceneViewDelegate has only two callbacks: there are none for constraints applied or will/did render. See docs/SceneKitComparison.md.

- `2026-10-15T03:09:12Z`: Done: SceneViewDelegate.sceneView(didApplyConstraintsAtTime:), SceneView.Options.showsStatistics overlay, SceneGraph.statistics. Not verified on screen (did not run the app). Left: MSAA (the shadow and fog passes read depth, so they would need resolved or multisample-aware depth) and a prepare step.

---

## 96: Sort transparent entries back to front

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:renderer
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T02:51:27Z
closed: 2026-10-15T02:51:27Z
+++

No renderer sorts transparent entries back to front; you have to use renderingOrder by hand. ShaderMaterial with isTransparent is not sorted, and Blinn-Phong has no transparency yet (#36). See docs/SceneKitComparison.md.

- `2026-10-15T02:31:17Z`: Related: #36.

---

## 97: Use GeometryLite3D for transforms and other math

+++
status: open
priority: high
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:44Z
updated: 2026-10-15T02:31:17Z
+++

MSSG reimplements math that GeometryLite3D already has, or should have. Move it to GeometryLite3D and use it from there.

Already in GeometryLite3D but duplicated here:
- SIMD4.xyz: private copies in HitTest.swift and Constraint.swift; many places spell out SIMD3(m.columns.3.x, m.columns.3.y, m.columns.3.z) instead (SceneGraphRenderer, Culling, BlinnPhongMaterialRenderer, ShaderMaterial, Shadows, PBRSceneGraph, HitTest).
- LookAt: SceneView.swift has its own lookAt(eye:target:up:); Constraint.swift has lookRotation.
- Euler: exists in GeometryLite3D; MSSG has no Euler API (#79).

Candidates to add to GeometryLite3D, then use here:
- TRS (SceneGraph.TRS) on top of TransformComponents/decompose.
- BoundingBox.union (Bounds.swift).
- Ray and ray/triangle and ray/box tests (HitTest.swift).
- Frustum test (Culling.swift isInFrustum).
- Projection helpers in Shadows.swift: viewMatrix(eye:forward:), perspective(fieldOfView:near:far:), orthographic(halfSize:near:far:), the reversedDepth matrix (SceneGraphRenderer.swift), and an orthographic ProjectionProtocol type (#87).
- Matrix accessors such as translation/position of a float4x4.

- `2026-10-15T02:31:17Z`: Related: #79, #87, #94.

---

## 98: Demo: "Introduction to MSSG" keynote-style presentation

+++
status: new
priority: medium
kind: feature
labels: area:demo, effort:l
created: 2026-10-15T02:37:51Z
+++

A demo that presents MSSG like an Apple WWDC keynote, built entirely with MSSG. Slides and transitions are scenes, not SwiftUI views.

- Look: black or dark gradient background, large clean titles (Shape.text), one idea per slide, cinematic camera moves between slides.
- Content: one slide per feature (scene graph, shapes, Blinn-Phong and PBR materials, lights and shadows, fog and environment, actions, Transaction, constraints, animation blending, morphing and skinning, glTF and Model I/O import, hit testing, SceneView), each showing the feature live.
- Navigation: next/previous with arrow keys and click, plus auto-advance. Transitions use actions and Transaction (camera fly-throughs, fades once #76 lands).
- Lives in the demo package with the other demos, runnable from the app and from scenegraph-demos.

Gaps it may hit: text styling (#80), node opacity for fades (#76), post-processing such as bloom (#45).

---

## 99: Blinn-Phong crashes when no light reaches a batch

+++
status: closed
priority: high
kind: bug
labels: area:renderer, effort:xs
created: 2026-10-15T02:44:10Z
closed: 2026-10-15T02:44:10Z
+++

When light category masks leave a Blinn-Phong batch with no lights (for example only a light with lightCategoryBitMask 0b10 and a mesh in category 1), BlinnPhongMaterialRenderer passes an empty array to Lighting, which asserts (MetalSprocketsAddOns Lighting.swift:62). Seen while rendering SceneKit Features with only the red light visible.

---
