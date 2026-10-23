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
status: closed
priority: high
kind: enhancement
labels: effort:m, area:renderer
depends: 100
created: 2026-10-12T15:40:04Z
updated: 2026-10-15T13:18:16Z
closed: 2026-10-15T13:18:16Z
+++

Split from #32 (instancing done). BlinnPhongMaterial (MetalSprocketsAddOns) has no alpha or blend mode, so the renderer cannot tell transparent entries apart. Needs: alpha/blend mode on the material (upstream in MetalSprocketsAddOns, plus blending in BlinnPhongShader), then draw opaque first, transparent back-to-front with depth writes off. PBR already does this.

- `2026-10-14T13:31:44Z`: Related: #65 (renderingOrder demo needs transparency).
- `2026-10-14T13:36:18Z`: Looked at it. Punting: BlinnPhongMaterial and its shader live in MetalSprocketsAddOns, a remote dependency on main. The fragment shader always returns alpha 1, and the material has no opacity or blend mode, so transparency needs an upstream change. Options: (a) add opacity/blend mode to BlinnPhongMaterial and alpha output to BlinnPhongShader in MetalSprocketsAddOns (commit there; you push), then do the opaque-then-sorted-transparent split here; (b) give this repo its own Blinn-Phong shader in MetalSprocketsSceneGraphShaders with opacity, which duplicates AddOns code. Which do you want?
- `2026-10-14T13:54:48Z`: Decision: bring our own Blinn-Phong material and shaders into this repo (MetalSprocketsSceneGraphShaders + renderer target) and stop using BlinnPhongMaterial/BlinnPhongShader from MetalSprocketsAddOns. Then do the opaque/transparent split.
- `2026-10-15T02:31:16Z`: Related: #83, #96.
- `2026-10-15T12:02:24Z`: Depends on #100 (own Blinn-Phong).

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:physics
created: 2026-10-12T16:17:40Z
updated: 2026-10-15T20:07:19Z
closed: 2026-10-15T20:07:19Z
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
- `2026-10-15T20:07:19Z`: Added SceneGraph.PhysicsBody + Node.physicsBody (core, backend-neutral) and the MetalSprocketsSceneGraphPhysics target (SceneGraphPhysicsWorld on SwiftJolt by git URL): syncs bodies with the graph, kinematic push, writes dynamic poses (transform revision only). Physics demo ported. Docs not updated yet.

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

## 45: Camera post-processing: HDR, bloom, depth of field, tone mapping

+++
status: open
priority: low
kind: feature
labels: area:renderer, effort:l, deferred
created: 2026-10-13T20:20:23Z
updated: 2026-10-15T21:19:52Z
+++

Cameras have only a projection. SceneKit cameras have HDR, exposure, bloom, depth of field, motion blur, SSAO, vignette and color grading.

Want: post-processing settings on `Camera`, applied after the scene pass. Start with HDR, tone mapping and bloom.

- `2026-10-13T20:21:45Z`: Related: #43 (scene environment).
- `2026-10-15T03:32:22Z`: Done: SceneGraph.postProcessing with SSAO (unblurred), exposure, contrast, saturation and vignette, as compute passes after fog; Shadows demo toggles and a golden image. Left: HDR and tone mapping (needs float render targets in the renderers, including MetalSprocketsPBR), bloom and depth of field (need extra textures and blur passes), an SSAO blur.

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
status: closed
priority: low
kind: feature
labels: area:renderer, effort:l
created: 2026-10-13T20:20:23Z
updated: 2026-10-15T03:28:26Z
closed: 2026-10-15T03:28:26Z
+++

No particles. SceneKit has `SCNParticleSystem` attached to nodes.

Want: a particle emitter as node content, with a GPU simulation and a renderer for it.

---

## 51: Positional audio

+++
status: closed
priority: low
kind: feature
labels: area:audio, effort:m
created: 2026-10-13T20:20:23Z
updated: 2026-10-15T03:22:06Z
closed: 2026-10-15T03:22:06Z
+++

No audio. SceneKit has `SCNAudioSource`, `SCNAudioPlayer` and `audioListener`.

Want: audio sources on nodes, positioned in 3D from the world transform, and a listener node (default: the camera). Probably with AVAudioEngine.

---

## 52: Save and load a scene graph

+++
status: open
priority: medium
kind: feature
labels: area:assets, effort:l
created: 2026-10-13T20:20:23Z
updated: 2026-10-22T15:20:58Z
+++

A scene graph can't be saved. SceneKit can archive `SCNScene` (`.scn`) and export it.

Want: a file format for the node tree, transforms, content, materials, animation, skins and morph targets. Mesh data could be stored inline or as external references. Different from glTF and USD import (#16, #31).

- `2026-10-13T20:21:45Z`: Related: #16, #31, #37 (importers).
- `2026-10-13T20:45:21Z`: Looked at the model. Punting: this needs design decisions that the code cannot answer. (1) Materials are 'any Material' and projections 'any ProjectionProtocol' (open protocols), so decoding needs a type registry or a closed set of types. (2) Textures (MTLTexture inside PBRMaterial/BlinnPhongMaterial) and PBREnvironment maps have no source data to write back. (3) Container format: one JSON file with base64 mesh data, a package directory (scene.json + .bin buffers + images), or glTF export instead of a new format. Proposal: a package directory: scene.json (Codable nodes, TRS, skins by node id, morphs, clips, environment settings), one .bin per MetalMesh (vertex/index buffers + descriptor), PNG/EXR for textures read back from the GPU, and a MaterialCodec registry that renderer modules register (PBR, Blinn-Phong). Unblocker: OK this design (or prefer glTF export), and say if reading textures back from the GPU is acceptable.
- `2026-10-13T20:50:31Z`: Deferred: scene graphs are built by hand (or imported) for now.
- `2026-10-22T15:28:24Z`: Design decided: a package directory (.scenesprocketsd) with scene.json for the graph; glTF content by reference (the original file copied into the package); generated meshes written as glTF too (needs SwiftGLTF builder APIs). Core first: node tree, transforms, flags, shapes, materials, lights, cameras, environment/fog/post. Animations, skins, morphs, constraints, physics, particles later. Split into the issues below.

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

## 54: glTF scene graph loader: pointer animations

+++
status: closed
priority: low
kind: enhancement
labels: area:assets, effort:m
created: 2026-10-13T20:37:21Z
updated: 2026-10-15T23:35:09Z
closed: 2026-10-15T23:35:09Z
+++

MetalSprocketsSceneGraphGLTF (#16) does not map these glTF features into the scene graph:

- EXT_mesh_gpu_instancing copies.
- KHR_node_visibility. The `isVisible` property is internal in MetalSprocketsGLTF.
- Orthographic cameras. The scene graph has no orthographic projection.
- KHR_animation_pointer channels for materials, lights, cameras and visibility.

The loader adds a warning for skipped cameras and channels.

- `2026-10-15T02:31:16Z`: Related: #87.
- `2026-10-15T02:59:59Z`: Done: EXT_mesh_gpu_instancing copies become child nodes (skinned meshes keep one), KHR_node_visibility sets isVisible. Left: orthographic cameras (needs #87) and KHR_animation_pointer channels (needs key-path animation targets, #89).
- `2026-10-15T19:48:51Z`: Orthographic cameras now load (done in #87); only KHR_animation_pointer remains.
- `2026-10-15T21:32:48Z`: Done: KHR_animation_pointer channels for KHR_node_visibility, lights (color, intensity, range, spot cone angles) and cameras (yfov, ymag, znear, zfar) become property channels; new Property statics visibility, lightRange, lightInner/OuterConeAngle, cameraVerticalFieldOfView, cameraHalfHeight, cameraNear/Far. Left: material channels. MetalSprocketsGLTF parses /materials/N/... into GLTFAnimationPointer.MaterialProperty and PBRMaterial.AnimatedState, both internal. Unblocker: OK to make those public in MetalSprocketsGLTF (and push), or should the scene graph map material pointers itself? Camera xmag/aspectRatio are skipped on purpose (width follows the view).
- `2026-10-15T21:58:17Z`: No API consumers: public API can change freely. Making MetalSprocketsGLTF material pointer types public is fine (MetalSprocketsGLTF#175).

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

## 59: Shadow flicker on still frames (self-shadowed fox, Dice tray and dice)

+++
status: open
priority: medium
kind: bug
labels: area:renderer, effort:m, deferred
created: 2026-10-14T01:11:25Z
updated: 2026-10-21T21:03:02Z
+++

In the Imported Assets demo, shadowed pixels sometimes flash unshadowed for a frame. It is mostly the fox's self-shadowed side. It happens with the camera still and the animation paused (speed 0). The flashes are random and rare. They are clearly less frequent with the inspector sidebar closed, so they likely depend on frame timing.

Context: SceneGraphShadows draws a shadow map per directional light (ShadowCasterDepthPass), then the AddOns ShadowMaskPass darkens the drawable in screen space using the view's depth texture. Up to 3 frames are in flight, and they share one depth texture.

Fixed already: a whole-shadow blink while rotating the camera. The scene pass now starts with QueueBarrier(after: .dispatch, before: [.vertex, .fragment]).

Tried, no effect:
- `.barrierAfterPass(after: .dispatch, beforeQueueStages: [.vertex, .fragment])` on the mask pass.
- 6 shadow map slots instead of 3.

Verified with per-frame logging: every frame drew shadows, and the depth and mask passes used the same shadow map slot. Presentation (signalDrawable) comes after the whole command buffer.

Next steps: capture a GPU trace of a flashing frame, or render into renderer-owned depth textures, one per frame in flight, so frames share nothing.

\- `2026-10-14T01:14:55Z`: Possibly caused by shadow acne (#60): borderline texels flip between lit and shadowed. Check again after fixing #60.
\- `2026-10-21T21:02:38Z`: Also seen in the Dice demo (Demos > Dice), on what should be a completely still frame: after the dice land and settle, the shadows of the tray walls and of the dice flicker. Nothing is moving then: Jolt puts the settled dice to sleep, so their transforms stop changing (logged: a settled die keeps the same world position frame after frame), and sceneGraph.bounds stays at the tray ((-3.2, -0.2, -2.2) to (3.2, 0.6, 2.2)), so the directional shadow view (fitted to bounds in shadowViewsAndDroppedLights) does not move either. That rules out shadow-frustum shimmer from changing bounds.

Setup: one directional light (Sun, eye [2.5, 7, 3] looking at the origin, intensity 2.5) plus a point fill light; SceneGraphShadows(intensity: 0.65, softness: 2); Blinn-Phong tray (pine texture), PBR dice.

Not reproducible offscreen: DemoSnapshot renders one frame at a time and waits for the GPU, and those frames are stable. That fits the frame-timing theory above (frames in flight sharing the view depth texture). #60 acne is also visible on the tray floor at this angle, but acne should not flicker on a still frame unless the inputs change.

---

## 60: Shadow acne on lit surfaces (depth bias ineffective)

+++
status: open
priority: medium
kind: bug
labels: area:renderer, effort:s, deferred
created: 2026-10-14T01:14:55Z
updated: 2026-10-20T02:27:43Z
+++

Surfaces that face the light show a fine dotted shadow pattern, and shadow edges are stepped. It is clearly visible on the fox's head in the Imported Assets demo. It may also cause the random flicker in #59, because borderline texels flip between lit and shadowed.

Cause: the hardware depth bias does almost nothing with the depth32Float shadow map. The constant bias is measured in float ULPs, so depthBias = 2 is close to zero. Only the slope part helps, and only on steep faces. The shadow map also covers the whole scene bounds (about 6 units) at 2048², so the fox gets few texels.

Fix: apply a world-space depth offset in the ShadowCasters vertex shaders. Push caster depth away from the light by about 1 to 2 texels, computed as orthoSize * 2 / resolution and converted to clip z through the orthographic range. Make it a property of SceneGraphShadows. Optionally fit the shadow map tighter (casters plus receivers in view), or raise the resolution.

Related: #59.

- `2026-10-16T02:38:45Z`: Tried to reproduce in a unit test: a flat plane lit by a directional or spot light, at about 7° and 20° grazing angles, with a distant object to stretch the shadow map. Covered both shadow paths: Blinn-Phong in-shader sampling and the screen-space mask (ShaderMaterial). Result: 0 self-shadowed pixels at 128x128 in every case. A box floor showed dark pixels, but those were side faces facing away from the light, so they were real shadows. Punting: I can't confirm that the depth-bias explanation is the cause. Unblocker: a screenshot or repro steps in the Imported Assets demo (window size, light setup), or permission to change the bias without a failing test.

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
status: closed
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-14T15:18:06Z
updated: 2026-10-15T03:20:48Z
closed: 2026-10-15T03:20:48Z
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
status: closed
priority: high
kind: bug
labels: area:renderer, effort:m
depends: 100
created: 2026-10-14T15:36:23Z
updated: 2026-10-15T12:36:55Z
closed: 2026-10-15T12:36:55Z
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
- `2026-10-15T12:02:24Z`: Depends on #100 (own Blinn-Phong).
- `2026-10-15T12:36:55Z`: Fixed for Blinn-Phong (in-repo shader after #100): each light's shadow slices are sampled while shading and scale only that light's diffuse and specular; ambient is not shadowed; light category masks pick the lights per batch, so a light that does not reach a mesh cannot shadow it. The screen-space mask now skips Blinn-Phong pixels and is not run at all when every mesh is Blinn-Phong. PBR is still on the screen-space path: #102.

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
status: closed
priority: medium
kind: bug
labels: area:demo, effort:s
created: 2026-10-14T16:40:19Z
updated: 2026-10-16T02:35:08Z
closed: 2026-10-16T02:35:08Z
+++

Since moving the demos to DemoKit (#72), the top of the demo view sits under the window toolbar. The FPS overlay (topTrailing, padded) is partly hidden, and the configuration inspector's Form starts under the toolbar (the first rows are cut off). Screenshots: 2026-10-14 12.16.32 and 12.21.40.

What is known:
- DemoKit's own description overlay on the same content is placed correctly, so its container respects the safe area.
- MetalSprocketsExamples uses the same pattern (RenderView, .interactiveCamera, a topTrailing frame-timing overlay, .demoConfiguration { Form }) and, as far as known, looks fine.
- Switching from our own .inspector to .demoConfiguration did not fix it.

The difference must be in SceneDemoView or SceneView: .onGeometryChange, .onTapGesture, the CameraControl modifier, the demo .toolbar items, or the metal view settings that change with shadows. Next: run the app and bisect those modifiers.

- `2026-10-14T16:47:38Z`: View hierarchy (MetalSprocketsSceneGraphDemo[49042].viewhierarchy): every split item, including the detail and the inspector hosting views, is full window height (1031 pt), which is normal on macOS 26. The visible rect starts 52 pt down (under the toolbar). The MTKView platform host frame is also 1031 pt tall from y=0, so SwiftUI lays out our detail content (and the inspector Form) with no top safe-area inset. Nothing in MetalSprocketsUI, Interaction3D or SceneView calls ignoresSafeArea. DemoKit's description overlay (a ScrollView) is inset correctly. Hypothesis, not verified: DemoKit's detail wrapper (ZStack { Color.clear; content }.clipped(), with .inspector applied inside it) loses the safe area for non-scroll content; the old ContentView put the demo directly in the split view's detail and was fine. Check: does MetalSprocketsExamples show its frame-timing overlay under the toolbar too?
- `2026-10-14T17:07:28Z`: Also happens in MetalSprockets-Examples, so it's in DemoKit. Filed DemoKit #22 (content underlaps toolbar) and added findings to DemoKit #21 (inspector). Blocked on those.
- `2026-10-16T02:34:31Z`: Unblocked: upstream fix is in the resolved dependencies.
- `2026-10-16T02:35:08Z`: Fixed upstream in DemoKit (#21, #22); the resolved DemoKit includes the fix.

---

## 75: Reach 120 fps in every demo

+++
status: open
priority: medium
kind: enhancement
labels: area:renderer, effort:l, deferred
created: 2026-10-14T16:41:14Z
updated: 2026-10-15T20:11:38Z
+++

Target: 120 fps (8.3 ms frames) on a ProMotion display in every demo. Some demos drop well below that.

Known so far:
- SceneKit Features with shadows on: about 31 fps (30 ms frames, 3.1 ms GPU). All 8 shadow views run: sun + spotlight + six for the red point light. Shadows are now off by default (#71).
- Imported Assets: about 90 fps before GPU skinning for shadow casters; CPU shadow prep went from 2.8 ms to 0.13 ms. Not re-measured since.
- The demo frame meter shows CPU frame time well above GPU time in several demos, so the main thread is probably the limit, not the GPU.

Likely CPU costs per frame: SceneGraphElement rebuilding element trees; meshEntries/bounds traversal; CPU deformation (Blinn-Phong skin/morph, deformed() copies); ShaderMaterialRenderer creating one RenderPipeline per entry; renderBatches grouping; SceneView reading bounds each frame for the viewpoint; SwiftUI updates from the DemoScene observation and frame-timing overlay.

Plan: measure each demo (CPU and GPU, Instruments time profile), list the top costs per demo, fix them one by one, and add a CLI timing mode (scenegraph-demos --bench <id>, see #73) to track regressions.

- `2026-10-15T19:45:35Z`: Looked at measuring headlessly: scenegraph-demos --render uses OffscreenRenderer, which skips SwiftUI, the display link and SceneView's per-frame work, the suspected main-thread costs. Punting: the target (120 fps on ProMotion) and the root causes need on-screen runs with Instruments, which opens windows. Unblocker: OK to run the demo app and profile it, or split out a --bench <id> CLI mode (renders N frames through the same per-frame path and reports CPU/GPU ms) as its own issue first.

---

## 76: Node opacity and fade actions

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:scenegraph
depends: 100
created: 2026-10-15T02:28:06Z
updated: 2026-10-15T19:52:16Z
closed: 2026-10-15T19:52:16Z
+++

SceneKit has SCNNode.opacity (inherited by children) and fadeIn/fadeOut/fadeOpacity actions. Nodes here have no opacity, so there are no fade actions either. Want: Node.opacity applied by every renderer, plus the fade actions. See docs/SceneKitComparison.md.

- `2026-10-15T12:02:24Z`: Depends on #100 (own Blinn-Phong).
- `2026-10-15T19:52:16Z`: Added Node.opacity (inherited), MeshEntry.opacity/isTransparent, Material.appliesNodeOpacity, fade actions, Blinn-Phong support, and ShaderMaterialTransforms.opacity (samples use it). PBR split out as #108.

---

## 77: Node flattenedClone

+++
status: closed
priority: low
kind: feature
labels: effort:s, area:scenegraph
created: 2026-10-15T02:28:06Z
updated: 2026-10-16T12:04:39Z
closed: 2026-10-16T12:04:39Z
+++

Missing SceneKit equivalents: clone()/flattenedClone(), childNode(withName:recursively:), replaceChildNode(_:with:), and enumerateHierarchy's stop flag. Want them on SceneGraph.Node and SceneGraph.visit. See docs/SceneKitComparison.md.

- `2026-10-15T03:10:47Z`: Done: clone(), childNode(withLabel:recursively:), replaceChild(_:with:), SceneGraph.traverse with skipChildren/stop. Left: flattenedClone (merging meshes needs matching vertex layouts).
- `2026-10-16T12:04:39Z`: Added Node.flattenedClone(): merges every visible mesh in the subtree into one mesh, with transforms baked into positions, normals and tangents. Each submesh keeps its material. Returns nil for mixed vertex layouts or skinned/morphed meshes. Tests did not compile before the change.

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
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:scenegraph
depends: 97
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T19:35:14Z
closed: 2026-10-15T19:35:14Z
+++

Missing SceneKit equivalents: eulerAngles; settable worldPosition/worldOrientation/worldTransform; convertPosition/convertVector/convertTransform(from:/to:); and a one-shot look(at:up:localFront:) that targets a point. Today look-at only exists as a constraint on a node. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #97 (GeometryLite3D has Euler and LookAt).
- `2026-10-15T02:35:20Z`: Depends on #97: build these helpers on GeometryLite3D (Euler, LookAt, matrix accessors), adding what is missing there first, not as new local math in MSSG.
- `2026-10-15T19:35:14Z`: Added NodeSpace.swift: eulerAngles, settable worldTransform/worldPosition/worldOrientation, convertPosition/convertVector/convertTransform(from:/to:), look(at:up:localFront:). Built on GeometryLite3D Euler, Transform3D and lookRotation.

---

## 80: Shape options: segment counts, box chamfer, geodesic sphere, plane corner radius

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:scenegraph, deferred
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T21:19:11Z
+++

SceneGraph.Shape has no segment counts, no box chamferRadius, no sphere isGeodesic, and no plane corner radius. SCNText's chamfer, flatness, container frame and wrapping are missing too. Needs SwiftMesh support for some of these. See docs/SceneKitComparison.md.

---

## 81: New shapes: tube, pyramid, floor, extruded Bézier path

+++
status: open
priority: low
kind: feature
labels: effort:m, area:scenegraph, deferred
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T21:19:11Z
+++

SceneKit has SCNTube, SCNPyramid, SCNFloor (infinite, with optional reflections) and SCNShape (an extruded Bézier path). Shape has none of them. See docs/SceneKitComparison.md.

---

## 82: GPU tessellation and adaptive subdivision

+++
status: open
priority: low
kind: feature
labels: effort:l, area:renderer, deferred
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T21:19:11Z
+++

SceneKit has subdivisionLevel, wantsAdaptiveSubdivision, the SCNGeometryTessellator and edge creases. There is no equivalent here. See docs/SceneKitComparison.md.

- `2026-10-15T03:24:47Z`: Done: CPU Loop subdivision (MetalMesh.subdivided(levels:smooth:), Node.subdivisionLevel), welding seams so they stay closed. Left: GPU tessellation (SCNGeometryTessellator), adaptive subdivision, edge creases.

---

## 83: Blinn-Phong material: normal maps, emission, cull mode

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:renderer
depends: 100
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T19:43:07Z
closed: 2026-10-15T19:43:07Z
+++

BlinnPhongMaterial has only ambient, diffuse and specular color sources and shininess. It has no normal map, no emission, and no double-sided/cull mode setting. Transparency is #36. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #36.
- `2026-10-15T12:02:24Z`: Depends on #100 (own Blinn-Phong).
- `2026-10-15T19:43:07Z`: Added emission (color or tinted texture), normalMap (tangent frame from screen derivatives, +Y up) and cullMode (CCW front; mirrored transforms flip winding) to BlinnPhongSceneMaterial. Tests cover emission, a +X normal map and both cull modes; the bitangent sign (+Y vs -Y green) is not covered by a test.

---

## 84: Material settings: blend modes, depth read/write, color write mask, wireframe

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T20:22:03Z
closed: 2026-10-15T20:22:03Z
+++

SceneKit materials have blendMode (alpha, add, subtract, multiply, screen, replace), writesToDepthBuffer/readsFromDepthBuffer, colorBufferWriteMask and fillMode .lines. Here only ShaderMaterial.isTransparent and PBR alphaMode exist. Want these settings to work across the material families. See docs/SceneKitComparison.md.

- `2026-10-15T20:22:03Z`: Added MaterialRenderState (blendMode alpha/add/subtract/multiply/screen/replace, writes/readsFromDepthBuffer, colorWriteMask, fillMode) on BlinnPhongSceneMaterial and ShaderMaterial. Blend modes that mix with the background make the material transparent (draw order). PBR split out as #114 (needs MetalSprocketsPBR hooks).

---

## 85: Shader modifiers

+++
status: open
priority: low
kind: feature
labels: effort:xl, area:renderer, deferred
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T21:19:12Z
+++

SceneKit shader modifiers inject code at geometry, surface, lighting and fragment entry points of the built-in materials. ShaderMaterial (like SCNProgram) replaces the whole shader. Want a way to tweak the built-in Blinn-Phong/PBR shading without rewriting it. See docs/SceneKitComparison.md.

---

## 86: Light gaps: ambient node, attenuation, temperature, IES and area lights

+++
status: open
priority: low
kind: feature
labels: effort:l, area:renderer, deferred
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T21:19:12Z
+++

Missing SceneKit equivalents: an ambient light type as a node (today it is per renderer: BlinnPhongMaterialRenderer.ambientLightColor), attenuationStartDistance and attenuationFalloffExponent, color temperature, and IES, area and probe lights. See docs/SceneKitComparison.md.

---

## 87: Orthographic cameras

+++
status: closed
priority: medium
kind: feature
labels: effort:s, area:renderer
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T19:48:51Z
closed: 2026-10-15T19:48:51Z
+++

GeometryLite3D only has PerspectiveProjection, so there is no orthographic camera. The glTF and Model I/O loaders skip orthographic cameras with a warning. Needs a projection type in GeometryLite3D first. Also unblocks part of #54. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #97 (orthographic projection belongs in GeometryLite3D), #54.
- `2026-10-15T13:29:45Z`: Blocked on GeometryLite3D #1 (OrthographicProjection).
- `2026-10-15T19:22:45Z`: Unblocked: GeometryLite3D now has OrthographicProjection (used for directional shadows since #97).
- `2026-10-15T19:48:52Z`: Camera already took any ProjectionProtocol, so OrthographicProjection rendered; added a render test. glTF orthographic cameras now load (ymag as halfHeight, xmag ignored like SceneKit). Model I/O orthographic cameras are still skipped: MDLCamera has no orthographic size.

---

## 88: Shadow gaps: cascades, per-light settings

+++
status: open
priority: low
kind: enhancement
labels: effort:l, area:renderer, deferred
created: 2026-10-15T02:28:07Z
updated: 2026-10-15T21:19:41Z
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
status: closed
priority: low
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T23:42:34Z
closed: 2026-10-15T23:42:34Z
+++

Missing: SCNReplicatorConstraint, SCNAccelerationConstraint, SCNSliderConstraint, SCNAvoidOccluderConstraint and SCNTransformConstraint; influenceFactor, isEnabled and isIncremental; and billboard with any set of free axes (today only .all or .y). IK is #57. See docs/SceneKitComparison.md.

- `2026-10-15T02:31:16Z`: Related: #57 (IK).
- `2026-10-15T03:17:39Z`: Done: replicator, avoidOccluder, transform constraints, and billboard with any set of free axes. Left: acceleration (needs frame time passed to applyConstraints and per-node state), slider (needs physics, #38), and influenceFactor/isEnabled/isIncremental (Constraint is an enum; these need a wrapper type, which is an API decision).
- `2026-10-15T21:33:11Z`: Reviewed what is left (acceleration, slider, influenceFactor/isEnabled/isIncremental). Punting: each changes public API. influenceFactor/isEnabled/isIncremental need Constraint to become a wrapper (e.g. struct Constraint { kind; influence; isEnabled; isIncremental }) or new enum cases; acceleration needs applyConstraints(pointOfView:deltaTime:) plus per-node velocity state; slider can now use physics (#38 closed) but needs a collision query API from the physics module. Unblocker: OK to (1) turn Constraint into a struct wrapping today's enum as 'kind', with influence/isEnabled/isIncremental fields, and (2) add deltaTime to applyConstraints?
- `2026-10-15T21:58:16Z`: No API consumers: public API can change freely. Go ahead with a Constraint wrapper struct and a deltaTime argument on applyConstraints; no unblocker needed.
- `2026-10-15T23:42:34Z`: Done: Constraint is now a struct (kind, influenceFactor, isEnabled) with static factories per kind; new acceleration kind; applyConstraints(pointOfView:deltaTime:). Slider and isIncremental split to a new issue.

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
labels: effort:l, area:renderer, deferred
created: 2026-10-15T02:28:08Z
updated: 2026-10-15T21:19:12Z
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
status: closed
priority: high
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:44Z
updated: 2026-10-15T19:10:52Z
closed: 2026-10-15T19:10:52Z
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

\- `2026-10-15T02:31:17Z`: Related: #79, #87, #94.
\- `2026-10-15T13:29:45Z`: Done here: GeometryLite3D's SIMD4.xyz replaces the private copies and the spelled-out columns.3 positions (except PBRSceneGraph.swift, where MetalSprocketsPBR's own public xyz makes it ambiguous); LookAt.cameraMatrix replaces SceneView's lookAt. The rest needs GeometryLite3D first, filed there: #1 OrthographicProjection, #2 float4x4 translation/normal matrix, #3 BoundingBox helpers, #4 Ray and intersections, #5 frustum test, #6 projection/view helpers, #7 TRS, #8 quaternion look rotation.
\- `2026-10-15T18:54:18Z`: GeometryLite3D now has the missing pieces (upstream #1–#8 done; BoundingBox3D rename and union adopted in 6fa9359e). Remaining work, one step at a time:
1. float4x4.normalMatrix: replace normalMatrix() in BlinnPhongMaterialRenderer.swift and .inverse.transpose in ShaderMaterial.swift.
2. simd_quatf.lookRotation: replace the private lookRotation in Constraint.swift.
3. OrthographicProjection: replace orthographic(halfSize:near:far:) in Shadows.swift; also check viewMatrix(eye:forward:), perspective(...), and the reversedDepth matrix in SceneGraphRenderer.swift against Projection/ViewProjection.
4. Ray3D: replace HitTest.Ray and the private triangle and slab tests in HitTest.swift. HitTest.Ray is public API.
5. Frustum and ViewProjection: replace the frustum tests in Culling.swift and Queries.swift, and project/unproject/ray in Queries.swift. The reversed-depth convention must match the renderer.
6. Transform3D: replace SceneGraph.TRS (public API; keep a typealias?). Transform3D(matrix:) returns nil for lossy matrices, but TRS(matrix:) falls back to identity. Decide which behaviour callers get.

- `2026-10-15T19:03:42Z`: Step 4 (Ray3D) is blocked on GeometryLite3D #33 (box test returns nil from inside the box), #34 (NaN for axis-parallel rays on a face plane) and #35 (fixed epsilon misses small triangles). The public SceneGraph.Ray(viewPoint:...) also works out reversed depth by itself, but Ray3D needs a flag or a ViewProjection.
- `2026-10-15T19:10:52Z`: Done except Ray3D, split out as #107.
- `2026-10-15T21:58:17Z`: No API consumers: public API can change freely. Replace HitTest.Ray and SceneGraph.TRS outright; no typealias needed.
- `2026-10-15T22:00:46Z`: Correction: do NOT add typealiases or deprecations to keep old callers working. Break the API and update all callers. Replace SceneGraph.TRS and HitTest.Ray outright.

---

## 98: Demo: "Introduction to MSSG" keynote-style presentation

+++
status: closed
priority: medium
kind: feature
labels: area:demo, effort:l
created: 2026-10-15T02:37:51Z
updated: 2026-10-16T01:55:15Z
closed: 2026-10-16T01:55:15Z
+++

A demo that presents MSSG like an Apple WWDC keynote, built entirely with MSSG. Slides and transitions are scenes, not SwiftUI views.

- Look: black or dark gradient background, large clean titles (Shape.text), one idea per slide, cinematic camera moves between slides.
- Content: one slide per feature (scene graph, shapes, Blinn-Phong and PBR materials, lights and shadows, fog and environment, actions, Transaction, constraints, animation blending, morphing and skinning, glTF and Model I/O import, hit testing, SceneView), each showing the feature live.
- Navigation: next/previous with arrow keys and click, plus auto-advance. Transitions use actions and Transaction (camera fly-throughs, fades once #76 lands).
- Lives in the demo package with the other demos, runnable from the app and from scenegraph-demos.

Gaps it may hit: text styling (#80), node opacity for fades (#76), post-processing such as bloom (#45).

- `2026-10-15T20:27:29Z`: Added KeynoteDemo ("Introduction to SceneGraph", first in the catalog): 10 slides along +X, camera flights with Transaction, slide cross-fades with node opacity, Next/Previous toolbar actions on the arrow keys, click to advance, Auto-advance parameter. DemoAction gained a key shortcut and DemoScene.usesSceneCamera turns off user camera control. Slides for the remaining listed features are #115.
- `2026-10-15T21:10:39Z`: Reopened: slides should also show actual code, keynote style — a short Swift snippet beside each live feature (for example the Node/action/constraint calls that build what is on screen). Open question: render code as 3D text (Shape.text, monospaced font, maybe syntax colors per token) or as a textured quad from a rendered image; either way it should be built from scene graph features. Missing slides are still #115.
- `2026-10-16T00:03:20Z`: Code panels added: CodePanel renders a syntax-highlighted Swift snippet with SwiftUI ImageRenderer into a texture on a plane (emission + diffuse alpha). Every feature slide shows the code behind it. Camera moved back to fit the panels. scenegraph-demos --render gained --slide N; DemoSnapshot uses the scene camera when usesSceneCamera is set.

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

## 100: Own Blinn-Phong material, renderer and shaders (stop using AddOns')

+++
status: closed
priority: high
kind: enhancement
labels: area:renderer, effort:l
created: 2026-10-15T12:02:03Z
updated: 2026-10-15T12:18:52Z
closed: 2026-10-15T12:18:52Z
+++

Decision on #36 (2026-10-14): bring Blinn-Phong into this repo and stop using BlinnPhongMaterial, BlinnPhongShader and Lighting from MetalSprocketsAddOns.

Scope:
- A Blinn-Phong material type in MetalSprocketsSceneGraph (ambient, diffuse, specular as color or texture; shininess), replacing AddOns' BlinnPhongMaterial everywhere (renderer, ModelIO loader, tests, demos).
- Shaders in MetalSprocketsSceneGraphShaders: directional, point and spot lights with node orientation, range and cone falloff; instanced and non-instanced paths; reversed depth.
- BlinnPhongMaterialRenderer keeps culling, front-to-back sorting, instancing and the CPU deformation fallback.
- Same output as today for existing scenes (golden images or pixel tests before and after).

Unblocks: #36 (opacity and transparency), #71 (per-light shadows sampled in the fragment shader), #83 (normal maps, emission, cull mode), the Blinn-Phong half of #76 (node opacity), and GPU skinning/morphing for Blinn-Phong.

---

## 101: Extruded text meshes have zero-length normals

+++
status: closed
priority: medium
kind: bug
labels: area:scenegraph, effort:s
created: 2026-10-15T12:18:52Z
updated: 2026-10-15T19:31:18Z
closed: 2026-10-15T19:31:18Z
+++

SceneGraph.Shape.text("SceneGraph", fontName: "Helvetica-Bold") from SwiftMesh's extrudedText has 296 of 6186 vertices with zero-length normals, all in glyphs with holes (e, a, p). The old AddOns Blinn-Phong shader normalized them to NaN and drew those glyphs white; the in-repo shader (#100) now falls back to the face normal, but PBR and ShaderMaterial still get zero normals. Other shapes are fine. Fix in SwiftMesh's text extrusion (or recompute missing normals in Shape.metalMesh).

- `2026-10-15T19:31:18Z`: Worked around in Shape.mesh() by triangulating extruded text before adding flat normals; planar UVs now cover hole corners too. Root cause filed as SwiftMesh #171.

---

## 102: PBR: sample shadows per light in the shader

+++
status: closed
priority: medium
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-15T12:36:55Z
updated: 2026-10-16T12:13:29Z
closed: 2026-10-16T12:13:29Z
+++

Since #71, Blinn-Phong samples each light's shadow slices while shading, so a light only darkens what it lights. PBR meshes still go through the screen-space mask, which multiplies every light's shadow and darkens the whole pixel: surfaces facing away from a shadow-casting light, or outside its category, are darkened anyway (the original #71 bug). Fix: pass SceneGraphRenderContext.shadow and lightShadowSlices into MetalSprocketsPBR's lighting and scale each PBRLight's contribution by its own shadow (upstream change), then mark PBRSceneMaterial with SamplesShadowsInShader. ShaderMaterial could get a helper for the same.

- `2026-10-15T19:43:58Z`: Checked MetalSprocketsPBR (9b5495b): PBRLight and the lighting shader have no shadow input. Punting: the fix is an upstream shader/API change that then has to be released before MSSG can use it. Filed as MetalSprocketsPBR #14. Unblocker: implement #14 there (or tell me to do it in that repo), then this is wiring plus SamplesShadowsInShader.
- `2026-10-16T02:34:31Z`: Unblocked: upstream fix is in the resolved dependencies.
- `2026-10-16T02:39:20Z`: Checked MetalSprocketsPBR #14 (PBRShadows, PBRLight.shadowSliceStart/Count). The wiring is straightforward: build PBRShadows from context.shadow, using the submission's depth texture and our greaterEqual sampler, and set the slices on each PBRLight. Punting: PBRShadows has no intensity or color, so PBR would lose SceneGraphShadows.intensity (default 0.6) and color, which the screen-space mask supports today. Filed MetalSprocketsPBR#17. Unblocker: land #17, or accept full-strength, untinted PBR shadows.
- `2026-10-16T12:07:45Z`: Unblocked: MetalSprocketsPBR#17 landed.
- `2026-10-16T12:13:29Z`: PBRSceneMaterial is now SamplesShadowsInShader. PBRMaterialRenderer passes SceneGraphShadows to MetalSprocketsPBR's PBRShadows (map for the current submission, slices, softness, intensity, color), and sets each PBRLight's shadow slices. Used in both the main pass and the transmission pre-pass. Test pbrShadowsDimOnlyTheirOwnLight fails before the change (the fill light was darkened by the sun's screen-space shadow).

---

## 103: Move the particle engine into its own target

+++
status: closed
priority: low
kind: task
labels: area:renderer, effort:s
created: 2026-10-15T13:22:15Z
updated: 2026-10-15T23:44:52Z
closed: 2026-10-15T23:44:52Z
+++

Split the particle simulation (ParticleSystem: emission, integration, size and color over life, SplitMix64) out of MetalSprocketsSceneGraph into its own target (e.g. MetalSprocketsParticles) that depends only on simd, not on the scene graph. Make advance(by:emitterTransform:), instances() and the particle list public there. MetalSprocketsSceneGraph depends on it and keeps the scene integration: Node.particleSystems, SceneGraph.advanceParticles(by:), visibleParticleSystems() and ParticlesElement drawing. Keep SceneGraph.ParticleSystem as a typealias so callers do not change.

- `2026-10-15T21:58:17Z`: No API consumers: public API can change freely. The SceneGraph.ParticleSystem typealias is optional.
- `2026-10-15T22:00:46Z`: Correction: do NOT add typealiases or deprecations to keep old callers working. Break the API and update all callers. No SceneGraph.ParticleSystem typealias.

---

## 104: Move the audio engine into its own target

+++
status: closed
priority: low
kind: task
labels: area:audio, effort:s
created: 2026-10-15T13:22:24Z
updated: 2026-10-15T23:47:16Z
closed: 2026-10-15T23:47:16Z
+++

Split the positional audio engine out of MetalSprocketsSceneGraph into its own target (e.g. MetalSprocketsAudio) that depends only on AVFAudio and simd, not on the scene graph: AudioPlayer (buffer or file, loops, volume) and a spatial mixer (AVAudioEngine plus AVAudioEnvironmentNode) with an API to attach/detach players, set each player's position, pause/resume, and set the listener transform. MetalSprocketsSceneGraph depends on it and keeps the scene integration: Node.audioPlayers and SceneAudio.update(sceneGraph:listener:) (walk the graph, push world positions, pause players on hidden nodes, detach removed ones), plus SceneView(audio:). Keep SceneGraph.AudioPlayer as a typealias so callers do not change. Same shape as #103.

- `2026-10-15T21:58:17Z`: No API consumers: public API can change freely. The SceneGraph.AudioPlayer typealias is optional.
- `2026-10-15T22:00:46Z`: Correction: do NOT add typealiases or deprecations to keep old callers working. Break the API and update all callers. No SceneGraph.AudioPlayer typealias.

---

## 105: Move each material renderer into its own target

+++
status: closed
priority: low
kind: task
labels: area:renderer, effort:m
created: 2026-10-15T13:23:03Z
updated: 2026-10-16T02:25:52Z
closed: 2026-10-16T02:25:52Z
+++

Split the material families out of MetalSprocketsSceneGraph so apps link only what they use:
- MetalSprocketsSceneGraphBlinnPhong: BlinnPhongSceneMaterial, BlinnPhongMaterialRenderer, BlinnPhongSceneGraphElement, BlinnPhong.metal.
- MetalSprocketsSceneGraphPBR: PBRSceneMaterial, PBRMaterialRenderer, PBRNodeLayout, PBRSceneGraphModelBuilder, environment background (the only part needing MetalSprocketsPBR).
- Flat/unlit and custom-shader materials: ShaderMaterial, ShaderMaterialRenderer and their sample shaders (or a 'Flat' unlit material if one is added).
The core keeps SceneGraph, SceneGraphElement, the SceneGraphMaterialRenderer and SceneGraphBackgroundRenderer protocols, shadows, fog, post-processing and particles drawing.

Needs public API that is internal today: SamplesShadowsInShader, SceneGraphShadows.Sampling fields, SceneGraphRenderContext.shadow/lightShadowSlices, MeshEntry.deformed, culledMeshEntries/sortedFrontToBack/groupedByVertexDescriptor, and per-target shader bundles. Loaders that pick materials (ModelIOSceneGraph .pbr/.blinnPhong, GLTFSceneGraph uses PBR) need to move with or depend on the right renderer target. SceneView's default renderers (Blinn-Phong + PBR) would move to the UI layer or be passed in. Note: this reverses part of the earlier single-target merge for the renderers only.

- `2026-10-15T23:52:40Z`: Done: MetalSprocketsSceneGraphPBR target with PBRSceneMaterial, PBRMaterialRenderer, PBRNodeLayout, the glTF loader and the Model I/O loader. The core no longer depends on MetalSprocketsPBR, MetalSprocketsGLTF or SwiftGLTF. SceneView's default renderers are now Blinn-Phong only; pass PBRMaterialRenderer for PBR. Left: Blinn-Phong and ShaderMaterial targets. They need SceneView's default renderer, Shadows.swift, MaterialRenderState and Node.swift untangled, many internal render helpers made public, and a decision on shaders: keep BlinnPhong.metal and ShaderMaterialSamples.metal in the shared MetalSprocketsSceneGraphShaders bundle, or give each target its own bundle.
- `2026-10-16T02:25:52Z`: Done: MetalSprocketsSceneGraphBlinnPhong and MetalSprocketsSceneGraphShaderMaterial targets. SceneView.renderers is now required. Shaders stay in the shared MetalSprocketsSceneGraphShaders bundle. MetalSprocketsSceneGraphPBR depends on Blinn-Phong for the Model I/O loader. Made public: SamplesShadowsInShader, SceneGraphShadowMap (read-only parts), SceneGraphShadows.Sampling fields (read-only), materialDraw, materialRenderState, vertexBuffers, culledMeshEntries, sortedFrontToBack, groupedByVertexDescriptor.

---

## 106: Make API more SceneKit-like

+++
status: open
priority: medium
kind: enhancement
labels: effort:xl, area:scenegraph, deferred
created: 2026-10-15T13:24:33Z
updated: 2026-10-15T21:19:41Z
+++

Move the public API closer to SceneKit's model so it is simple and easy to use. Goal: a newcomer who knows SceneKit can build and render a scene with little boilerplate. This is an ongoing direction, not a single change.

- `2026-10-15T19:23:06Z`: Ongoing direction; split concrete changes into their own issues.

---

## 107: Hit testing has its own ray type and intersection code

+++
status: closed
priority: medium
kind: enhancement
labels: area:scenegraph, effort:s
created: 2026-10-15T19:07:12Z
updated: 2026-10-15T19:21:21Z
closed: 2026-10-15T19:21:21Z
+++

HitTest.swift has SceneGraph.Ray and private Möller–Trumbore, slab and box-entry tests. GeometryLite3D has Ray3D with intersect(triangle:) and intersect(box:), but they cannot replace ours until GeometryLite3D #33 (nil when the ray starts inside the box), #34 (NaN for axis-parallel rays on a face plane) and #35 (fixed epsilon misses small triangles) are fixed. SceneGraph.Ray(viewPoint:viewSize:cameraMatrix:projectionMatrix:) is public and works out reversed depth by itself; Ray3D needs a reversedDepth flag or a ViewProjection. Split out of #97.

- `2026-10-15T19:21:21Z`: Done with GeometryLite3D 0.2.3.

---

## 108: PBR meshes ignore node opacity

+++
status: closed
priority: medium
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-15T19:51:39Z
updated: 2026-10-15T20:18:13Z
closed: 2026-10-15T20:18:13Z
+++

Node.opacity (#76) fades Blinn-Phong and ShaderMaterial meshes, but PBRSceneMaterial has appliesNodeOpacity false, so PBR meshes stay opaque during fades. PBRMaterial is a class with a resource buffer built once, and PBRModel draws blended materials in different passes, so applying opacity means a per-node material copy with a scaled baseColorFactor alpha and alphaMode blend, and a model rebuild when an entry crosses opacity 1. A per-instance opacity input in MetalSprocketsPBR would avoid both.

- `2026-10-15T20:12:56Z`: Related: #110 (fade demo should note PBR is excluded until this lands).
- `2026-10-15T20:18:13Z`: PBRSceneMaterial applies node opacity: fading entries are built with a blended copy (alpha scaled) and per-frame opacity goes through PBRRenderer.materialOverrides, so the model only rebuilds when an entry starts or stops fading. Node.opacity now bumps the transform revision instead of structure. Masked materials lose their cutoff while fading.

---

## 109: Scene graph lights and shadow maps come from MetalSprocketsAddOns

+++
status: closed
priority: medium
kind: task
labels: area:renderer, effort:m
created: 2026-10-15T20:07:48Z
updated: 2026-10-15T20:55:19Z
closed: 2026-10-15T20:55:19Z
+++

MSSG's core types depend on MetalSprocketsAddOns: Light (and its type enum) is the C struct from MetalSprocketsAddOnsShaders/Lighting.h, used by Node.Content.light, SceneGraphRenderer, Shadows, BlinnPhong and the glTF/Model I/O loaders. Shadows use AddOns' ShadowMap and ShadowContext (requiredColorUsage/requiredDepthUsage), and ShadowCasterDepthPass mirrors ShadowMapDepthPass. Nine source files import MetalSprocketsAddOns. Since #100, Blinn-Phong is in-repo, so these are the main remaining ties. Users must import MetalSprocketsAddOnsShaders just to make a light (the physics demo needed it). Want: MSSG-owned Light (a Swift type) and shadow map types, and drop the AddOns dependency where it is only used for these.

- `2026-10-15T20:10:26Z`: Audit: Light/its type enum and ShadowMap/ShadowContext/ShadowMapDepthPass are the only AddOns symbols MSSG uses. No MSSG shader includes AddOns headers, and no other dependency (PBR, glTF, SwiftMesh...) depends on AddOns. So after this: remove the AddOns package and both products from Package.swift, its imports from 9 source files and ~25 test files (mostly only for Light), and from the demos (they use only Light and ShadowContext).
- `2026-10-15T20:55:19Z`: MSSG no longer depends on MetalSprocketsAddOns. Added a Swift Light (same initializers and cases) and an internal SceneGraphShadowMap (the parts of AddOns' ShadowMap MSSG used, reversed depth only). ShadowContext.requiredColorUsage/requiredDepthUsage moved to SceneGraphShadows. Removed AddOns from both manifests, every import (45 files) and all Package.resolved files. Package tests, demo tests and goldens (including shadows) pass unchanged.

---

## 110: SceneKit Features demo does not show node opacity or fade actions

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:s
created: 2026-10-15T20:12:17Z
updated: 2026-10-15T20:31:01Z
closed: 2026-10-15T20:31:01Z
+++

Node.opacity and the fade actions (#76) have no demo. Add them to SceneKitFeaturesDemo: for example a "Fade" action that runs fadeOut then fadeIn on a shape, and an opacity slider on a parent node to show that children inherit it. Use Blinn-Phong or ShaderMaterial shapes; PBR ignores node opacity (#108).

- `2026-10-15T20:31:01Z`: SceneKitFeaturesDemo: shapes now sit under a "Shapes" group with a Shapes Opacity slider (inherited by every shape, including the ShaderMaterial capsule), and a Fade action runs fadeOut/fadeIn on the text. Test covers inheritance and the fade.

---

## 111: SceneKit Features demo does not show Blinn-Phong emission, normal maps or cull mode

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:s
created: 2026-10-15T20:12:17Z
updated: 2026-10-15T20:36:11Z
closed: 2026-10-15T20:36:11Z
+++

BlinnPhongSceneMaterial.emission, normalMap and cullMode (#83) have no demo. Add them to SceneKitFeaturesDemo: a glowing (emissive) shape, a shape with a procedural normal map (bumps or tiles, so no asset is needed), and a toggle that sets a shape's cullMode to .back or .front so the hidden side is visible. A normal map with a clear up direction would also check the +Y green convention, which no test covers.

- `2026-10-15T20:36:11Z`: SceneKitFeaturesDemo now has an emissive sphere, a box with a generated bump normal map (+Y up), and a sphere whose cull mode a Cull Mode choice sets. Tests check the materials, the choice, and that the generated map's green channel points up on the top of each bump. Goldens scenekit-features and scenekit-features-shadows re-recorded (only the three new objects differ). Not checked: whether the shader's +Y handling makes the bumps' upper sides brighter on screen; the goldens are too small to tell.

---

## 112: SceneKit Features demo has no orthographic camera

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:xs
created: 2026-10-15T20:12:17Z
updated: 2026-10-15T20:29:38Z
closed: 2026-10-15T20:29:38Z
+++

Orthographic cameras (#87) have no demo. Add a perspective/orthographic toggle to SceneKitFeaturesDemo that swaps the camera node's projection to OrthographicProjection (halfHeight sized to frame the scene). Check that SceneView's camera control and tap hit testing still work with it.

- `2026-10-15T20:29:38Z`: Added an Orthographic toggle to SceneKitFeaturesDemo that swaps the camera node's projection (halfHeight 4.5). Test: projection swaps both ways and a tap ray built like SceneView's hits the sphere. Not checked by hand: SceneView's camera control in orthographic mode (dolly moves the camera but does not zoom, since orthographic size does not depend on distance).

---

## 113: SceneKit Features demo does not use the node transform helpers

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:s
created: 2026-10-15T20:12:17Z
updated: 2026-10-15T23:48:31Z
closed: 2026-10-15T23:48:31Z
+++

eulerAngles, worldPosition/worldOrientation setters, convertPosition/convertVector/convertTransform and look(at:) (#79) have no demo. Use them in SceneKitFeaturesDemo where they fit, for example a "Look at Ball" action that calls look(at:) once on a node (beside the existing lookAt constraint), and yaw/pitch/roll sliders bound to eulerAngles on one shape.

---

## 114: PBR materials have no render state (blend mode, depth, color mask, fill mode)

+++
status: closed
priority: low
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-15T20:21:37Z
updated: 2026-10-16T12:02:30Z
closed: 2026-10-16T12:02:30Z
+++

MaterialRenderState (#84) works for Blinn-Phong and ShaderMaterial. PBRSceneMaterial has none: PBRRenderer sets its own depth/stencil, blending and fill state inside MetalSprocketsPBR with no per-material hook (only alphaMode and doubleSided). Needs MetalSprocketsPBR to accept per-material blend mode, depth read/write, color write mask and fill mode (or a pipeline/encoder hook), then PBRSceneMaterial.renderState wired through.

- `2026-10-15T23:38:02Z`: Checked: PBRMaterialRenderer.makeElement builds one PBRRenderer for all entries; PBRRenderer (MetalSprocketsPBR) sets its own depth/blend/fill state inside, so wrapping it with materialRenderState from outside would be overridden. Punting: needs a MetalSprocketsPBR change first. Unblocker: OK to add per-material render state to MetalSprocketsPBR (e.g. PBRMaterial.renderState with blend mode, depth read/write, color write mask, fill mode, applied per batch in PBRRenderer) and push it? Then PBRSceneMaterial wires it through.
- `2026-10-16T01:59:20Z`: Blocked on MetalSprocketsPBR#15 (per-material render state).
- `2026-10-16T02:32:53Z`: Unblocked: upstream fix landed (dependencies updated).
- `2026-10-16T12:02:30Z`: PBRSceneMaterial.renderState exposes MetalSprocketsPBR's PBRRenderState: blend mode (opaque, alpha, premultiplied, additive), depth test and write, color write mask, and fill mode. It is stored on the shared PBRMaterial. Faded copies keep it. It is PBRRenderState, not MaterialRenderState: PBR has no subtract, multiply or screen blending. Test pbrRenderStateIsApplied did not compile before the change.

---

## 115: Keynote demo is missing slides for several features

+++
status: closed
priority: low
kind: task
labels: area:demo, effort:m
created: 2026-10-15T20:27:29Z
updated: 2026-10-16T01:55:15Z
closed: 2026-10-16T01:55:15Z
+++

The keynote demo (#98, KeynoteDemo.swift) has slides for the scene graph, shapes, materials, lights, actions, constraints, opacity/fades and blend modes. Features #98 listed with no slide yet: shadows, fog and environment, Transaction (used only for the camera flights), animation blending, morphing and skinning, glTF and Model I/O import, hit testing, SceneView, and physics. Lights are range-limited per slide; scene-wide settings (fog, shadows, environment) need a way to switch on per slide.

- `2026-10-16T00:03:20Z`: Added slides: Shadows, Fog, Implicit Animation (Transaction), Animation Blending, glTF & Model I/O (animated fox + pedestal), Hit Testing (click shapes to hop them), Physics (restacks on arrival), SceneView. Shadows/fog switch on per slide. Still missing: morphing and skinning.

---

## 116: Demos are listed twice: DemoCatalog.demos and SceneGraphDemos.all

+++
status: closed
priority: medium
kind: task
labels: area:demo, effort:s
created: 2026-10-15T21:07:57Z
updated: 2026-10-15T22:09:35Z
closed: 2026-10-15T22:09:35Z
+++

Each demo must be added in two places: DemoCatalog.demos (used by the CLI, DemoSnapshot and tests) and SceneGraphDemos.all in DemoKitDemos.swift (the app's picker), which also needs a hand-written DemoView wrapper type per demo. The keynote demo (#98) was added only to DemoCatalog and did not appear in the app. everyCatalogDemoIsInTheApp now catches a mismatch, but the duplication remains. Want one list: for example a single generic DemoView wrapper parameterised by catalog id, if DemoKit can take instances or a closure instead of one type per demo.

---

## 117: Candy demo gummies don't look subsurface-scattered

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:demo
created: 2026-10-15T21:15:13Z
updated: 2026-10-23T13:22:41Z
closed: 2026-10-15T21:28:05Z
+++

The gummies in CandyDemo read as tinted plastic, not soft translucent candy. Light does not seem to bleed through thin edges or glow deeper in thick parts.

Current gummy material (CandyDemo.swift, gummy()): diffuse transmission 0.6, KHR_materials_volume with constant thicknessFactor 1 (no thickness texture), attenuation, volumeScatter with multiscatterColorFactor, sheen, clearcoat. No transmissionFactor.

Notes from MetalSprocketsGLTF / MetalSprocketsPBR:
- PBR.metal scales diffuse transmission color by attenuation using thicknessFactor × the thickness texture's green channel. The gummy has no thickness texture, so absorption is the same everywhere.
- KHRMaterialsVolumeScatter is only an approximation: there is no scattering pass. The multiscatter color tints diffuse transmission and halves it. multiscatterColorTexture and scatterAnisotropy are ignored.
- The GLTFViewer ShowcaseScene glass sample uses KHR_materials_transmission + ior + volume. The gummy uses none of that.

Expected: gummies look soft and translucent, with brighter, more saturated thin edges when backlit.

- `2026-10-15T21:28:05Z`: Gummies now use partial specular transmission (0.35, IOR 1.4), more diffuse transmission (0.9), lower roughness (0.4), shorter attenuation distance (0.5) and a stronger back light. Thickness still constant: no thickness texture, and view-dependent thinness at silhouettes is not something a texture can express. No test: visual tuning of a demo with no golden image; checked with scenegraph-demos --render candy.

---

## 118: Curved SceneGraph.Shape primitives render with faceted normals

+++
status: closed
priority: medium
kind: bug
labels: area:renderer
created: 2026-10-15T21:15:56Z
updated: 2026-10-23T13:22:41Z
closed: 2026-10-15T21:18:26Z
+++

Tori, capsules, spheres, cylinders and cones made from SceneGraph.Shape look faceted in the demos (e.g. SceneKitFeaturesDemo, KeynoteDemo, ShadowsDemo).

Shape.mesh() (Sources/MetalSprocketsSceneGraph/Shape.swift) calls the SwiftMesh generators without an attributes argument. SwiftMesh's default is MeshAttributes.default = [.flatNormals, .textureCoordinates], so every curved shape gets per-face normals.

CandyDemo avoids this by building its meshes directly with [.smoothNormals, .textureCoordinates].

The shapes also use SwiftMesh's default segment counts (torus 32x16, capsule 8 latitude segments), so silhouettes can still look polygonal.

Expected: curved shapes shade smoothly; box and plane stay flat.

---

## 119: No 2D text rendering

+++
status: open
priority: medium
kind: feature
labels: deferred, effort:m, area:text
created: 2026-10-15T21:21:02Z
updated: 2026-10-20T02:26:42Z
+++

SceneGraph can only show text as extruded 3D meshes (Shape.text, SwiftMesh extrusion). There is no flat, resolution-independent 2D text for labels, HUDs or slide copy.

MetalSprocketsAddOns has a Slug text renderer (Sources/MetalSprocketsAddOns/Slug: SlugFontAtlas, SlugTextMeshBuilder, SlugTextRenderPipeline) that renders glyph outlines on the GPU.

Want: 2D text in the scene graph using Slug from MetalSprocketsAddOns.

---

## 120: Keynote Materials slide: horizontal banding on spheres while animating

+++
status: closed
priority: medium
kind: bug
labels: area:renderer
created: 2026-10-15T21:22:03Z
updated: 2026-10-23T13:22:41Z
closed: 2026-10-16T01:58:26Z
+++

In KeynoteDemo, on the Materials slide during animation, the top row of red spheres shows horizontal stripes across their upper half. The stripes stop at a hard line near each sphere's equator. The bottom row of gold spheres looks fine.

Screenshot: /Users/schwa/Library/Application Support/CleanShot/media/media_uuSjrobEUn/Screenshot 2026-10-15 at 17.21.37@2x.png

Repro:
1. Run the demo app, open the Keynote demo.
2. Let it advance to the Materials slide.

Expected: smooth shading on all spheres.
Actual: striped, torn-looking upper hemispheres on the red spheres.

Unknown whether it is tied to the slide transition, the sphere mesh, or the material on that row.

- `2026-10-16T00:03:20Z`: Fixed in working copy: transparent (faded) Blinn-Phong meshes with cullMode .none blended back and front faces in index order, so back faces landed on top in bands. BlinnPhongBatchesElement now draws such meshes in two passes, back faces then front faces. Reproduced and verified with scenegraph-demos --render keynote --slide 3 at slide opacity 0.5.
- `2026-10-16T01:58:26Z`: Fixed

---

## 121: glTF loader ignores image-based light, transmission and variant names

+++
status: closed
priority: low
kind: enhancement
labels: area:assets, effort:m
created: 2026-10-15T22:00:46Z
updated: 2026-10-15T23:39:37Z
closed: 2026-10-15T23:39:37Z
+++

GLTFAsset.makeSceneGraph(device:) drops parts of the asset that MetalSprocketsGLTF already exposes:

- EXT_lights_image_based: GLTFAsset.environment() is public, but sceneGraph.environment is never set from it.
- Transmission: GLTFAsset.hasTransmission is true for glass assets, but the scene graph has no pass that renders the scene behind transmissive surfaces, so glass shows only the environment map.
- KHR_materials_variants: variantNames is not copied into GLTFSceneGraph, and a loaded scene graph cannot switch variants (needs MetalSprocketsGLTF to expose per-variant materials).

- `2026-10-15T23:39:37Z`: Done: the scene's EXT_lights_image_based light sets sceneGraph.environment.map; variantNames is on GLTFSceneGraph. Split off: transmission scene pass and runtime variant switching (new issues).

---

## 122: glTF material animation channels do not blend in AnimationMixer

+++
status: closed
priority: low
kind: enhancement
labels: area:animation, area:assets, effort:s
created: 2026-10-15T23:35:09Z
updated: 2026-10-16T06:42:29Z
closed: 2026-10-16T06:42:29Z
+++

KHR_animation_pointer material channels from GLTFSceneGraph use a Property whose get returns an empty array, because a material has no generic way to read back the animated value. AnimationMixer uses get as the rest value, so material channels cannot be weighted, cross-faded or added on top of other clips. They only work when a clip is applied directly (AnimationClip.apply / AnimationPlayer).

Expected: material channels blend like transform and light channels.
Actual: with a mixer, material channels are ignored when blending against the rest value.

- `2026-10-15T23:38:02Z`: Punting: MaterialProperty.factor in MetalSprocketsGLTF is set-only, so the scene graph cannot read a factor back for the mixer's rest value. Unblocker: OK to give .factor a getter (or key path) in MetalSprocketsGLTF and push?
- `2026-10-16T02:01:05Z`: Blocked on MetalSprocketsGLTF issue (material properties need a getter).
- `2026-10-16T02:01:08Z`: Upstream: MetalSprocketsGLTF#177.
- `2026-10-16T02:32:53Z`: Unblocked: upstream fix landed (dependencies updated).
- `2026-10-16T06:42:30Z`: gltfMaterial's get reads the animated state (MetalSprocketsGLTF AnimatedState.value(of:)), so the mixer has a rest value. Test: an additive layer at weight 0.5 fails before the fix and passes after.

---

## 123: Transmissive PBR materials do not show the scene behind them

+++
status: closed
priority: low
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-15T23:39:36Z
updated: 2026-10-16T02:06:09Z
closed: 2026-10-16T02:06:09Z
+++

PBR materials with transmissionFactor > 0 (glTF KHR_materials_transmission) refract only the environment map in the scene graph. MetalSprocketsPBR can sample a transmission scene (PBRRenderer.transmissionTarget, frame.hasTransmissionScene), but PBRMaterialRenderer never renders the opaque scene into one, so objects behind glass are not visible through it.

Expected: glass shows the refracted scene behind it.
Actual: glass shows only the environment map.

- `2026-10-16T02:06:10Z`: PBRMaterialRenderer adds a transmission pre-pass (new SceneGraphPrePassRenderer hook). Follow-ups: #129, #130.

---

## 124: Cannot switch glTF material variants on a loaded scene graph

+++
status: closed
priority: low
kind: enhancement
labels: area:assets, effort:s
created: 2026-10-15T23:39:37Z
updated: 2026-10-16T10:42:22Z
closed: 2026-10-16T10:42:22Z
+++

GLTFSceneGraph keeps variantNames, but the scene graph always shows the variant the GLTFAsset was loaded with. Switching means loading the asset again and rebuilding the graph, which loses node state and animation players.

Blocked on MetalSprocketsGLTF#176 (per-variant materials are not public).

- `2026-10-16T02:34:31Z`: Unblocked: upstream fix is in the resolved dependencies.
- `2026-10-16T10:42:22Z`: Added GLTFSceneGraph.selectVariant(_:): swaps each mesh node's materials using GLTFAsset.material(for:variant:), keeping node state, mesh and shadow flags. Test gltfMaterialVariantsSwitchInPlace did not compile before the change.

---

## 125: Constraints: no slider constraint and no isIncremental

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, effort:m
created: 2026-10-15T23:42:34Z
updated: 2026-10-16T00:05:43Z
closed: 2026-10-16T00:05:43Z
+++

SceneGraph.Constraint now has influenceFactor, isEnabled and an acceleration kind (#91), but still lacks:

- A slider constraint (SCNSliderConstraint): keeps a node from moving into physics bodies in a category, sliding along them. Needs a sphere-cast or overlap query from MetalSprocketsSceneGraphPhysics; the core module cannot see physics.
- isIncremental (SCNConstraint.isIncremental). Influence blends from the node's transform at the time the constraint runs, which carries the previous frame's result unless animation resets it. There is no switch for blending from the unconstrained transform instead.

- `2026-10-16T00:05:43Z`: Slider done: SceneGraphPhysicsWorld.sliderConstraint(radius:categoryBitMask:) (sphere sweep, stops and slides; uses node categoryBitMask). isIncremental left out on purpose: constraints write trs directly, so there is no unconstrained transform to blend from; supporting it would mean storing each node's pre-constraint transform every frame. Reopen if needed.

---

## 126: Keynote code panels: snippets would not compile as written

+++
status: open
priority: low
kind: bug
labels: area:demo, deferred, effort:s
created: 2026-10-16T00:06:57Z
updated: 2026-10-20T02:26:42Z
+++

The code panels in KeynoteDemo.swift show Swift that does not compile if pasted.

- Scene Graph and Shapes slides: Node(shape:material:) leaves out the required device: argument.
- Animation Blending slide: 'let controller' must be 'var' (blend and advance are mutating). 'mixer' is not defined.
- Actions slide: 'down' is not defined.

Expected: each snippet compiles, given the obvious names (materials, nodes) it refers to.

---

## 127: Keynote code panels: snippets do not match what the slide does

+++
status: open
priority: low
kind: bug
labels: area:demo, deferred, effort:s
created: 2026-10-16T00:06:57Z
updated: 2026-10-20T02:26:42Z
+++

Some code panels in KeynoteDemo.swift differ from the code that builds the slide, or show demo-only API.

- Shadows slide: 'scene.shadows = SceneGraphShadows(...)' is a DemoScene property, not library API. Library users pass shadows to SceneView(..., shadows:).
- Scene Graph slide: the orbit's parent is shown as 'sun', but the demo parents it to the slide (the sun is a sibling).
- Actions slide: leaves out the rotate that runs in a group with the hop.

---

## 128: Keynote code panels: decide on short type names

+++
status: open
priority: low
kind: task
labels: area:demo, deferred, effort:s
created: 2026-10-16T00:06:57Z
updated: 2026-10-20T02:26:42Z
+++

Keynote code panels use Node, Action, AnimationController and AnimationPlayer. The real names are SceneGraph.Node and so on, and there are no typealiases. Decide: keep short names for readability, use full names, or add public typealiases.

---

## 129: Glass does not show non-PBR objects behind it

+++
status: closed
priority: low
kind: enhancement
labels: area:renderer, effort:m
created: 2026-10-16T02:06:06Z
updated: 2026-10-16T12:22:47Z
closed: 2026-10-16T12:22:47Z
+++

The transmission pre-pass (#123) draws only PBR entries. Blinn-Phong, ShaderMaterial and particle content behind transmissive PBR glass is missing from the refracted scene.

Expected: everything opaque behind glass shows through it.
Actual: only PBR meshes and the environment show through.

Needs the other material renderers to draw into the transmission target with linear (not tone-mapped) output.

- `2026-10-16T12:15:59Z`: Plan: (1) MetalSprocketsPBR#18 lets PBRTransmissionPass draw extra content. (2) The pre-pass hook gets the other renderers' opaque elements, in the main pass's batches. (3) PBRMaterialRenderer passes those elements to the transmission pass. Blinn-Phong already writes linear output. Particles are left out at first because they are transparent. Blocked on MetalSprocketsPBR#18.
- `2026-10-16T12:21:02Z`: Unblocked: MetalSprocketsPBR#18 landed.
- `2026-10-16T12:22:47Z`: PBRMaterialRenderer's transmission pre-pass now also draws the other renderers' opaque batches (new otherOpaqueContent argument on SceneGraphPrePassRenderer, using MetalSprocketsPBR#18's additionalContent). Blinn-Phong shows through glass. ShaderMaterial does too if its shaders output linear color. Particles are still left out (transparent). Test glassShowsBlinnPhongBehindIt fails before the change.

---

## 130: Transmission pre-pass ignores fades and light category masks

+++
status: closed
priority: low
kind: bug
labels: area:renderer, effort:s
created: 2026-10-16T02:06:06Z
updated: 2026-10-16T02:42:08Z
closed: 2026-10-16T02:42:08Z
+++

PBRMaterialRenderer's transmission pre-pass (#123) draws all PBR entries as one model with all lights. In the scene seen through glass, fading nodes are drawn fully opaque, and lights light nodes their category masks exclude.

Expected: the scene behind glass matches the main pass.

Blocked on MetalSprocketsPBR#16 (PBRTransmissionPass from existing renderers).

- `2026-10-16T02:32:54Z`: Unblocked: upstream fix landed (dependencies updated).
- `2026-10-16T02:42:08Z`: The transmission pre-pass now uses the main pass's batches (renderBatches, now public): per-batch lights and material overrides through PBRTransmissionPass(renderers:). The light-mask test fails before the fix. Fades already looked right before the change (5% red behind glass was dim either way), so there is no fade test.

---

## 131: Add SceneKit-style debug statistics overlay

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:renderer, deferred
created: 2026-10-16T02:37:54Z
updated: 2026-10-20T02:27:43Z
+++

Add an optional debug info overlay to the scene view, like SceneKit's showsStatistics.

Reference: https://p.kagi.com/proxy/FG7aA.png?c=paVMepdr69omyIsuiCcXRC3n_YTvrIv4uKvP_RH_p1sKrZU_OYHNk4M0KKz7GNsN

Collapsed bar shows:
- Backend and FPS (e.g. 'Metal 60fps')
- Draw call count
- Triangle/vertex count
- Frame-time sparkline

Expanded panel shows:
- Donut chart of frame time (e.g. 0.2 s)
- Breakdown by phase with color legend: e.g. update/animation, scene graph traversal, culling, encoding/rendering, GPU time, 2D/UI overlay

Done when: a view modifier or flag turns the overlay on, and it shows live per-frame stats.

---

## 132: No built-in debug visualization modes for scene graph rendering

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:renderer, deferred
created: 2026-10-17T12:19:22Z
updated: 2026-10-20T02:27:43Z
+++

SceneGraph has no standard way to view a scene in debug modes such as normals, UVs, tangents, world position or material channels. The only option is ShaderMaterial.normals(), which has to be set on each node by hand.

Related debug shaders already exist in sibling packages:
- MetalSprocketsAddOns: DebugRenderPipeline / DebugShaders.metal (DebugShadersMode: normals, texture coordinates, tangents, bitangents, world and local position, IDs).
- MetalSprocketsPBR: PBRRenderer.debugView (PBRDebugView: base color, alpha, metallic, roughness, occlusion, emissive, shading and geometric normals, tangents, UVs, UV checker, front facing, transmission, clearcoat, sheen, iridescence and more). The GLTF viewer uses it.

None of these can be turned on for a whole SceneGraph or SceneView, and Blinn-Phong has no equivalent.

Requested (per user): make debug shaders a default part of this project, so any scene can be shown in a debug mode.

---

## 133: MeshEntry values are copied many times per frame

+++
status: closed
priority: medium
kind: bug
created: 2026-10-17T12:35:33Z
updated: 2026-10-17T12:51:38Z
closed: 2026-10-17T12:51:38Z
+++

SceneGraph.MeshEntry is a large struct: a Node reference, a world transform, a MetalMesh (a struct holding arrays and dictionaries of Metal buffers), a material existential and a few flags. Each frame the render path copies every entry several times: meshEntries(), the category-mask filter, applyLevelsOfDetail, renderBatches, partitionMeshEntries, and the renderer's own intermediate arrays (for example BlinnPhongMaterialRenderer's item tuples and InstanceBatch). Every copy retains and releases each reference inside the entry.

Measured on the keynote's Performance slide (1,600 crates, Release build, after the Blinn-Phong sorting and batch-key fixes): about 4.1 ms per frame, of which roughly 15% (458 of 2,654 main-thread samples) is 'outlined init with copy' or 'outlined destroy' of SceneGraph.MeshEntry and MetalMesh.

---

## 134: Renderers rebuild draw batches every frame even when only transforms change

+++
status: closed
priority: medium
kind: feature
created: 2026-10-17T12:35:33Z
updated: 2026-10-17T12:51:38Z
closed: 2026-10-17T12:51:38Z
+++

BlinnPhongMaterialRenderer.makeElement regroups all entries by pipeline key, builds an instance-batch key per entry and hashes it, every frame. When a scene's structure (meshes, materials, visibility, opacity) is unchanged and only node transforms move, the grouping comes out the same each frame; only the model matrices differ.

On the keynote's Performance slide (1,600 animated crates, 3 batches) this grouping work is repeated 1,600 times per frame. The scene graph has one revision counter, so a renderer cannot tell a transform-only change from a structural one.

---

## 135: No explicit instancing API; drawing many copies always goes through per-node implicit instancing

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:scenegraph, deferred
created: 2026-10-17T12:50:07Z
updated: 2026-10-20T02:27:43Z
+++

The only way to draw many copies of a mesh is one Node per copy. Renderers then discover the repeats each frame (implicit instancing): flatten the tree into one MeshEntry per node, cull each entry, and group entries back into instance batches. Even with the cached batching from #134, the per-node cost remains: node traversal and world transforms, one MeshEntry and one frustum test per copy, and gathering one model matrix per copy every frame.

On the keynote's Performance slide this scales with crate count: 1,600 crates took about 1.6 ms per frame and 484 crates about 0.9 ms (Release, offscreen benchmark), almost all on the CPU, for what the GPU draws as 3 instanced calls.

There is no way to give the scene graph a single node holding a mesh, a material and an array of instance transforms (and optionally per-instance colors), like SCNGeometry with a custom instance buffer or EXT_mesh_gpu_instancing, so that the cost does not grow with one node per copy. glTF EXT_mesh_gpu_instancing is currently expanded into child nodes for the same reason.

---

## 136: Ambient occlusion is part of PostProcessing and darkens the final lit color

+++
status: open
priority: medium
kind: bug
labels: effort:m, area:renderer, deferred
created: 2026-10-17T13:09:48Z
updated: 2026-10-20T02:27:43Z
+++

Screen-space ambient occlusion is configured as SceneGraph.PostProcessing.ambientOcclusion, next to exposure, contrast, saturation and vignette, and runs as a post pass (ambient_occlusion in PostProcessing.metal) that multiplies the final rendered color.

Problems:
- It is grouped with color grading, although it is a lighting effect.
- It darkens all light at a pixel: direct lighting, specular highlights and emission are occluded, not just ambient and indirect light. A crease lit by a spotlight still goes dark, and emissive or unlit content (for example the keynote's code panels and titles) is darkened.
- Material renderers never see the occlusion: Blinn-Phong ambient and PBR image-based lighting cannot apply it to their ambient terms.

Expected: ambient occlusion reduces only ambient and indirect lighting, and is configured as a lighting setting, separate from post-processing color adjustments.

---

## 137: Evaluate MetalSprocketsParticles as replacement for particle system

+++
status: closed
priority: medium
kind: task
labels: has-subtasks, effort:xl, area:renderer
depends: 138, 139, 140, 141, 142, 143
created: 2026-10-19T12:06:26Z
updated: 2026-10-21T17:34:49Z
closed: 2026-10-21T17:34:49Z
+++

Evaluate MetalSprocketsParticles (https://github.com/schwa/MetalSprocketsParticles, local: /Users/schwa/Projects/Scratch/MetalSprocketsParticles) as a replacement for the current particle system. If adopted, it becomes our particle system and the in-repo MetalSprocketsParticles target is deleted.

## Prelim findings (code read only, not built or benchmarked)

No show stoppers found.

Current system: small CPU sim (MetalSprocketsParticles target, ParticleRenderer.swift, Particles.metal). Sorts on CPU and builds a new MTLBuffer every frame. Used by KeynoteDemo, ParticleTests, ParticleSystemTests.

Candidate: about 8.6k lines, GPU sim and render, built as MetalSprockets elements (runtime.simulate / runtime.render). Render-pass agnostic.

### Integration work
- Delete our MetalSprocketsParticles target (same product and type names).
- Model split: ParticleSystem (Codable description) vs ParticleSystemRuntime (GPU state). Node.particleSystems must hold runtimes or a wrapper. Rethink clone() sharing.
- Move per-frame simulate out of SceneView.advanceParticles into the renderer frame setup. Pass node world transforms via simulate(transforms:).
- Hidden nodes: map to the per-emitter isEmitting.
- Port KeynoteDemo effects (fire, fountain, firefly trail) and the tests.
- Check extra dependencies: SwiftMesh, MetalCompilerPlugin.

### Upstream changes needed
- Reversed depth: they use .less; we use .greater. Need an option or a caller-supplied depth compare.
- Soft particles need a scene depth texture from our renderer (optional; depends on MetalSprockets #530).
- cameraEye/cameraTarget on ParticleSystem are irrelevant to us (cosmetic).

- `2026-10-20T02:25:07Z`: Split into subtasks: #138 → #139 → #140 → #141 → #142, #143
- `2026-10-21T17:34:49Z`: Adopted. All subtasks done.

---

## 138: Upstream: configurable depth compare in MetalSprocketsParticles

+++
status: closed
priority: medium
kind: task
labels: effort:m, subtask, area:renderer
created: 2026-10-20T02:25:07Z
updated: 2026-10-21T16:47:49Z
closed: 2026-10-21T16:47:49Z
+++

MetalSprocketsParticles uses .less depth compare; we use reversed-Z (.greater). Add an option or caller-supplied depth compare upstream. Done when particles depth-test correctly against a .greater depth buffer. Part of #137.

- `2026-10-21T16:47:49Z`: Already done upstream: ParticleSystemRuntime.reverseZ (#144) gives .greater depth compare. Package tagged 0.0.1 on GitHub.

---

## 139: Adopt MetalSprocketsParticles package and delete in-repo particle target

+++
status: closed
priority: medium
kind: task
labels: effort:m, subtask, area:renderer
depends: 138
created: 2026-10-20T02:25:07Z
updated: 2026-10-21T17:09:58Z
closed: 2026-10-21T17:09:58Z
+++

Add the MetalSprocketsParticles package dependency (check SwiftMesh and MetalCompilerPlugin deps). Delete the in-repo MetalSprocketsParticles target, ParticleRenderer.swift, and Particles.metal. Done when the package builds. Part of #137.

- `2026-10-21T17:09:58Z`: Done: MetalSprocketsParticles (GitHub, branch main) adopted; SceneParticleSystem wraps description + runtime; simulate/render in SceneGraphElement.

---

## 140: Integrate ParticleSystem/ParticleSystemRuntime into Node model

+++
status: closed
priority: medium
kind: task
labels: effort:m, subtask, area:renderer
depends: 139
created: 2026-10-20T02:25:07Z
updated: 2026-10-21T17:09:59Z
closed: 2026-10-21T17:09:59Z
+++

Node.particleSystems holds runtimes or a wrapper. Split Codable description from GPU runtime state. Rethink clone() sharing. Map hidden nodes to per-emitter isEmitting. Part of #137.

- `2026-10-21T17:09:59Z`: Done: MetalSprocketsParticles (GitHub, branch main) adopted; SceneParticleSystem wraps description + runtime; simulate/render in SceneGraphElement.

---

## 141: Move particle simulation into renderer frame setup

+++
status: closed
priority: medium
kind: task
labels: effort:m, subtask, area:renderer
depends: 140
created: 2026-10-20T02:25:07Z
updated: 2026-10-21T17:09:59Z
closed: 2026-10-21T17:09:59Z
+++

Move per-frame simulate out of SceneView.advanceParticles into renderer frame setup. Pass node world transforms via simulate(transforms:). Done when particles simulate and render in the scene. Part of #137.

- `2026-10-21T17:09:59Z`: Done: MetalSprocketsParticles (GitHub, branch main) adopted; SceneParticleSystem wraps description + runtime; simulate/render in SceneGraphElement.

---

## 142: Port KeynoteDemo particle effects to new system

+++
status: closed
priority: medium
kind: task
labels: effort:m, subtask, area:renderer
depends: 141
created: 2026-10-20T02:25:07Z
updated: 2026-10-21T17:34:48Z
closed: 2026-10-21T17:34:48Z
+++

Port fire, fountain, and firefly trail effects in KeynoteDemo. Done when they look and behave as before. Part of #137.

- `2026-10-21T17:34:48Z`: Fire, fountain and firefly trail ported; keynote-particles golden added.

---

## 143: Port particle tests to new system

+++
status: closed
priority: medium
kind: task
labels: effort:m, subtask, area:renderer
depends: 141
created: 2026-10-20T02:25:07Z
updated: 2026-10-21T17:34:48Z
closed: 2026-10-21T17:34:48Z
+++

Port ParticleTests and ParticleSystemTests to the new particle system. Done when tests pass. Part of #137.

- `2026-10-21T17:34:48Z`: ParticleTests ported (draw/depth, follows node, hidden stops emitting); old ParticleSystemTests removed with the target.

---

## 144: Particle effect colliders ignore the node transform

+++
status: closed
priority: low
kind: bug
created: 2026-10-21T17:34:49Z
updated: 2026-10-21T17:53:15Z
closed: 2026-10-21T17:53:15Z
+++

SceneParticleSystem passes system.colliders(at:) as is, so an effect's colliders stay in world space while its emitters follow the node. Transform them by the node's world transform. Follow-up to #137.

- `2026-10-21T17:53:15Z`: Collider.transformed(by:) applies the node's world transform each step.

---

## 145: Soft particles: pass scene depth to particle render

+++
status: closed
priority: low
kind: feature
created: 2026-10-21T17:34:49Z
updated: 2026-10-21T17:53:15Z
closed: 2026-10-21T17:53:15Z
+++

SceneGraphElement calls runtime.render(projection:view:) without sceneDepth, so emitters with softness do not fade into geometry. Needs a scene depth texture that is not the pass's depth attachment. Follow-up to #137.

- `2026-10-21T17:53:15Z`: Scene depth copied to r32Float after the scene pass; soft particles draw in a second pass with render(sceneDepth:).

---

## 146: Upstream MetalSprocketsParticles: sprite depth state and multi-step frames

+++
status: closed
priority: low
kind: task
created: 2026-10-21T17:34:49Z
updated: 2026-10-21T17:53:15Z
closed: 2026-10-21T17:53:15Z
+++

1. Sprite draws set no depth state and inherit the enclosing pass's (ours writes depth), which cut dark squares into additive effects. We override with .depthCompare(function: .greater, writes: false); upstream should set it itself. 2. More than ~4 simulate calls in one frame gave nondeterministic results (alive-count readback ring). We step once per frame; upstream should support or document it. Follow-up to #137.

- `2026-10-21T17:53:15Z`: Workarounds in place here; upstream tracked as MetalSprocketsParticles #236 and #237.

---

## 147: Pin MetalSprocketsParticles by version

+++
status: closed
priority: low
kind: task
created: 2026-10-21T17:34:49Z
updated: 2026-10-23T13:00:15Z
closed: 2026-10-23T13:00:15Z
+++

Package.swift and the demo package use branch main because the 0.0.1 tag depends on MetalSprockets main (#530). Switch both to .upToNextMinor once MetalSprockets is released with #530 and Particles is re-tagged.

---

## 148: Dice demo: bevel die edges

+++
status: open
priority: low
kind: enhancement
labels: deferred, area:demo, effort:s
created: 2026-10-22T01:05:11Z
updated: 2026-10-23T13:22:39Z
+++

DiceGeometry builds dice with sharp edges. Real dice (and the old Dice by PCalc models) have rounded edges, which catch highlights and read as solid objects, especially on the metal and glass styles. Bevel or chamfer each edge in DiceGeometry, keeping per-face texture coordinates and the convex hull used for physics. Done when the dice show rounded edges in the Dice demo and the numbers still sit on their faces.

---

## 149: Dice demo: use real-world face numbering

+++
status: open
priority: low
kind: enhancement
labels: deferred, area:demo, effort:xs
created: 2026-10-22T01:05:11Z
updated: 2026-10-23T13:22:39Z
+++

DiceGeometry numbers faces with a simple scheme: opposite faces add up to n + 1 (n - 1 for the D10, numbered 0 to 9), but the arrangement around each corner is arbitrary. Store-bought dice follow conventions (for example, a D6 with 1, 2, 3 meeting counterclockwise at a corner; a balanced D20). Done when each die kind matches a standard layout.

---

## 150: Rename MetalSprocketsSceneGraph to SceneSprocket

+++
status: closed
priority: medium
kind: task
created: 2026-10-22T01:29:01Z
updated: 2026-10-22T15:07:06Z
closed: 2026-10-22T15:07:06Z
+++

Rename the package and its products to SceneSprocket. Scope to decide: package name, library/module names (MetalSprocketsSceneGraph, MetalSprocketsSceneGraphPBR, ...BlinnPhong, ...ShaderMaterial, ...Physics, ...Shaders), the demo package and app, the repository, documentation, and dependents (MetalSprocketsParticles demos, others that import these modules).

- `2026-10-22T15:07:06Z`: Renamed: package SceneSprocket; modules SceneSprocket, SceneSprocketPBR, SceneSprocketBlinnPhong, SceneSprocketShaderMaterial, SceneSprocketPhysics, SceneSprocketShaders, SceneSprocketAudio; demo package SceneSprocketDemos, app SceneSprocketDemo (bundle id io.schwa.SceneSprocketDemo), CLI scenesprocket-demos. Swift type names unchanged. Left for the owner: rename the repo folder (then change package: "MetalSprocketsSceneGraph" to "SceneSprocket" in Demo/Packages/SceneSprocketDemos/Package.swift and container in .xcb.toml), the GitHub repository, and references in other repos (MetalSprocketsParticles Methodology.md, MetalSprocketsGLTF PublicMaterialPointerTests.swift, other repos' ISSUES.md).

---

## 151: Demos for every supported feature

+++
status: closed
priority: medium
kind: task
created: 2026-10-22T01:40:08Z
updated: 2026-10-22T14:05:29Z
closed: 2026-10-22T14:05:29Z
+++

Every feature should have a demo: a standalone demo, a keynote slide, or a clearly labeled part of a larger demo (Dice, Gears, Shadows, SceneKit Features). glTF loading and particles are out of scope here.

Check an item when a demo shows it. Items marked "(keynote)" are partly shown on a keynote slide today, so check whether that is enough or needs its own demo.

## Scene graph and nodes
- [ ] Node hierarchy: add, insert, remove, replace children (keynote: Scene Graph)
- [ ] Transforms: TRS and matrix local transforms, pivot
- [ ] Node space: worldTransform, worldPosition, worldOrientation, eulerAngles, convertPosition/Vector/Transform, look(at:)
- [ ] Visibility (isVisible) and node opacity (keynote: Opacity & Fades)
- [ ] Rendering order
- [ ] Category bit masks: camera, light (lightCategoryBitMask) and hit-test masks (SceneKit Features)
- [ ] Clone and flattenedClone
- [ ] Bounds: meshBounds, subtreeBounds, worldBounds
- [ ] Statistics (node, mesh, triangle, light, camera counts)
- [ ] Revision and change tracking

## Geometry
- [ ] Shapes: box, sphere, plane, cylinder, cone, capsule, torus (keynote: Shapes)
- [ ] Extruded text (keynote: Shapes)
- [ ] Custom meshes (SwiftMesh): generated dice, gears (Dice, Gears)
- [ ] Multiple materials per mesh (submeshes)
- [ ] Subdivision (subdivisionLevel)
- [ ] Levels of detail
- [ ] Instancing: identical mesh + material batched (keynote: Performance)
- [ ] Frustum culling (keynote: Performance)

## Cameras
- [ ] Perspective camera
- [ ] Orthographic camera
- [ ] Camera nodes and switching the point of view
- [ ] Camera category bit mask

## Lights
- [ ] Directional light
- [ ] Point light with range
- [ ] Spot light (inner and outer cone)
- [ ] Light color and intensity
- [ ] Light category masks (lights that affect only some nodes)
- [ ] Default lighting (SceneView autoenablesDefaultLighting)

## Shadows
- [ ] Directional, spot and point light shadows (Shadows demo)
- [ ] Intensity, color, softness (Shadows demo)
- [ ] Resolution, depth bias, slope scale
- [ ] castsShadow / receivesShadow per mesh (Shadows demo: floor)
- [ ] Shadows sampled in shader (Blinn-Phong, PBR) and screen-space shadow mask (other materials)

## Blinn-Phong materials
- [ ] Ambient, diffuse, specular, shininess
- [ ] Color and texture sources, texture tint
- [ ] Emission
- [ ] Normal map
- [ ] Opacity and diffuse texture alpha
- [ ] Cull mode (front, back, none)

## PBR materials (MetalSprocketsPBR)
- [ ] Base color, metallic, roughness (factors and textures) (keynote: Materials; Dice)
- [ ] Normal map with normal scale (Dice)
- [ ] Occlusion map and strength
- [ ] Emissive color, texture and strength (Dice: Glow)
- [ ] Alpha modes: opaque, mask (cutoff), blend
- [ ] Unlit
- [ ] Texture transforms (offset, rotation, scale, texCoord set)
- [ ] Transmission, thickness, attenuation, IOR (keynote: Glass; Dice: Ruby Glass)
- [ ] Dispersion (Dice: Rainbow Crystal)
- [ ] Specular and specular color
- [ ] Iridescence (keynote: PBR Extensions; Dice: Pearl)
- [ ] Anisotropy (Dice: Brushed Steel)
- [ ] Sheen (keynote: PBR Extensions; Dice: Velvet)
- [ ] Clearcoat, clearcoat roughness, clearcoat normal (keynote: PBR Extensions; Dice)
- [ ] Diffuse transmission (keynote: PBR Extensions; Dice: Gummy)
- [ ] Volume scatter and multiscatter color (Dice: Gummy)
- [ ] Retroreflection
- [ ] Specular-glossiness workflow
- [ ] Environment maps: studio, uniform color, equirectangular image; intensity; exposure
- [ ] Environment background with blur, and environment rotation
- [ ] Double-sided materials

## Shader materials
- [ ] Custom vertex and fragment shaders with parameters (float, vectors, matrix, texture, sampler, buffer) (keynote: Custom Shaders)
- [ ] Built-in normals and rim materials

## Render state (all material families)
- [ ] Blend modes: alpha, add, subtract, multiply, screen, replace (keynote: Blend Modes)
- [ ] Depth write and depth test on/off
- [ ] Color write mask
- [ ] Wireframe fill mode
- [ ] Transparency sorting and node opacity

## Environment and post-processing
- [ ] Background: none, color, environment
- [ ] Fog: color, start/end distance, density exponent (keynote: Fog)
- [ ] Exposure, contrast, saturation (keynote: Post-processing)
- [ ] Vignette (Shadows demo)
- [ ] Screen-space ambient occlusion (Shadows demo)

## Actions
- [ ] move by / to
- [ ] rotate by / to (axis-angle, Euler, quaternion)
- [ ] scale by / to
- [ ] fade in / out / opacity to / by (keynote: Opacity & Fades)
- [ ] wait, wait with range
- [ ] custom, run, hide, unhide, removeFromParent
- [ ] sequence, group, repeat, repeatForever (keynote: Actions)
- [ ] Timing modes: linear, ease in, ease out, ease in-out, custom
- [ ] Action keys, removal, hasAction, node actionSpeed

## Implicit animation
- [ ] Transaction.animate and withoutAnimation (keynote: Implicit Animation)

## Animation clips
- [ ] Keyframed translation, rotation, scale channels
- [ ] Morph weight channels
- [ ] Custom property channels (light color, visibility, light range, cone angles, camera field of view)
- [ ] Interpolation modes
- [ ] Animation events
- [ ] AnimationPlayer: speed, looping, repeat count, autoreverse, timing mode
- [ ] Blending: AnimationMixer, AnimationController, layers (override / additive), blend weights (keynote: Animation Blending)
- [ ] Root motion
- [ ] Animation state machine: states, transitions with fades and conditions

## Constraints
- [ ] lookAt (keynote: Constraints)
- [ ] billboard (all axes and limited axes)
- [ ] replicator (position, orientation, scale, offsets)
- [ ] avoidOccluder
- [ ] distance (minimum, maximum)
- [ ] inverseKinematics
- [ ] acceleration
- [ ] transform (custom closure)
- [ ] slider constraint (physics module)

## Deformation
- [ ] Morph targets with weights, by name (keynote: Deformation)
- [ ] Skinning: skins, joints, inverse bind matrices (keynote: Deformation; fox)

## Hit testing and queries
- [ ] Ray and segment hit tests with options (category mask, back-face culling, bounding box only, first only, maximum distance, root node) (keynote: Hit Testing)
- [ ] Hit details: position, normal, texture coordinates, barycentric, triangle
- [ ] Project and unproject points
- [ ] Nodes inside the frustum

## Physics (MetalSprocketsSceneGraphPhysics, Jolt)
- [ ] Static, dynamic, kinematic bodies (keynote: Physics; Dice)
- [ ] Shapes: box, sphere, capsule, cylinder, bounding box, convex hull, mesh (Dice: convex hull)
- [ ] Mass, friction, restitution
- [ ] Velocity, angular velocity, impulses (Dice)
- [ ] Gravity

## Audio
- [ ] Audio players on nodes, positional audio, SceneView audio

## SceneView (SwiftUI)
- [ ] allowsCameraControl, autoenablesDefaultLighting, showsStatistics (keynote: SceneView)
- [ ] Delegate callbacks (update, after actions, after constraints)
- [ ] Tap handling with hit-test category mask
- [ ] External camera binding

- `2026-10-22T14:05:29Z`: Superseded by Documentation/Features.md.

---

## 152: Feature gaps vs. SceneKit, RealityKit, three.js and others

+++
status: closed
priority: low
kind: task
created: 2026-10-22T01:42:26Z
updated: 2026-10-22T14:05:30Z
closed: 2026-10-22T14:05:30Z
+++

Features in SceneKit, RealityKit, three.js, Babylon.js, Godot and Filament that MetalSprocketsSceneGraph does not have. Compiled from what those libraries document plus Documentation/SceneKitComparison.md; not a commitment to build all of it. Glance at each item and either file its own issue, link the existing one, or strike it.

Already tracked elsewhere: HDR, tone mapping, bloom, depth of field (#45); save/load (#52); USD/USDZ loading (#31); shape options (#80); tube, pyramid, floor, Bézier extrusion (#81); ambient node, temperature, IES and area lights (#86); shadow cascades and per-light settings (#88); explicit instancing (#135).

## Rendering
- [ ] Screen-space reflections (SceneKit, Babylon, Godot)
- [ ] Planar reflections / mirror surfaces; reflective floor (SceneKit SCNFloor, three.js Reflector)
- [ ] Reflection probes / local environment probes (RealityKit, Godot, Unity-style)
- [ ] Image-based lighting from a scene capture (render the scene into a cube map)
- [ ] Skybox / procedural sky (three.js Sky, Godot, Babylon)
- [ ] Motion blur, chromatic aberration, film grain, lens flares (SceneKit, Babylon, Godot)
- [ ] Anti-aliasing options: MSAA settings, FXAA/SMAA/TAA (three.js, Babylon, Godot)
- [ ] Outlines and selection highlights (three.js OutlinePass, Babylon highlight layer, RealityKit)
- [ ] Glow / emissive bloom per object (Babylon glow layer)
- [ ] Contact shadows / ground shadow catcher; shadow-only material (SceneKit shadowOnly, RealityKit grounding shadows, three.js ShadowMaterial)
- [ ] Decals projected onto meshes (three.js DecalGeometry, Babylon, Godot)
- [ ] Order-independent transparency
- [ ] Light baking / lightmaps (three.js, Godot, Filament)
- [ ] Global illumination (Godot SDFGI/VoxelGI)
- [ ] Volumetric lighting and fog (Godot, Filament)
- [ ] Render to texture / secondary cameras into textures (SceneKit, three.js render targets)
- [ ] Multiple viewports and split screen
- [ ] Stereo / visionOS immersive rendering
- [ ] Occlusion culling (beyond frustum)
- [ ] Debug views: normals, wireframe overlay for every material, bounding boxes, light gizmos (SceneKit debugOptions, three.js helpers)

## Materials
- [ ] Shader modifiers / node-based material graph (SceneKit shader modifiers, RealityKit Shader Graph, three.js TSL, Babylon Node Material)
- [ ] Toon / cel shading and other stylized models (three.js MeshToonMaterial)
- [ ] Matcap material (three.js MeshMatcapMaterial)
- [ ] Video textures (SceneKit, RealityKit VideoMaterial, three.js VideoTexture)
- [ ] Cube-map and 3D textures in materials
- [ ] Parallax / height mapping
- [ ] Triplanar mapping
- [ ] Detail maps / texture blending (terrain splatting)
- [ ] Render state for PBR: depth write/test, color mask, wireframe (#114)

## Geometry
- [ ] Lines and line widths, line materials (three.js Line2/LineMaterial)
- [ ] Point clouds with point size
- [ ] Sprites / screen-aligned quads with size attenuation (three.js Sprite)
- [ ] 2D text that is not extruded (#119)
- [ ] Terrain / heightmap geometry
- [ ] Constructive solid geometry in the scene graph (SwiftMesh has boolean meshes)
- [ ] Procedural geometry modifiers: bend, twist, noise (Babylon, Blender-style)
- [ ] GPU tessellation and displacement (SceneKit tessellator)

## Animation
- [ ] Animation along a path / spline (SceneKit follow, three.js curves)
- [ ] Tweening of any property (three.js tween, RealityKit FromToByAnimation)
- [ ] Physics-based springs and spring animations (RealityKit, SwiftUI-style)
- [ ] Animation retargeting between skeletons
- [ ] GPU skinning for all renderers (CPU skinning today is slow in Debug)
- [ ] Constraint influence factors (SceneKit)

## Physics and interaction
- [ ] Physics joints: hinge, ball-and-socket, slider, fixed (SceneKit, RealityKit, Jolt)
- [ ] Collision and contact callbacks, trigger volumes (SceneKit contact delegate, RealityKit CollisionEvents)
- [ ] Physics fields: gravity, vortex, drag, noise (SceneKit SCNPhysicsField)
- [ ] Character controller (Jolt has one)
- [ ] Vehicles (SceneKit SCNPhysicsVehicle)
- [ ] Soft bodies and cloth
- [ ] Raycasts against physics (vs. render geometry)
- [ ] Gestures and manipulators: drag, rotate and scale objects; transform gizmos (RealityKit installGestures, three.js TransformControls)
- [ ] Camera controllers: first person, fly, map, follow camera (three.js controls)

## Architecture
- [ ] Entity-component-system or components on nodes (RealityKit, Godot)
- [ ] Presentation tree / interpolated rendering state (SceneKit presentation)
- [ ] Scene serialization to a native format (#52), prefabs / reusable subtrees
- [ ] Asset metadata: up axis, units, frame rate
- [ ] Spatial audio with occlusion and reverb (RealityKit)
- [ ] Accessibility for 3D content (RealityKit accessibility components)

- `2026-10-22T14:05:30Z`: Superseded by Documentation/Features.md.

---

## 153: Game demo: 3D platformer like SceneKit's Fox

+++
status: open
priority: low
kind: feature
labels: deferred, area:demo, effort:xl
created: 2026-10-22T01:56:58Z
updated: 2026-10-23T13:22:39Z
+++

A small playable platformer, in the spirit of Apple's SceneKit Fox demo, to exercise the engine as a whole.

Gameplay: a rigged character runs, jumps and collects items across platforms; a follow camera; simple hazards or enemies.

Exercises: skinning and animation blending (idle, run, jump via the AnimationStateMachine), physics with a character controller (Jolt has one; see #152), collision callbacks/triggers for pickups, follow camera, particles and audio for pickups, shadows, PBR.

Asset candidates (verify each license before adding; prefer CC0 glTF so no conversion or credits):
- Quaternius (quaternius.com): CC0 low-poly animated characters (walk, run, jump, idle) and platformer/environment packs.
- Kenney (kenney.nl): CC0 Platformer Kit, Animated Characters, props and level pieces.
- KayKit (kaylousberg.itch.io): rigged characters with many animations; free tiers CC0.
- Mixamo: auto-rig plus animation library; FBX (needs Blender conversion) and raw files probably not redistributable, so a poor fit for a public repo.
- Sketchfab, Poly Pizza: filter by animated + CC0/CC-BY; CC-BY needs credit.
- Already on disk: Khronos glTF sample assets (Fox, CesiumMan, BrainStem) for testing only; not a game kit.

Suggested start: a Quaternius character with Kenney's Platformer Kit.

Related: #151 (demos for every feature), #152 (feature gaps: character controller, contact callbacks, follow camera).

---

## 154: Manipulation widgets: transform gizmos for moving, rotating and scaling nodes

+++
status: closed
priority: medium
kind: feature
created: 2026-10-22T14:49:36Z
updated: 2026-10-23T13:13:51Z
closed: 2026-10-23T13:13:51Z
+++

Add on-screen manipulators for editing nodes in a SceneView, like three.js TransformControls, RealityKit's installGestures, Unity and Godot gizmos.

Want:
- Translate (axis arrows, plane handles, free), rotate (axis rings, trackball), scale (axis and uniform) handles.
- World or local space; snapping to a grid, angle step or scale step.
- Handles drawn on top of the scene at a constant screen size, highlighted on hover.
- Picking via hit testing; dragging along a constrained axis or plane in screen space.
- Undo-friendly change callbacks (begin, change, end).
- Touch gestures (drag, pinch, rotate) on iOS and visionOS, mouse on macOS.

Uses: the demo inspector, a future scene editor, and save/load round trips (#52).

Related: Documentation/Features.md rows 'Gestures and transform gizmos' and 'Scene inspector and editor'.

- `2026-10-23T13:13:51Z`: Done in SceneSprocketsGizmos (TransformGizmo). Remaining: trackball and pinch/rotate (#178), touch drag (#173).

---

## 155: Make scene graph changes observable to SwiftUI

+++
status: closed
priority: medium
kind: enhancement
labels: effort:m, area:scenegraph
created: 2026-10-22T15:22:08Z
updated: 2026-10-23T13:43:56Z
closed: 2026-10-23T13:43:56Z
+++

SceneGraph and SceneGraph.Node are plain classes. SwiftUI views that read them (for example an outline of the node tree, or an inspector showing a node's label or transform) do not update when the graph changes.

SceneSprocketsComposer needs this to show a live scene tree and inspector while editing.

Expected: changing a node's children, label, content or transform invalidates SwiftUI views that read those properties. Options include `@Observable` on Node/SceneGraph, or a revision value that views can observe.

Constraint: the renderer reads the graph every frame. Observation must not add noticeable per-frame cost (for example, from transform changes during animation or physics).

- `2026-10-23T13:43:56Z`: Fixed: SceneGraph and SceneGraph.Node are @Observable; caches, revisions and parent are @ObservationIgnored so render-time reads/cache writes don't invalidate. Cost (Release, 1000 nodes, set every transform + traverse each frame): 0.11 -> 0.17 ms/frame. Composer's transformRevision workaround can now go.

---

## 156: Scene archive: scene.json for the graph

+++
status: closed
priority: medium
kind: feature
created: 2026-10-22T15:28:24Z
updated: 2026-10-22T16:13:26Z
closed: 2026-10-22T16:13:26Z
+++

Part of #52. Write and read a .scenesprocketsd package directory with scene.json describing the graph. Codable on the domain types (no shadow types): Node (label, local transform, pivot, visibility, opacity, category and light masks, rendering order, children), Shape (regenerated on load), Light, Camera (perspective, orthographic), Environment, Fog, PostProcessing. Materials through a codec registry the renderer modules register (PBR, Blinn-Phong). Mesh content comes from the issues for glTF references and generated meshes. Done when a round-trip test (write, read, compare) passes for a scene with shapes, lights and cameras.

- `2026-10-22T16:13:26Z`: Done: SceneArchive writes and reads .scenesprocketsd packages (scene.json + textures). Round-trip tests pass. Follow-ups: #159-#165.

---

## 157: Scene archive: keep glTF content by reference

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:document
created: 2026-10-22T15:28:24Z
updated: 2026-10-23T13:45:09Z
+++

Part of #52. When a glTF is loaded into a scene, tag each imported node with its source asset and glTF node index. Writing a scene copies the original glTF (with its buffers and images) into the package; scene.json refers to it (asset, node index) instead of storing meshes or materials. Reading runs the glTF loader and splices the nodes back in. Transform and visibility changes on imported nodes are stored as overrides in scene.json; decide what to do for material or mesh changes (override or fall back to writing the mesh as generated). Done when a scene with a loaded glTF round-trips, including a moved imported node.

- `2026-10-23T13:45:09Z`: Punted by auto-issue-fixer. Read GLTFSceneGraph.swift and the archive code. Punting: needs decisions. (1) Same as #158: the core archive has no glTF dependency, so this needs a content hook on SceneArchive implemented in SceneSprocketsPBR — best designed once for #157 and #158 together. (2) The issue leaves open what to do when an imported node's material or mesh is edited (override vs fall back to #158's generated-mesh path). (3) One glTF node can become several scene nodes (GLTFSceneGraphBuilder.node(_:) returns [Node], e.g. multi-material or instanced meshes), so the reference needs a sub-index or a rule. Unblocker: decide the hook design (see #158 comment) and pick the override rule; then this is implementable.

---

## 158: Scene archive: write generated meshes as glTF

+++
status: open
priority: medium
kind: feature
labels: effort:m, area:document
created: 2026-10-22T15:28:25Z
updated: 2026-10-23T13:44:43Z
+++

Part of #52. Meshes built in code (MetalMesh from SwiftMesh: dice, gears, hand-built geometry) are written into the package as glTF, with their materials and textures (read back from the GPU), and scene.json refers to them. SwiftGLTF main can build documents from scratch (public initializers, settable Document, Container(document:binaryBuffer:url:), see its AuthoringTests). Done when a scene with generated dice round-trips.

- `2026-10-23T13:44:43Z`: Punted by auto-issue-fixer. Looked at SceneGraph+Archive.swift (the mesh-not-a-shape branch) and target deps. Punting: needs two design decisions. (1) Where the glTF writer lives: the core SceneSprockets target has no SwiftGLTF dependency (only SceneSprocketsPBR does). Options: add SwiftGLTF to core, or add a mesh-codec hook to SceneArchive (like materialTypes) and implement it in SceneSprocketsPBR. (2) Materials: the issue says write materials and textures into the glTF, but scene.json already archives Blinn-Phong/PBR materials and textures. Should the glTF carry geometry only (materials stay in scene.json), or also materials? My suggestion: hook in SceneSprocketsPBR, geometry-only glTF (MetalMesh -> Mesh -> glTF primitives per submesh).

---

## 159: Scene archive: make scene.json easier to read

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-23T14:07:13Z
closed: 2026-10-23T14:07:13Z
+++

Part of #52. Synthesized Codable writes enums as objects ({"directional": {}}, {"none": {}}) and SIMD vectors and matrices one number per line. Write simple enums as strings and vectors as compact arrays, keeping the format stable for reading. See ~/Desktop/shadows.scenesprocketsd (scenesprockets-demos --save shadows).

- `2026-10-23T14:07:13Z`: Fixed: LightType and BlendMode are String-raw enums written as strings; Background .none is "none"; number arrays (vectors, matrices) are compacted onto one line after encoding. Old synthesized enum objects still decode. Tests sceneJSONIsReadable, oldEnumFormatStillReads.

---

## 160: Scene archive: save ShaderMaterial

+++
status: open
priority: low
kind: feature
labels: effort:m, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-23T13:22:40Z
+++

Part of #52. ShaderMaterial is not archivable: its shaders are compiled functions. Save a reference to the shader (library and function names, or source) plus parameters (floats, vectors, matrices, textures via the archive context; buffers as data). Seen in scenekit-features: 'Red Pane'.

---

## 161: Scene archive: save animation, constraints and actions

+++
status: closed
priority: medium
kind: feature
labels: effort:l, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-23T13:53:26Z
closed: 2026-10-23T13:53:26Z
+++

Part of #52. Not saved yet: animation clips and players, constraints, running actions. Closure-based ones (Constraint.transform, Action.custom/run, custom animation properties) cannot be saved; decide whether to skip them with a warning or replace them with named, registered behaviors. Seen in shadows and scenekit-features (spinning torus, look-at constraints).

- `2026-10-23T13:53:26Z`: Constraints done: saved in scene.json with node references as child-index paths from the root, resolved after the tree is read; .transform (closure) skipped with a warning. Test constraintsRoundTripWithNodeReferences. Animation and actions split to #179 (Action is closure-based; needs a data model).

---

## 162: Scene archive: save morph targets, skins, physics, particles, audio, levels of detail

+++
status: open
priority: medium
kind: feature
labels: effort:l, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-23T13:22:39Z
+++

Part of #52. Node features not saved yet: morph targets and weights, skins and skin vertices, physics bodies, particle systems (MetalSprocketsParticles' ParticleSystem is already Codable), audio players, levels of detail. Each warns today.

---

## 163: Scene archive: store PBR uniforms field by field

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-23T14:10:35Z
closed: 2026-10-23T14:10:35Z
+++

Part of #52. PBRSceneMaterial saves PBRMaterialUniforms as raw bytes with a size check, so archives break whenever MetalSprocketsPBR changes the struct layout. Encode the fields by name (factors, texture slots with transforms and texCoord sets, extension parameters) so archives survive layout changes and are readable.

- `2026-10-23T14:10:35Z`: Fixed: PBR uniforms saved by name under 'parameters' (factors, flags, alpha mode, texture slots with transform/texCoord/enabled); missing fields keep defaults. Mesh-derived flags (hasTangents, hasNormals, isPointOrLine) are set at draw time and not saved. Old raw-byte archives still read. Tests pbrUniformsAreStoredByName, rawPBRUniformsStillRead.

---

## 164: Scene archive: samplers, texture transforms and more texture formats

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:document
created: 2026-10-22T16:11:23Z
updated: 2026-10-23T13:22:40Z
+++

Part of #52. Not saved yet: sampler states (textures load with linear repeat), PBR animatable texture transforms, mip levels (regenerated, not stored), cube and 3D textures, compressed formats (ASTC, BC). Float textures are raw bytes; consider EXR.

---

## 165: Open and save .scenesprocketsd documents in the demo app

+++
status: open
priority: low
kind: feature
labels: deferred, area:demo, effort:s
created: 2026-10-22T16:11:23Z
updated: 2026-10-23T13:22:40Z
+++

Part of #52. Register a UTType for .scenesprocketsd (a package) and add open/save to the demo app, for example with DocumentGroup, so archives can be inspected and edited. Today only scenesprockets-demos --save writes them, and nothing reads them except tests.

---

## 166: Geometry highlighting: show selected and hovered nodes in a SceneView

+++
status: closed
priority: medium
kind: feature
created: 2026-10-22T17:48:50Z
updated: 2026-10-23T13:24:20Z
closed: 2026-10-23T13:24:20Z
+++

Add a way to highlight nodes in a SceneView, for selection and hover feedback in an editor (like Reality Composer, Unity and Godot).

Want:
- Highlight a set of nodes (with or without their descendants).
- Styles: outline (silhouette) drawn on top of the scene, and optionally a tint or wireframe overlay.
- Works for all material families (BlinnPhong, PBR, shader materials) without changing the materials.
- Separate styles for selected and hovered.
- Low cost when nothing is highlighted.

Uses: SceneSprocketsComposer (selection in the scene tree and preview), the demo inspector, and the hover highlight that the transform gizmos need (#154).

- `2026-10-23T13:24:20Z`: Done: SelectionOutline (SceneSprocketsGizmos). Depth bug tracked in #172.

---

## 167: Transform gizmo: touch support on iOS and visionOS

+++
status: closed
priority: medium
kind: feature
created: 2026-10-22T18:03:48Z
updated: 2026-10-23T13:13:16Z
closed: 2026-10-23T13:13:16Z
+++

Follow-up to #154. SceneView routes a drag to the manipulator only when the pointer hovers over a handle (onContinuousHover), so on touch screens without a pointer the gizmo cannot be dragged and camera control takes the drag. Decide at touch-down instead (hit test the start location, then suppress camera control for that gesture), and add pinch/rotate gestures for scale and rotate.

- `2026-10-23T13:13:16Z`: Covered by #173 (decide at press, not hover).

---

## 168: Transform gizmo: view-aligned rotate ring and trackball

+++
status: open
priority: low
kind: enhancement
labels: effort:m, area:ui
created: 2026-10-22T18:03:48Z
updated: 2026-10-23T13:22:41Z
+++

Follow-up to #154. Rotate mode has the three axis rings only. Add a ring facing the camera (rotate about the view axis) and free trackball rotation inside the rings, like three.js TransformControls and Blender.

- `2026-10-23T13:22:41Z`: Related: #178 (touch pinch/rotate) was split off; trackball stays here.

---

## 169: Transform gizmo: dim hidden ring halves and handles pointing at the camera

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:ui
created: 2026-10-22T18:03:49Z
updated: 2026-10-23T14:13:06Z
closed: 2026-10-23T14:13:06Z
+++

Follow-up to #154. Ring halves behind the gizmo's center draw like the front halves, and an axis pointing at the camera collapses to a dot that is hard to grab. Draw back halves dimmer and hide or fade handles that face the camera.

- `2026-10-23T14:13:06Z`: Fixed: rotate rings draw their back half (behind the center) dimmer and thinner; translate/scale axes pointing at the camera and planes seen edge-on fade out, and fully faded handles are not picked. Tests handlesPointingAtTheCameraFade, ringsSplitIntoFrontAndBackHalves. Look not checked by eye.

---

## 170: Demo: undo for gizmo edits and a transform inspector

+++
status: open
priority: low
kind: enhancement
labels: deferred, area:demo, effort:m
created: 2026-10-22T18:03:49Z
updated: 2026-10-23T13:22:40Z
+++

Follow-up to #154. TransformGizmo has onBegin/onChange/onEnd, but the demo app does not record undo steps or show the selected node's transform. Register undo with the window's UndoManager on onBegin/onEnd, and show position, rotation and scale in the inspector.

---

## 171: TransformGizmo sizing: constant screen size vs scaling with the camera

+++
status: open
priority: low
kind: enhancement
labels: effort:s, area:ui
created: 2026-10-22T18:51:28Z
updated: 2026-10-23T13:22:40Z
+++

TransformGizmo keeps a constant size on screen: `size` (110 view points) is converted to world units each frame with `SceneViewport.worldSizeOfPoint`. So the gizmo does not change size when the camera zooms or moves. This is what Unity, Godot and Blender do.

In SceneSprocketsComposer this felt wrong: the user expected the gizmo to change size with the camera.

Decide the behavior, and maybe make it an option:
- Screen size (current): always easy to grab, but it gives no depth cue and can look large next to small objects.
- World size: scales with distance like the scene; can become too small or too large to use.
- Hybrid: screen size, clamped to a world size range or scaled by a fraction of the target bounds.

Related: #154 (transform gizmo).

---

## 172: SelectionOutline draws over objects in front of the selection

+++
status: closed
priority: medium
kind: bug
labels: area:ui, effort:m
created: 2026-10-22T21:55:34Z
updated: 2026-10-23T13:38:09Z
closed: 2026-10-23T13:38:09Z
+++

The selection outline (SelectionOutline, #166) shows through objects that are in front of the selected node. Seen in SceneSprocketsComposer.

Cause: SelectionOutline draws JumpFloodOutlineRenderPipeline with `.always` (x-ray). SceneView uses memoryless depth when there are no post passes, so the overlay passes cannot depth-test against the scene.

Fix options:
- Keep the scene depth when an overlay needs it (store depth, private storage, like the post passes), and draw the outline with `.greaterEqual` (reversed depth). The mask carries depth in its green channel, so the mask texture must be `.rg32Float`.
- Make x-ray an option (Blender shows hidden parts fainter).

MetalSprocketsAddOns JumpFloodOutlineDemoView shows the depth-tested setup.

- `2026-10-23T13:38:10Z`: Fixed: SelectionOutline is depth-tested by default (xray option for the old behavior). Mask is .rg32Float with reversed-depth projection; outline pass loads scene depth and tests .greaterEqual. SceneView keeps depth (private, stored) when it has an overlay. Tests: SelectionOutlineTests.

---

## 173: Gizmo handles need a hover before a click works

+++
status: closed
priority: medium
kind: bug
labels: area:ui, effort:s
created: 2026-10-22T21:55:34Z
updated: 2026-10-23T13:32:43Z
closed: 2026-10-23T13:32:43Z
+++

Clicking a TransformGizmo handle without moving the pointer over it first does not drag the handle. You have to hover, then press. Seen in SceneSprocketsComposer.

Cause: SceneView enables the manipulator drag only when `isHoveringManipulator` is true (set by `onContinuousHover`), with `highPriorityGesture(..., including: hovering ? .gesture : .subviews)`. If the press comes before a hover update, or on touch devices (no hover), the drag goes to camera control instead. Turning on `.gesture` while hovering was also how the camera was kept off the gizmo drag.

Fix:
- Attach the manipulator drag as a simultaneous gesture, always enabled. At drag start, hit-test the manipulator at `startLocation`; if it misses, ignore the rest of the drag.
- Tell Interaction3D camera control to ignore drags that start on the manipulator, with the drag filter from Interaction3D #38. No hover gating, no gesture masks.
- Works the same on iOS and visionOS.

Blocked on Interaction3D #38. Related: #154.

- `2026-10-23T13:32:43Z`: Fixed: manipulator drag is a simultaneous gesture that hit-tests at drag start; camera control uses interactionDragFilter (Interaction3D #38). No unit test: SwiftUI gesture routing isn't reachable from unit tests; verify by hand in the composer/demo (click a handle without hovering first, and on iOS).

---

## 174: Move the transform gizmo to Interaction3D

+++
status: open
priority: low
kind: task
labels: area:ui, deferred, effort:l
created: 2026-10-22T22:00:05Z
updated: 2026-10-23T13:22:40Z
+++

TransformGizmo (SceneSprocketsGizmos, #154) is mostly not about scene graphs: handle layout, picking, drag math along axes, planes and rings, snapping, and screen-size scaling. Other MetalSprockets apps could use it. Interaction3D is the home for 3D interaction (camera controls, rotation widget), so move the gizmo there, and keep a thin SceneSprockets adapter.

What ties it to SceneSprockets now:
- `target: SceneGraph.Node` and `onBegin/onChange/onEnd(SceneGraph.Node)`. Replace with a transform the caller owns: a `Binding<Transform3D>` or get/set closures, plus the parent world transform for local space.
- `SceneViewport`: camera matrix, projection, view and drawable size, `ray(through:)`, `project`, `worldSizeOfPoint`. Interaction3D needs its own small viewport type (GeometryLite3D has ViewProjection), or the gizmo takes one.
- `SceneViewManipulator` conformance and `overlay(viewport:) -> AnyElement`: keep in SceneSprockets as the adapter.

Drawing: the gizmo draws with MetalSprocketsAddOns GraphicsContext3D. Interaction3D does not depend on MetalSprockets. Options:
- Interaction3D owns the geometry (handle outlines as 3D polylines, colors, hover and active state); SceneSprockets (or AddOns) draws them.
- Or draw with SwiftUI Canvas over the view in Interaction3D: no Metal, but no depth.

Gestures: do this together with Interaction3D #38 (drag filter), so the gizmo and camera control share one gesture model with simultaneous gestures. Then SceneView's hover gating goes away (#173).

After the move: SceneSprocketsGizmos keeps SelectionOutline (or it moves too), and the demo app and SceneSprocketsComposer use the Interaction3D gizmo through the adapter.

- `2026-10-23T12:56:17Z`: Deferred. Leaning toward: rendering moves to MetalSprocketsAddOns (AddOns depends on Interaction3D; Interaction3D owns gizmo geometry/math, no Metal). Gesture model still undecided (see #38, #173).

---

## 175: Composer: save a preview PNG inside the document bundle

+++
status: open
priority: medium
kind: feature
labels: area:composer, area:document, effort:m
created: 2026-10-23T13:03:28Z
updated: 2026-10-23T13:22:41Z
+++

When saving a .scenesprocketsd bundle, render the scene offscreen and write a PNG into the bundle (for example `Preview.png`).

The Quick Look preview extension and a future thumbnail extension can then show the PNG directly. They do not need to load the scene or start Metal rendering, which is slow and heavy in an extension.

- Render at a fixed size (for example 1024 px on the longest side) from the editor camera, or from the scene camera if there is one.
- Quick Look: show the PNG if it exists. If it does not, fall back to `QuickLookPreviewView` (a live render).
- Add a thumbnail extension (`com.apple.quicklook.thumbnail`) that returns the PNG.

Blocked on #52 (save and load a scene graph).

---

## 176: Composer: Render tab camera settings should override the scene camera node

+++
status: closed
priority: medium
kind: bug
labels: area:composer, area:preview, effort:s
created: 2026-10-23T13:03:28Z
updated: 2026-10-23T13:34:56Z
closed: 2026-10-23T13:34:56Z
+++

The Render tab field of view and near/far clip apply only when the scene has no camera node. If the scene has a camera node, SceneView uses that camera's projection, and the settings do nothing. They should always apply in the editor preview: the editor camera is our own orbit camera, not the scene camera.

Needs a SceneView change: it picks the projection from the first camera node (or `pointOfView`) in drawing, `viewport()` and hit testing, and falls back to `defaultCamera` only when there is none. Add a way to force the projection, for example: when `cameraMatrix` is set without `.allowsCameraControl` (a free camera), use `defaultCamera`; or add a `projection` override parameter.

Also remove the "Used when the scene has no camera node." note from the Render tab.

- `2026-10-23T13:34:56Z`: Fixed: SceneView(camera:) / SceneGraphElement(cameraOverride:) replace the camera node's camera; the composer passes its Render tab camera. Test cameraOverrideReplacesCameraNodeProjection.

---

## 177: Composer: use Interaction3D camera control instead of OrbitCamera gestures

+++
status: closed
priority: medium
kind: task
labels: area:composer, area:preview, effort:s
created: 2026-10-23T13:03:28Z
updated: 2026-10-23T13:50:27Z
closed: 2026-10-23T13:50:27Z
+++

ScenePreviewView has its own orbit, pan and zoom gestures (OrbitCamera), because SceneView's Interaction3D camera control beat the gizmo's drag. Once Interaction3D can ignore drags that start on the gizmo (Interaction3D #38) and SceneView uses it (#173), go back to Interaction3D:

- SceneView `.allowsCameraControl` with our `cameraMatrix` binding, or `interactiveCamera(cameraMatrix:)` on the preview.
- Keep Frame Selection and Reset: they set the camera matrix (and orbit target).
- Remove OrbitCamera's gesture code, and the scroll wheel and magnify handlers in ScenePreviewView.

Blocked on Interaction3D #38 and #173.

- `2026-10-23T13:50:27Z`: Fixed: ScenePreviewView uses SceneView .allowsCameraControl (Interaction3D) with a cameraMatrix binding and the new SceneView cameraTarget; OrbitCamera replaced by EditorCamera (framing only); custom drag/magnify/scroll handlers removed. Gesture behavior needs a manual check in the app.

---

## 178: Transform gizmo: pinch and rotate gestures on iOS and visionOS

+++
status: open
priority: low
kind: feature
labels: area:ui, effort:m
created: 2026-10-23T13:13:51Z
updated: 2026-10-23T13:22:41Z
+++

Follow-up to #154. On iOS and visionOS: pinch to scale and two-finger rotate to rotate the selected node. Touch drag on handles is #173; trackball rotation is #168.

---

## 179: Scene archive: save animation clips and running actions

+++
status: new
priority: medium
kind: feature
labels: area:document, effort:l
created: 2026-10-23T13:53:20Z
+++

Split from #161 (constraints are done there).

- Actions: SceneGraph.Action stores its behavior as runner closures (makeRunner), so no action can be saved today, not even move(by:). Saving them needs a data description of actions (a Codable tree of the built-in kinds: move, rotate, scale, fade, hide, sequence, group, repeat, wait, ...) that builds the runners, plus the running state (elapsed time, key). Action.custom/run and TimingMode.custom are closures: skip them with a warning, or replace them with named, registered behaviors.
- Animation: AnimationClip and AnimationPlayer are not tied to nodes in the graph (players are owned by the caller), so decide what a saved scene holds: clips with node-path targets (like constraints in #161), and which players auto-play on load.

Seen in shadows and scenekit-features (spinning torus).

---
