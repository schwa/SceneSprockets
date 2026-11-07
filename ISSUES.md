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
status: closed
priority: low
kind: documentation
labels: effort:m, area:docs, release
created: 2026-10-12T15:17:53Z
updated: 2026-11-07T15:34:54Z
closed: 2026-11-07T15:34:54Z
+++

Split from #18, which got a README guide (scene building, rendering, custom renderers, reversed depth, change tracking, bounds, animation, limitations). Per-symbol DocC comments were left out on purpose: the API is changing quickly, and AGENTS.md asks for no doc comments unless asked. Do this once the API settles (after glTF loading, #16).

- `2026-11-07T15:34:54Z`: Fixed: every public declaration in all seven modules has a /// doc comment, except protocol witnesses (body, encode/init(from:), materialType, makeElement, isTransparent, appliesNodeOpacity, archive and manipulator methods), which inherit the documented protocol requirements. Done in steps: existing // comments above public declarations, enum cases and protocol requirements became doc comments; the rest were written by hand (the 21 NodeField components share one template). just check-docs (warnings as errors) passes; build 0 warnings; 327 tests pass; lint clean.

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
status: closed
priority: medium
kind: feature
labels: area:assets, effort:l
created: 2026-10-13T20:20:23Z
updated: 2026-11-04T20:52:33Z
closed: 2026-11-04T20:52:33Z
+++

A scene graph can't be saved. SceneKit can archive `SCNScene` (`.scn`) and export it.

Want: a file format for the node tree, transforms, content, materials, animation, skins and morph targets. Mesh data could be stored inline or as external references. Different from glTF and USD import (#16, #31).

- `2026-10-13T20:21:45Z`: Related: #16, #31, #37 (importers).
- `2026-10-13T20:45:21Z`: Looked at the model. Punting: this needs design decisions that the code cannot answer. (1) Materials are 'any Material' and projections 'any ProjectionProtocol' (open protocols), so decoding needs a type registry or a closed set of types. (2) Textures (MTLTexture inside PBRMaterial/BlinnPhongMaterial) and PBREnvironment maps have no source data to write back. (3) Container format: one JSON file with base64 mesh data, a package directory (scene.json + .bin buffers + images), or glTF export instead of a new format. Proposal: a package directory: scene.json (Codable nodes, TRS, skins by node id, morphs, clips, environment settings), one .bin per MetalMesh (vertex/index buffers + descriptor), PNG/EXR for textures read back from the GPU, and a MaterialCodec registry that renderer modules register (PBR, Blinn-Phong). Unblocker: OK this design (or prefer glTF export), and say if reading textures back from the GPU is acceptable.
- `2026-10-13T20:50:31Z`: Deferred: scene graphs are built by hand (or imported) for now.
- `2026-10-22T15:28:24Z`: Design decided: a package directory (.scenesprocketsd) with scene.json for the graph; glTF content by reference (the original file copied into the package); generated meshes written as glTF too (needs SwiftGLTF builder APIs). Core first: node tree, transforms, flags, shapes, materials, lights, cameras, environment/fog/post. Animations, skins, morphs, constraints, physics, particles later. Split into the issues below.
- `2026-10-25T01:34:52Z`: #157 (glTF kept by reference) and #158 (generated meshes as glTF) are done.
- `2026-11-04T20:52:33Z`: All split-out subtasks are closed (#156-#165, #180): SceneArchive writes and reads .scenesprocketsd packages, and the Composer saves and opens them. Remaining gaps are tracked separately: #179 (animation clips, running actions) and #182 (audio players, LOD). Closing this umbrella.

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
labels: area:renderer, effort:m
created: 2026-10-14T01:11:25Z
updated: 2026-11-07T15:46:16Z
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

- `2026-11-07T15:50:34Z`: Autonomous run: investigated, no fix. Findings: (1) The Dice sighting (2026-10-21) is after Blinn-Phong (#71, 10-15) and PBR (#102, 10-16) started sampling shadows in their shaders, and the dice scene is Blinn-Phong plus PBR, so the flicker is not only in the screen-space ShadowMaskPass that the original theory centers on. (2) Shadow map slots are picked by submission index and the caster pass ends with barrierAfterPass(after: .fragment, ...); 6 slots made no difference, so slot reuse looks ruled out. Remaining suspects on the in-shader path: per-frame data the shaders read (light view-projection matrices, shadow slices) living in a buffer that the CPU rewrites while an earlier frame is still in flight. Punting: it only reproduces live, by timing, and I cannot verify a guess offscreen. Unblocker: a GPU trace of a flashing frame in the settled Dice demo, or permission to add per-frame logging of the shadow uniforms' buffer identity and contents and run the app to compare.

---

## 60: Shadow acne on lit surfaces (depth bias ineffective)

+++
status: closed
priority: medium
kind: bug
labels: area:renderer, effort:s
created: 2026-10-14T01:14:55Z
updated: 2026-10-24T14:28:15Z
closed: 2026-10-24T14:28:15Z
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
status: closed
priority: low
kind: feature
labels: effort:m, area:scenegraph
created: 2026-10-15T02:28:07Z
updated: 2026-10-24T15:07:59Z
closed: 2026-10-24T15:07:59Z
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
status: closed
priority: low
kind: bug
labels: area:demo, effort:s
created: 2026-10-16T00:06:57Z
updated: 2026-11-07T15:55:52Z
closed: 2026-11-07T15:55:52Z
+++

The code panels in KeynoteDemo.swift show Swift that does not compile if pasted.

- Scene Graph and Shapes slides: Node(shape:material:) leaves out the required device: argument.
- Animation Blending slide: 'let controller' must be 'var' (blend and advance are mutating). 'mixer' is not defined.
- Actions slide: 'down' is not defined.

Expected: each snippet compiles, given the obvious names (materials, nodes) it refers to.

- `2026-11-07T15:55:53Z`: Fixed: Scene Graph and Shapes snippets pass device:; Actions defines down as up.reversed(); Animation Blending declares the mixer and makes the controller var; Materials uses BlinnPhongSceneMaterial's initializer instead of the demo-only .plastic helper. Verified by compiling all five snippets in a temporary test file (short type names via private typealiases, per #128), then removed. Materials and Animation Blending panels checked in offscreen renders.

---

## 127: Keynote code panels: snippets do not match what the slide does

+++
status: closed
priority: low
kind: bug
labels: area:demo, effort:s
created: 2026-10-16T00:06:57Z
updated: 2026-11-07T15:57:48Z
closed: 2026-11-07T15:57:48Z
+++

Some code panels in KeynoteDemo.swift differ from the code that builds the slide, or show demo-only API.

- Shadows slide: 'scene.shadows = SceneGraphShadows(...)' is a DemoScene property, not library API. Library users pass shadows to SceneView(..., shadows:).
- Scene Graph slide: the orbit's parent is shown as 'sun', but the demo parents it to the slide (the sun is a sibling).
- Actions slide: leaves out the rotate that runs in a group with the hop.

- `2026-11-07T15:57:48Z`: Fixed: Shadows panel shows the library API, SceneView(..., shadows:), and aims the light with trs.translation and look(at:) instead of the demo-only .camera(eye:target:) (which did not compile either); the Scene Graph demo now parents the orbit to the sun, as the panel shows; the Actions panel includes the spin grouped with the hop. The changed snippets were compiled in a temporary test file (removed); slides 1, 5 and 12 checked in offscreen renders.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:renderer
created: 2026-10-17T12:19:22Z
updated: 2026-10-24T15:04:55Z
closed: 2026-10-24T15:04:55Z
+++

SceneGraph has no standard way to view a scene in debug modes such as normals, UVs, tangents, world position or material channels. The only option is ShaderMaterial.normals(), which has to be set on each node by hand.

Related debug shaders already exist in sibling packages:
- MetalSprocketsAddOns: DebugRenderPipeline / DebugShaders.metal (DebugShadersMode: normals, texture coordinates, tangents, bitangents, world and local position, IDs).
- MetalSprocketsPBR: PBRRenderer.debugView (PBRDebugView: base color, alpha, metallic, roughness, occlusion, emissive, shading and geometric normals, tangents, UVs, UV checker, front facing, transmission, clearcoat, sheen, iridescence and more). The GLTF viewer uses it.

None of these can be turned on for a whole SceneGraph or SceneView, and Blinn-Phong has no equivalent.

Requested (per user): make debug shaders a default part of this project, so any scene can be shown in a debug mode.

- `2026-10-24T14:17:41Z`: Related: #188 (Composer debug shapes for lights and cameras).
- `2026-10-24T14:18:20Z`: Related: #188 (Composer debug shapes for lights and cameras).

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
labels: effort:m, area:renderer
created: 2026-10-17T13:09:48Z
updated: 2026-11-07T15:46:16Z
+++

Screen-space ambient occlusion is configured as SceneGraph.PostProcessing.ambientOcclusion, next to exposure, contrast, saturation and vignette, and runs as a post pass (ambient_occlusion in PostProcessing.metal) that multiplies the final rendered color.

Problems:
- It is grouped with color grading, although it is a lighting effect.
- It darkens all light at a pixel: direct lighting, specular highlights and emission are occluded, not just ambient and indirect light. A crease lit by a spotlight still goes dark, and emissive or unlit content (for example the keynote's code panels and titles) is darkened.
- Material renderers never see the occlusion: Blinn-Phong ambient and PBR image-based lighting cannot apply it to their ambient terms.

Expected: ambient occlusion reduces only ambient and indirect lighting, and is configured as a lighting setting, separate from post-processing color adjustments.

- `2026-11-07T15:50:56Z`: Autonomous run: scoped, not changed. Doing this needs (1) the AO texture computed before the material passes (a depth prepass, or reordering so AO runs between a depth-only pass and shading), (2) Blinn-Phong to multiply only its ambient term by it, (3) PBR to multiply only its IBL/indirect term by it; MetalSprocketsPBR has no screen-space occlusion input today, so that is a change in MetalSprocketsPBR, and (4) a public API move of PostProcessing.ambientOcclusion to a lighting setting (for example SceneGraph.ambientOcclusion or Environment.ambientOcclusion). Punting: it is a cross-package design change, and the API placement is your call. Questions: where should the setting live, and is a depth prepass for AO acceptable (it costs a second geometry pass when AO is on)?

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
labels: area:demo, effort:s
created: 2026-10-22T01:05:11Z
updated: 2026-11-07T15:46:17Z
+++

DiceGeometry builds dice with sharp edges. Real dice (and the old Dice by PCalc models) have rounded edges, which catch highlights and read as solid objects, especially on the metal and glass styles. Bevel or chamfer each edge in DiceGeometry, keeping per-face texture coordinates and the convex hull used for physics. Done when the dice show rounded edges in the Dice demo and the numbers still sit on their faces.

---

## 149: Dice demo: use real-world face numbering

+++
status: open
priority: low
kind: enhancement
labels: area:demo, effort:xs
created: 2026-10-22T01:05:11Z
updated: 2026-11-07T15:46:17Z
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
status: closed
priority: medium
kind: feature
labels: effort:l, area:document
created: 2026-10-22T15:28:24Z
updated: 2026-10-25T01:34:52Z
closed: 2026-10-25T01:34:52Z
+++

Part of #52. When a glTF is loaded into a scene, tag each imported node with its source asset and glTF node index. Writing a scene copies the original glTF (with its buffers and images) into the package; scene.json refers to it (asset, node index) instead of storing meshes or materials. Reading runs the glTF loader and splices the nodes back in. Transform and visibility changes on imported nodes are stored as overrides in scene.json; decide what to do for material or mesh changes (override or fall back to writing the mesh as generated). Done when a scene with a loaded glTF round-trips, including a moved imported node.

\- `2026-10-23T13:45:09Z`: Punted by auto-issue-fixer. Read GLTFSceneGraph.swift and the archive code. Punting: needs decisions. (1) Same as #158: the core archive has no glTF dependency, so this needs a content hook on SceneArchive implemented in SceneSprocketsPBR — best designed once for #157 and #158 together. (2) The issue leaves open what to do when an imported node's material or mesh is edited (override vs fall back to #158's generated-mesh path). (3) One glTF node can become several scene nodes (GLTFSceneGraphBuilder.node(_:) returns [Node], e.g. multi-material or instanced meshes), so the reference needs a sub-index or a rule. Unblocker: decide the hook design (see #158 comment) and pick the override rule; then this is implementable.
\- `2026-10-24T11:44:52Z`: Decided: the glTF stored in the package must be complete and match the current scene. Composer is not a detailed glTF editor: imported glTFs are treated as mostly complete units. Detailed edits go through a separate 'explode' feature that converts the glTF node tree into scene graph nodes (see new issue).
\- `2026-10-25T01:01:53Z`: Decision (user): the glTF writer lives in SceneSprocketsPBR, as GLTFSceneGraph+Export.swift next to the importer GLTFSceneGraph.swift. SwiftGLTF already does file-level writing (Codable Document, GLTFWriter.glbData, Container.write(to:embedResources:)), so the new code only maps a SceneGraph to a glTF Document: meshes to accessors and buffer views, PBR and Blinn-Phong materials, nodes, KHR lights and cameras. Keeping both directions in one target allows read-write-read round-trip tests. Both may later move together into a SceneSprocketsGLTF target if they grow.
\- `2026-10-25T01:34:52Z`: Done.
- Core: SceneGraph.ModelSource holds a model file and the files it loads, as Data, so saving works in the App Sandbox after access has ended. It is stored on Node.modelSource (copied by clone()). The new ArchivableModelLoader hook on SceneArchive (modelLoader): a node with a modelSource is saved as {"model": "models/N/<file>"} plus its own fields (label, transform, visibility...); its content and subtree are not written. Identical sources share one folder. Reading loads the file with the loader, splices its content and children under the saved node, and rebuilds modelSource from the package folder, so re-saving keeps the reference. Without a loader, the subtree is saved like any other (meshes through #158's codec).
- SceneSprocketsPBR: ModelFile.load sets modelSource on glTF roots (main file + external buffers and images). ModelFileLoader implements the hook.
- Composer (per the 'mostly complete units' decision): nodes inside an imported model are locked. A click or context-menu pick inside one picks the model root. Nothing can be inserted, created or moved into a model (reparent refuses; insert falls back to the root; assistant tools explain why). Editing inside is #183 (explode).
- Not covered: Model I/O formats (USDZ, OBJ...) are not kept by reference; their meshes are saved through #158. glTF animations are still not imported (ModelFile.load drops them).
Tests: ModelReferenceArchiveTests.loadedGLTFIsKeptByReference (gltf + external .bin copied, moved root kept, mesh count, modelSource equal, re-save gives identical scene.json) and withoutALoaderTheSubtreeIsSaved; Composer insertedGLTFIsKeptByReference.

---

## 158: Scene archive: write generated meshes as glTF

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:document
created: 2026-10-22T15:28:25Z
updated: 2026-10-25T01:27:58Z
closed: 2026-10-25T01:27:58Z
+++

Part of #52. Meshes built in code (MetalMesh from SwiftMesh: dice, gears, hand-built geometry) are written into the package as glTF, with their materials and textures (read back from the GPU), and scene.json refers to them. SwiftGLTF main can build documents from scratch (public initializers, settable Document, Container(document:binaryBuffer:url:), see its AuthoringTests). Done when a scene with generated dice round-trips.

\- `2026-10-23T13:44:43Z`: Punted by auto-issue-fixer. Looked at SceneGraph+Archive.swift (the mesh-not-a-shape branch) and target deps. Punting: needs two design decisions. (1) Where the glTF writer lives: the core SceneSprockets target has no SwiftGLTF dependency (only SceneSprocketsPBR does). Options: add SwiftGLTF to core, or add a mesh-codec hook to SceneArchive (like materialTypes) and implement it in SceneSprocketsPBR. (2) Materials: the issue says write materials and textures into the glTF, but scene.json already archives Blinn-Phong/PBR materials and textures. Should the glTF carry geometry only (materials stay in scene.json), or also materials? My suggestion: hook in SceneSprocketsPBR, geometry-only glTF (MetalMesh -> Mesh -> glTF primitives per submesh).
\- `2026-10-24T11:26:48Z`: Punted again by auto-issue-fixer: the two design questions in the previous comment are still open. Unblocker: confirm 'mesh-codec hook in SceneSprocketsPBR, geometry-only glTF' (or pick another option).
\- `2026-10-24T11:44:52Z`: Decided: SwiftGLTF supports writing; the glTF carries materials too (not geometry only). Still open: where the writer lives (core vs hook in SceneSprocketsPBR).
\- `2026-10-25T01:01:54Z`: Decision (user): the glTF writer lives in SceneSprocketsPBR, as GLTFSceneGraph+Export.swift next to the importer GLTFSceneGraph.swift. SwiftGLTF already does file-level writing (Codable Document, GLTFWriter.glbData, Container.write(to:embedResources:)), so the new code only maps a SceneGraph to a glTF Document: meshes to accessors and buffer views, PBR and Blinn-Phong materials, nodes, KHR lights and cameras. Keeping both directions in one target allows read-write-read round-trip tests. Both may later move together into a SceneSprocketsGLTF target if they grow.
\- `2026-10-25T01:27:57Z`: Done.
- Core: a new ArchivableMeshCodec protocol on SceneArchive (meshCodec). A mesh that is not a shape is written as mesh.file (a package path) next to its materials and shadow flags. Without a codec it is still skipped with a warning. Nodes sharing a mesh share one file, and share the decoded mesh on read. The archive capture (#238) now carries arbitrary files, not only textures.
- SceneSprocketsPBR: GLTFMeshCodec in GLTFSceneGraph+Export.swift writes meshes/N.glb with every vertex attribute (glTF names, '_'-prefixed names for bitangents and 3-float tangents), one primitive per submesh, and glTF materials: PBR values, Blinn-Phong approximated (diffuse to base color, shininess to roughness), and core textures referenced as ../textures/N.png, shared with scene.json.
- Mesh extras record the attribute order and buffer layout, so reading restores the exact vertex descriptor and data.
- scene.json keeps the exact materials, so reading uses only the geometry from the glTF.
- Not saved: morph targets and skins inside the MetalMesh (warned).
- Enabled in the Composer (inserted models' meshes now survive saving; the 'not saved' insert alert is gone) and the Demo snapshot archive.
Tests: core generatedMeshesRoundTripAsGLTF (both buffer layouts; glTF validates; textures referenced; shared file; exact attribute bytes, descriptor, indices; materials). Composer insertedMeshesAreSavedWithTheDocument. Demo generatedDiceRoundTrip (dice demo saves and reads back every mesh).

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
status: closed
priority: low
kind: feature
labels: effort:m, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-23T14:22:53Z
closed: 2026-10-23T14:22:53Z
+++

Part of #52. ShaderMaterial is not archivable: its shaders are compiled functions. Save a reference to the shader (library and function names, or source) plus parameters (floats, vectors, matrices, textures via the archive context; buffers as data). Seen in scenekit-features: 'Red Pane'.

- `2026-10-23T14:22:53Z`: Fixed: ShaderMaterial is ArchivableMaterial. Saves library name (SceneArchive.shaderLibraries, new; sample shaders built in), function names, parameters (floats, vectors, float4x4, textures, CPU-readable buffers), isTransparent and render state. Samplers warn (#180); specialized functions and unregistered libraries are skipped with a warning via new ArchivableMaterial.archiveProblem(context:). Demo save registers ShaderMaterial. Tests shaderMaterialRoundTripsByReference, shaderMaterialFromAnUnregisteredLibraryIsSkipped.

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
status: closed
priority: medium
kind: feature
labels: effort:l, area:document
created: 2026-10-22T16:11:22Z
updated: 2026-10-24T11:29:39Z
closed: 2026-10-24T11:29:39Z
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
status: closed
priority: low
kind: enhancement
labels: effort:m, area:document
created: 2026-10-22T16:11:23Z
updated: 2026-10-23T14:14:45Z
closed: 2026-10-23T14:14:45Z
+++

Part of #52. Not saved yet: sampler states (textures load with linear repeat), PBR animatable texture transforms, mip levels (regenerated, not stored), cube and 3D textures, compressed formats (ASTC, BC). Float textures are raw bytes; consider EXR.

- `2026-10-23T14:14:45Z`: PBR animatable texture transforms done: stored by name with their slot name, offset, rotation and scale (test pbrTextureTransformsRoundTrip). Samplers, stored mips, cube/3D, compressed formats and EXR split to #180 (samplers need their descriptor kept; MTLSamplerState cannot be read back).

---

## 165: Open and save .scenesprocketsd documents in the demo app

+++
status: closed
priority: low
kind: feature
labels: deferred, area:demo, effort:s
created: 2026-10-22T16:11:23Z
updated: 2026-10-24T14:21:10Z
closed: 2026-10-24T14:21:10Z
+++

Part of #52. Register a UTType for .scenesprocketsd (a package) and add open/save to the demo app, for example with DocumentGroup, so archives can be inspected and edited. Today only scenesprockets-demos --save writes them, and nothing reads them except tests.

- `2026-10-24T14:21:10Z`: Closing: the Composer (DocumentGroup, .scenesprocketsd UTType) opens and saves these documents now.

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
status: closed
priority: low
kind: enhancement
labels: effort:m, area:ui
created: 2026-10-22T18:03:48Z
updated: 2026-10-23T14:17:56Z
closed: 2026-10-23T14:17:56Z
+++

Follow-up to #154. Rotate mode has the three axis rings only. Add a ring facing the camera (rotate about the view axis) and free trackball rotation inside the rings, like three.js TransformControls and Blender.

- `2026-10-23T13:22:41Z`: Related: #178 (touch pinch/rotate) was split off; trackball stays here.
- `2026-10-23T14:17:57Z`: Fixed: rotate mode has a white view-aligned ring (1.1x radius) that turns about the view direction, and a trackball inside the rings (.center) that turns freely with the drag (0.01 rad/point, not snapped). The inner 60% of the rings is always the trackball, since edge-on rings project through the center. Tests viewRingRotatesAboutTheViewDirection, trackballTurnsTheNearSideWithTheDrag.

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
status: closed
priority: low
kind: enhancement
labels: deferred, area:demo, effort:m
created: 2026-10-22T18:03:49Z
updated: 2026-10-24T14:21:10Z
closed: 2026-10-24T14:21:10Z
+++

Follow-up to #154. TransformGizmo has onBegin/onChange/onEnd, but the demo app does not record undo steps or show the selected node's transform. Register undo with the window's UndoManager on onBegin/onEnd, and show position, rotation and scale in the inspector.

- `2026-10-24T14:21:10Z`: Closing: the Composer has undo for gizmo edits and an editable transform inspector now.

---

## 171: TransformGizmo sizing: constant screen size vs scaling with the camera

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:ui
created: 2026-10-22T18:51:28Z
updated: 2026-10-24T11:30:21Z
closed: 2026-10-24T11:30:21Z
+++

TransformGizmo keeps a constant size on screen: `size` (110 view points) is converted to world units each frame with `SceneViewport.worldSizeOfPoint`. So the gizmo does not change size when the camera zooms or moves. This is what Unity, Godot and Blender do.

In SceneSprocketsComposer this felt wrong: the user expected the gizmo to change size with the camera.

Decide the behavior, and maybe make it an option:
- Screen size (current): always easy to grab, but it gives no depth cue and can look large next to small objects.
- World size: scales with distance like the scene; can become too small or too large to use.
- Hybrid: screen size, clamped to a world size range or scaled by a fraction of the target bounds.

Related: #154 (transform gizmo).

- `2026-10-24T11:30:21Z`: Added TransformGizmo.worldSize (opt-in, world units). Default stays screen size; Composer not switched. Hybrid (clamped) mode not added.

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
status: closed
priority: medium
kind: feature
labels: area:composer, area:document, effort:m
created: 2026-10-23T13:03:28Z
updated: 2026-10-24T14:42:46Z
closed: 2026-10-24T14:42:46Z
+++

When saving a .scenesprocketsd bundle, render the scene offscreen and write a PNG into the bundle (for example `Preview.png`).

The Quick Look preview extension and a future thumbnail extension can then show the PNG directly. They do not need to load the scene or start Metal rendering, which is slow and heavy in an extension.

- Render at a fixed size (for example 1024 px on the longest side) from the editor camera, or from the scene camera if there is one.
- Quick Look: show the PNG if it exists. If it does not, fall back to `QuickLookPreviewView` (a live render).
- Add a thumbnail extension (`com.apple.quicklook.thumbnail`) that returns the PNG.

Blocked on #52 (save and load a scene graph).

- `2026-10-24T11:27:01Z`: Punted by auto-issue-fixer: blocked on #52 (still open). Re-queued after #52 in this run.
- `2026-10-24T14:21:10Z`: Undeferred: the Composer already saves and loads .scenesprocketsd bundles through SceneArchive, so the block on #52 no longer stops this.
- `2026-10-24T14:42:46Z`: Done: saving writes Preview.png (1024×768, from the first camera node or a framed default camera), and Quick Look shows it, falling back to the live render. The thumbnail extension is split out into its own issue, because it needs a new Xcode target.

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
status: closed
priority: low
kind: feature
labels: area:ui, effort:m
created: 2026-10-23T13:13:51Z
updated: 2026-10-23T14:28:06Z
closed: 2026-10-23T14:28:06Z
+++

Follow-up to #154. On iOS and visionOS: pinch to scale and two-finger rotate to rotate the selected node. Touch drag on handles is #173; trackball rotation is #168.

- `2026-10-23T14:28:06Z`: Implemented: SceneViewManipulator gets two-finger hooks (claimsTwoFingerGesture/begin/change/end, default no-op). On iOS/visionOS SceneView adds a simultaneous Magnify+Rotate gesture; gestures starting within the gizmo's size of its center go to TransformGizmo (uniform scale, twist about the view direction, snapped), and Interaction3D's interactionMagnifyFilter keeps the camera from zooming with them. Test pinchAndTwistScaleAndTurnTheTarget. Not verified on iOS: the iOS build fails earlier in dependencies (#181); the gesture code was type-checked by enabling it on macOS temporarily.

---

## 179: Scene archive: save animation clips and running actions

+++
status: open
priority: medium
kind: feature
labels: area:document, effort:l, deferred
created: 2026-10-23T13:53:20Z
updated: 2026-10-24T11:44:52Z
+++

Split from #161 (constraints are done there).

- Actions: SceneGraph.Action stores its behavior as runner closures (makeRunner), so no action can be saved today, not even move(by:). Saving them needs a data description of actions (a Codable tree of the built-in kinds: move, rotate, scale, fade, hide, sequence, group, repeat, wait, ...) that builds the runners, plus the running state (elapsed time, key). Action.custom/run and TimingMode.custom are closures: skip them with a warning, or replace them with named, registered behaviors.
- Animation: AnimationClip and AnimationPlayer are not tied to nodes in the graph (players are owned by the caller), so decide what a saved scene holds: clips with node-path targets (like constraints in #161), and which players auto-play on load.

Seen in shadows and scenekit-features (spinning torus).

---

## 180: Scene archive: samplers, stored mip levels, cube/3D and compressed textures

+++
status: closed
priority: low
kind: enhancement
labels: area:document, effort:m
created: 2026-10-23T14:14:45Z
updated: 2026-10-24T12:52:18Z
closed: 2026-10-24T12:52:18Z
+++

Split from #164 (PBR texture transforms are done there).

- Samplers: MTLSamplerState cannot be read back, so saving one needs its MTLSamplerDescriptor kept with it. Probably MetalSprocketsPBR (PBRMaterial.Binding) and Blinn-Phong textures keep the descriptor; then store filters and address modes. Textures load with linear repeat today.
- Mip levels: only level 0 is stored; levels are regenerated on load. Store authored mips (for example from KTX2).
- Cube and 3D textures, and compressed formats (ASTC, BC): SceneArchiveContext.encode(texture:) throws for them.
- Float textures are raw bytes; consider EXR.

- `2026-10-24T11:44:53Z`: Decided: yes, keep sampler descriptors with textures so filters and address modes can be saved.
- `2026-10-24T11:53:26Z`: Sampler part depends on MetalSprocketsPBR #21.
- `2026-10-24T12:52:18Z`: Done: samplers (PBR via MetalSprocketsPBR #21; Blinn-Phong Source.texture now takes an MTLSamplerDescriptor), stored mip levels, 2D array/cube/cube array/3D textures, BC and ASTC compressed formats. Non-PNG textures are one .bin with every slice and level. Not done: EXR for float textures (still raw bytes, exact); file a new issue if wanted.

---

## 181: iOS build fails in MetalSprocketsPBR (Float16 unavailable)

+++
status: closed
priority: medium
kind: bug
labels: area:build, effort:s
created: 2026-10-23T14:27:56Z
updated: 2026-10-24T11:41:33Z
closed: 2026-10-24T11:41:33Z
+++

Found while working on #178. `xcb build -d ios` (generic/platform=iOS) fails before reaching SceneSprockets: MetalSprocketsPBR PBREnvironment.swift:26 and PBRHDROutput.swift:23 report "Float16 is unavailable in macOS", then MetalSprocketsGLTF and SceneSprocketsPBR cannot resolve MetalSprocketsPBR. The "macOS" in the message suggests an x86_64 macOS slice (Float16 is unavailable on Intel Macs) is being built. The simulator build fails anyway (no Metal 4). So the iOS-only code in SceneView (#178 two-finger gestures) has not been compiled for iOS.

- `2026-10-24T11:41:33Z`: Not reproducible. SceneSprockets, SceneSprocketsPBR, SceneSprocketsGizmos and the SceneSprocketsDemo app all build for generic iOS. Likely cause: 'xcb build -d ios' uses the default scheme (SceneSprocketsComposer, a macOS app with a macOS Quick Look extension). To check iOS: xcb build "SceneSprocketsDemo.xcodeproj/SceneSprocketsDemo" -d ios

---

## 182: Scene archive: save audio players and levels of detail

+++
status: closed
priority: medium
kind: feature
labels: effort:m, area:document
depends: 158
created: 2026-10-24T11:29:39Z
updated: 2026-11-07T15:54:11Z
closed: 2026-11-07T15:54:11Z
+++

Split from #162. Saving a scene still warns for these two node features. Audio players hold an AVAudioPCMBuffer and live in SceneSprocketsAudio, so the core archive needs a hook (or the audio file kept by reference). Levels of detail hold MetalMesh values, so they need the generated-mesh path from #158.

- `2026-11-07T15:54:12Z`: Fixed: scene archives save levels of detail (each level's distance, and its mesh as a mesh-codec file shared like node meshes; nil meshes kept) and audio players (each buffer as a CAF file in audio/, shared between players that share a buffer, plus loops and volume; position is set by SceneAudio each frame). Without a mesh codec, levels of detail are skipped with a warning. Tests: AudioAndDetailArchiveTests (both failed before the fix with the 'not saved yet' warning and nothing read back).

---

## 183: Composer: explode an imported glTF into scene graph nodes

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:composer
created: 2026-10-24T11:44:53Z
updated: 2026-11-04T20:59:42Z
closed: 2026-11-04T20:59:42Z
+++

Imported glTFs are kept as mostly complete units (#157), not edited in detail. Add an Explode command that converts an imported glTF node tree into plain scene graph nodes (meshes, materials, transforms), so they can be edited and are then saved as generated content (#158).

- `2026-10-24T15:08:18Z`: Punting: nothing to explode yet. The Composer has no glTF import, and GLTFSceneGraph already turns a glTF into plain nodes. Explode only makes sense once #157 tags imported nodes as one glTF unit kept by reference, and #158 can save the exploded meshes as generated content. Unblocker: do #157 (and decide where the glTF writer lives for #158), plus a Composer 'Import glTF…' command. Explode then removes the tag from the imported subtree.
- `2026-10-25T01:01:54Z`: Unblocked: #157/#158 now have a decided writer location (SceneSprocketsPBR).
- `2026-10-25T01:34:52Z`: Unblocked: #157 and #158 are done. Explode = clear the model root's modelSource (with undo); its subtree then saves as scene nodes with meshes through the glTF mesh codec (#158).

---

## 184: Composer: environment background looks closer than the grid

+++
status: open
priority: low
kind: task
labels: investigate, area:composer, effort:s
created: 2026-10-24T14:09:41Z
updated: 2026-10-24T14:18:19Z
+++

With the Studio environment as background, the grid looks like it runs past and under the environment's walls, so the environment seems nearer than the grid.

Checked so far: draw order is fine. SceneGraphRenderer adds the background first, and PBREnvironmentBackground draws with depth testing off, so the grid always draws over it.

My guess is perception: the Studio map shows a small room (floor, wall, corner), but the grid is an infinite plane with no distance fade, so it runs to the horizon at full brightness.

To investigate:
- Does a distance fade on GridShader (MetalSprocketsAddOns) fix it? It may need adding there.
- Does it still look wrong with an outdoor HDR?

- `2026-11-04T21:00:28Z`: Checked: GridShader in MetalSprocketsAddOns 0.2.x has no distance-fade option, so the likely fix is a change in that package (new fade parameters, tag, bump here), not in SceneSprockets. Punting: the bug is perceptual and needs a visual judgement in the running Composer (Studio vs an outdoor HDR, with and without a fade), which I cannot make from tests. Unblocker: OK to add a distance fade to GridShader in MetalSprocketsAddOns and use it in the Composer grid? And, if possible, check once with an outdoor HDR whether it still looks wrong.

---

## 185: Composer: save editor state in the document bundle next to scene.json

+++
status: closed
priority: medium
kind: feature
labels: area:composer, area:document, effort:m
created: 2026-10-24T14:12:32Z
updated: 2026-10-24T14:45:11Z
closed: 2026-10-24T14:45:11Z
+++

The Composer loses its editor state when a document is closed. Save it in the .scenesprocketsd bundle as its own file (for example editor.json) next to scene.json, so SceneArchive and other readers can ignore it.

Candidates:
- editor camera (matrix and orbit target)
- render settings (grid, axes, statistics, frame timing, shadows, field of view, clip planes)
- gizmo mode and space
- selection
- inspector visibility

ComposerDocument writes the bundle through SceneArchive into a temporary URL. The editor file can be added to that directory before the FileWrapper is made, and read back in init(configuration:). A missing or unreadable file must fall back to defaults.

---

## 186: Composer: add lights from the + menu

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T14:13:22Z
updated: 2026-10-24T14:27:53Z
closed: 2026-10-24T14:27:53Z
+++

The + menu adds only shapes. Add entries for directional, point and spot lights. Add the new light under the root, select it, and make it undoable, the same as EditorModel.addShape. Directional and spot lights point along the node's -Z, so give them a useful default rotation (for example angled down) and a useful default position.

---

## 187: Composer: add cameras from the + menu

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T14:13:23Z
updated: 2026-10-24T14:28:14Z
closed: 2026-10-24T14:28:14Z
+++

Add a Camera entry to the + menu. Add the new camera under the root, select it, and make it undoable, the same as EditorModel.addShape. Good default: place it at the current editor camera's transform so it looks at what the user sees. Related: choosing a scene camera as the preview's point of view.

---

## 188: Composer: draw debug shapes for lights and cameras

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T14:13:23Z
updated: 2026-10-24T14:50:29Z
closed: 2026-10-24T14:50:29Z
+++

Lights and cameras are invisible in the preview, so the user cannot see or click them. Draw debug shapes with MetalSprocketsAddOns' GraphicsContext3D / 3D canvas, as TransformGizmo does:
- directional light: arrow along -Z
- point light: small sphere or star, plus the range if it is finite
- spot light: cone from innerConeAngle and outerConeAngle
- camera: frustum from its projection

Draw the selected node highlighted. Add a Render settings toggle. Clicking a debug shape should select its node; mesh hit testing does not find these nodes.

- `2026-10-24T14:17:41Z`: Related: #132 (debug visualization modes in the renderer), #186 and #187 (adding lights and cameras; without these shapes they are invisible).
- `2026-10-24T14:18:20Z`: Related: #132 (debug visualization modes in the renderer), #186 and #187 (adding lights and cameras; without these shapes they are invisible).

---

## 189: Composer: app Settings window with a gizmo size option (large/small)

+++
status: closed
priority: low
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T14:14:41Z
updated: 2026-10-24T14:52:21Z
closed: 2026-10-24T14:52:21Z
+++

Add a Settings scene (Composer > Settings…) for app-wide preferences stored with @AppStorage, not in documents.

First setting: transform gizmo size, Large or Small. EditorModel sets gizmo.worldSize from the scene bounds (#171). Apply a multiplier on top of that, or a screen size if TransformGizmo supports one.

Later settings could include default render settings for new documents.

- `2026-10-24T14:17:41Z`: Related: #190 (the CollaborationKit auth settings go in this Settings window).
- `2026-10-24T14:18:20Z`: Related: #190 (the CollaborationKit auth settings go in this Settings window).

---

## 190: Composer: AI assistant panel in the sidebar with CollaborationKit

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T14:16:04Z
updated: 2026-10-24T15:19:41Z
closed: 2026-10-24T15:19:41Z
+++

Add CollaborationKit (github.com/schwa/CollaborationKit, local checkout at ~/Projects/Current/CollaborationKit) to the Composer:
- CollaborationChatView in the left sidebar, for example as a tab or a split under the scene tree.
- One ConversationStore / LLMSession per document.
- CollaborationSettingsView in the app Settings window (#189) for sign-in and model choice. Credentials go in KeychainCredentialStore and are shared through CollaborationCredentials in the environment.

Tools for the model are in a separate subtask.

- `2026-10-24T14:58:23Z`: Tried: added CollaborationKit 0.2.4 to SceneSprocketsComposerSupport, with an Assistant tab in the sidebar, a per-document ConversationStore and CollaborationSettingsView in Settings. Punting: SwiftPM cannot resolve the packages. CollaborationKit (0.2.4 and main) requires swift-syntax 602.x for its macros, and MetalSprockets requires swift-syntax 604.x. Unblocker: release a CollaborationKit that accepts swift-syntax 604 (for example from: "602.0.0" changed to "602.0.0"..<"605.0.0", or move to 604). Then this is mostly ready: the code was about 150 lines (AssistantPanel, settings tab, sidebar picker).

---

## 191: Composer: CollaborationKit tools to query and edit the scene

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:l
depends: 190
created: 2026-10-24T14:16:04Z
updated: 2026-10-24T15:44:19Z
closed: 2026-10-24T15:44:19Z
+++

Subtask of #190. Add @CollaborationTools / @CollaborationTool methods so the model can read and change the scene:
- query: list nodes (tree, ids, labels, kinds), get a node's transform, content, material and bounds, get the selection and the environment
- edit: add shapes, lights and cameras, delete, rename, set the transform, reparent, select, set environment and background

Make edits through EditorModel so they can be undone and the UI refreshes. Batch the changes from one assistant turn into one undo group if possible.

- `2026-10-24T15:05:09Z`: Punting: depends on #190, which is blocked. CollaborationKit needs swift-syntax 602.x and MetalSprockets needs 604.x, so the package cannot be added. Unblocker: a CollaborationKit release that accepts swift-syntax 604; then do #190 and this. Planned shape: @CollaborationTools on a small EditorModel adapter. Query: list nodes as path, label and kind; get a node's transform, content and bounds; get the selection and environment. Edit: add shape, light or camera, delete, rename, set transform, select. All edits go through the existing undoable EditorModel methods.
- `2026-10-24T15:19:41Z`: Unblocked: CollaborationKit 0.2.5 accepts swift-syntax 604, and #190 is done.

---

## 192: Composer: lock nodes

+++
status: closed
priority: low
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T14:16:05Z
updated: 2026-10-24T15:11:45Z
closed: 2026-10-24T15:11:45Z
+++

Add a lock toggle per node, in the tree row and the inspector. A locked node cannot be picked in the viewport, moved by the gizmo, or edited in the inspector. It can still be selected in the tree. Decide if the lock also applies to children. Save it as editor state (#185) or in the scene; probably editor state.

- `2026-10-24T14:17:41Z`: Related: #193 (hide/show). Show both toggles in the tree row.
- `2026-10-24T14:18:20Z`: Related: #193 (hide/show). Show both toggles in the tree row.

---

## 193: Composer: hide/show and enable/disable nodes

+++
status: closed
priority: low
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T14:16:05Z
updated: 2026-10-24T15:12:57Z
closed: 2026-10-24T15:12:57Z
+++

Add an eye toggle in the tree row and the inspector to hide and show nodes, using SceneGraph.Node.isVisible, which the archive already saves. Hidden nodes are not drawn and not hit-tested; show them dimmed in the tree. Decide if 'inactive' (also stops actions, constraints, particles and physics) is a separate state from 'hidden', like Unity's SetActive compared to a renderer toggle. Make changes undoable.

- `2026-10-24T14:17:41Z`: Related: #192 (lock nodes).
- `2026-10-24T14:18:20Z`: Related: #192 (lock nodes).

---

## 194: Composer: Quick Look thumbnail extension that returns Preview.png

+++
status: closed
priority: low
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T14:42:46Z
updated: 2026-10-24T15:49:29Z
closed: 2026-10-24T15:49:29Z
+++

Split from #175. Documents now contain Preview.png (DocumentPreview). Add a Quick Look thumbnail extension target (com.apple.quicklook.thumbnail, QLThumbnailProvider) that returns that PNG, so Finder icons show the scene. Needs a new Xcode target, which was not added in #175.

- `2026-10-24T15:49:29Z`: Added the SceneSprocketsThumbnail extension target (QLThumbnailProvider that draws Preview.png, aspect-fit). It builds, is embedded in the app and is sandboxed. No unit test: extension targets have no test target, and the code only reads the PNG with DocumentPreview.image (tested in #175) and draws it. Not checked at runtime: pluginkit -a did not register the DerivedData build, and qlmanage -t hung. To check: launch the built app once, then look at a saved .scenesprocketsd in Finder.

---

## 195: Debug views: PBR and Blinn-Phong material channels

+++
status: closed
priority: low
kind: feature
labels: area:renderer, effort:m
created: 2026-10-24T15:04:55Z
updated: 2026-10-24T15:52:21Z
closed: 2026-10-24T15:52:21Z
+++

Follow-up to #132. SceneGraphDebugMode covers geometry: shaded, normals, texture coordinates, UV checker, world position and wireframe. Material channels are not covered: base color, metallic, roughness, occlusion, emissive and others. MetalSprocketsPBR's PBRRenderer.debugView (PBRDebugView) already draws these for PBR. Pass a channel mode through SceneGraphRenderContext to PBRMaterialRenderer, and add a Blinn-Phong equivalent (diffuse, specular, shininess).

---

## 196: Composer: inactive nodes (pause actions, constraints, particles and physics)

+++
status: closed
priority: low
kind: feature
labels: area:composer, area:scenegraph, effort:m
created: 2026-10-24T15:12:57Z
updated: 2026-10-24T15:55:08Z
closed: 2026-10-24T15:55:08Z
+++

Split from #193. Hide/show (Node.isVisible) is done. A separate 'inactive' state, like Unity's SetActive, would also stop the subtree's actions, constraints, particles and physics, not just drawing. It needs a scene graph flag that advanceActions, applyConstraints, particles and SceneSprocketsPhysics respect. Decide whether inactive implies hidden.

---

## 197: Composer: Insert Model File… (glTF, USDZ, OBJ)

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T15:15:29Z
updated: 2026-10-24T15:40:48Z
closed: 2026-10-24T15:40:48Z
+++

Add an Insert Model File… command (+ menu and Scene menu) that picks a file and adds its contents to the open scene under the selected node, or under the root when nothing is selected. Select the new subtree, and make it one undo step.

Loaders already exist in SceneSprocketsPBR: GLTFSceneGraph for .gltf/.glb, and ModelIOSceneGraph for the formats Model I/O reads (.usdz, .usd, .obj, .ply, .stl). Optionally scale or frame the result to fit the scene.

Saving: generated meshes are not saved yet (#158), and glTF by reference is #157. Until then, inserted meshes may be skipped with a warning when saving, so decide whether to block saving or warn. Related: #183 (explode imported glTF).

- `2026-10-24T15:35:19Z`: Related: #183 (explode), #157 (glTF by reference) and #158 (write generated meshes).

---

## 198: Composer: basic material editing in the inspector

+++
status: closed
priority: high
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T15:15:46Z
updated: 2026-10-24T15:37:48Z
closed: 2026-10-24T15:37:48Z
+++

Mesh nodes show no material in the inspector, and new shapes always get a plain grey Blinn-Phong material. Add a Material section for mesh nodes:
- type picker: Blinn-Phong, PBR (and ShaderMaterial presets such as normals and rim, read-only)
- Blinn-Phong: diffuse, ambient and specular colors, shininess
- PBR: base color, metallic, roughness, emissive
- a few presets (plastic, metal, rubber, glass) as a quick start

Use ColorPicker with linear conversion, as SceneInspectorView's background color does. Edits are undoable and keep textures already on the material; editing textures is out of scope. For multi-material meshes, edit the material of each submesh.

---

## 199: Composer assistant: environment, reparenting and one undo step per turn

+++
status: closed
priority: low
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T15:44:27Z
updated: 2026-10-24T16:34:30Z
closed: 2026-10-24T16:34:30Z
+++

Follow-up to #191. SceneTools does not cover these yet:
- get and set the environment and background (SceneGraph.Environment: background kind and color, map, intensity, rotation)
- reparent a node (needs an undoable EditorModel move)
- group everything the assistant changes in one turn into a single undo step (ConversationStore turn start and end, or snapshotProvider as Phosphor uses it for rollback)

- `2026-10-24T16:12:44Z`: Narrowed by triage: reparenting is in #202 (update parent) and one undo step per turn is #203. What is left here is the environment and background tools.
- `2026-10-24T16:27:43Z`: #202 added update(parent:) for reparenting (EditorModel.reparent, undoable). Only the environment and background tools are left here.

---

## 200: AI mode: batch repeated operations into one job

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, effort:s
created: 2026-10-24T15:47:44Z
updated: 2026-10-24T16:29:46Z
closed: 2026-10-24T16:29:46Z
+++

Requests like "make 8 spheres" currently run 8 separate make-node tool calls. AI mode needs a way to batch jobs (e.g. a count/array parameter or a batch tool) so repeated operations run as one call.

- `2026-10-24T16:12:44Z`: Depends on #202: batching is the create tool's count/array parameter there. Do #202 first.

---

## 201: AI mode: support selection-aware edits like "align the selected objects"

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:l
created: 2026-10-24T15:48:37Z
updated: 2026-10-24T16:33:02Z
closed: 2026-10-24T16:33:02Z
+++

AI mode should handle requests that act on the current selection, e.g. "align the selected objects". Needs: (1) tools to read the app's UI selection, (2) tools to edit existing nodes (transforms etc.), not just create them.

- `2026-10-24T16:12:44Z`: The Composer has single selection only (EditorModel.selection is one node ID). 'Selected objects' needs multiple selection in the tree, the viewport (shift-click) and the gizmo first, then tools that read and set the selection set. Related: #202 (select tool).

---

## 202: AI mode: minimal composable tool set (query/select/create/update/delete)

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T15:49:26Z
updated: 2026-10-24T16:27:43Z
closed: 2026-10-24T16:27:43Z
+++

Keep AI tools few and composable instead of one tool per operation. Proposed set:
- query: read scene graph + current selection (names, types, transforms, bounds)
- select: set selection by node IDs
- create: add nodes; supports count/array for batching (#200)
- update: set properties on one or more nodes (transform, material, name, parent, visibility)
- delete: remove nodes
The model composes these for align/distribute/grid/recolor etc. Add specialized helpers only if the model struggles with a common op. Related: #200, #201.

---

## 203: AI mode: each AI turn is a single undo step

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, effort:s
created: 2026-10-24T15:49:27Z
updated: 2026-10-24T16:24:36Z
closed: 2026-10-24T16:24:36Z
+++

All edits made by one AI response should be grouped into a single undo action, so one Undo reverts the whole request (e.g. "make 8 spheres" or "align selected"). Related: #200.

- `2026-10-24T16:12:44Z`: Overlaps #199 (third point), which now points here.

---

## 204: Composer: crash when saving on quit (MainActor.assumeIsolated in snapshot)

+++
status: closed
priority: critical
kind: bug
labels: area:composer, area:document, effort:s
created: 2026-10-24T16:07:51Z
updated: 2026-10-24T16:17:25Z
closed: 2026-10-24T16:17:25Z
+++

Quitting with unsaved changes crashes with EXC_BREAKPOINT in dispatch_assert_queue, from ComposerDocument.snapshot(contentType:) at ComposerDocument.swift:70.

Cause: snapshot calls MainActor.assumeIsolated to write editor.json (#185) and Preview.png (#175). That assumes SwiftUI always takes the snapshot on the main thread, which is wrong. When saving on quit, AppKit runs -[NSDocument writeSafelyToURL:...] on a background queue (com.apple.root.default-qos), and ReferenceFileDocumentBox.snapshotForSerialization calls snapshot there. The main thread is blocked meanwhile in NSDocument _waitForUserInteractionUnblocking, so hopping to the main actor synchronously would deadlock.

Note: the scene archive write in the same function also reads the live scene graph off the main thread. The comment 'on the main actor' is wrong in this path.

Possible fix: capture what the save needs on the main actor ahead of time, and keep snapshot free of main-actor access. For example, update a stored editor state and a rendered preview image when the document changes or on the save action. Or render the preview on a background-safe path (DocumentPreview uses Metal only, plus SceneGraph reads). Regression test: call snapshot(contentType:) from a detached task or background queue and check that it returns.

---

## 205: Composer: multiple selection follow-ups (gizmo, inspector, saving)

+++
status: closed
priority: low
kind: enhancement
labels: area:composer, effort:m
created: 2026-10-24T16:33:01Z
updated: 2026-10-24T17:31:12Z
closed: 2026-10-24T17:31:12Z
+++

Follow-up to #201. Multiple selection works in the tree (Cmd and Shift click), in the viewport (Shift-click), for outlines, Delete and the assistant tools. Still single-node:
- the gizmo moves only the primary selection; it should move all selected nodes around a shared pivot
- the inspector shows only the primary node; it could edit shared fields (visibility, material color) for all of them
- editor.json saves only the primary selection (selectionPath); save all as paths

---

## 206: Composer: inserting a .gltf fails in the sandbox (external .bin), and the warning alert overflows the screen

+++
status: closed
priority: high
kind: bug
labels: area:composer, effort:m
created: 2026-10-24T16:51:08Z
updated: 2026-10-24T17:15:29Z
closed: 2026-10-24T17:15:29Z
+++

Insert Model File… on a .gltf with an external buffer (gltf-research-scenes/scenes/glass-of-water/gltf/glass_of_water.gltf) loads none of its meshes. Every primitive is skipped with: NSCocoaErrorDomain 257 'The file glass_of_water.bin couldn't be opened because you don't have permission to view it' (NSPOSIXErrorDomain 1, Operation not permitted). Screenshot: ~/Desktop/Screenshot 2026-10-24 at 12.50.15@2x.png.

Cause: the app is sandboxed (ENABLE_USER_SELECTED_FILES = readonly). The file importer grants access only to the chosen .gltf, not to the .bin and textures next to it. .glb works because it is one file.

Fix options:
- ask for the folder: when a .gltf refers to files outside its own bytes, show an open panel for its folder (or let the importer pick folders) and read within that security scope
- declare the sibling types as related items (NSIsRelatedItemType in CFBundleDocumentTypes) and open them through NSFileCoordinator with a file presenter (primaryPresentedItemURL); Apple's documented approach for sidecar files
- or copy the .gltf and its referenced files with a folder-scoped grant

Second problem in the same screenshot: the alert shows every warning in full, one per primitive with the whole NSError description, so it is taller than the screen and the OK button is off-screen. Show a summary instead: one line per distinct problem with a count (for example '17 meshes skipped: no permission to read glass_of_water.bin'), cap the list, and log the full text.

- `2026-10-24T17:04:01Z`: Related: #197 (Insert Model File).
- `2026-10-24T17:15:29Z`: Fixed the way the MetalSprocketsGLTF GLTFViewer demo does it: a .gltf whose buffers or images are separate files (ModelFile.needsFolderAccess) gets a second folder importer that opens in its folder, then loads with the folder's security scope. The alert now summarizes warnings (InsertWarnings), and the full text goes to the log. No unit test for the sandbox grant itself: tests do not run in the App Sandbox. The detection, folder check and summary are tested. Please check by inserting glass_of_water.gltf in the app.

---

## 207: Composer: top-level Default Camera and Default Lighting rows in the scene tree

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T16:53:27Z
updated: 2026-10-24T17:24:42Z
closed: 2026-10-24T17:24:42Z
+++

The scene tree has a top-level Scene row next to the root (scene settings). Add two more top-level rows: Default Camera and Default Lighting. They are editor objects, not nodes in the scene graph.

- Default Camera: the editor camera (EditorModel.camera, RenderSettings field of view and clip planes). Selecting it shows those settings in the inspector, and could also show the camera's transform and a 'Frame All' button. Today they are split between the Render tab and camera control.
- Default Lighting: the light added at the camera when the scene has no lights (RenderSettings.usesDefaultLighting, SceneView .autoenablesDefaultLighting). Selecting it shows the on/off toggle and, if added, its intensity and color. It should say whether it is active (it turns off as soon as the scene has a light).

Selection: extend SceneTreeView's Item enum (scene, node) with defaultCamera and defaultLighting, and make NodeInspectorView switch on it. Decide whether these settings leave the Render tab or appear in both places. Saved in editor.json like the other render settings.

- `2026-10-24T16:54:07Z`: Decided: move the camera and default lighting settings out of the Render tab. They live only in the Default Camera and Default Lighting inspectors.

---

## 208: Composer: edit every PBR material parameter in the inspector

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T16:56:05Z
updated: 2026-10-24T17:21:11Z
closed: 2026-10-24T17:21:11Z
+++

The Material section (#198) edits only base color, metallic, roughness and emissive. Expose every PBRMaterialUniforms value (MetalSprocketsPBR PBRShaderTypes.h), grouped in disclosure groups so the common ones stay on top:
- Base: base color with alpha, metallic, roughness, emissive color and emissiveStrength, unlit
- Alpha: alphaMode (opaque, mask, blend) and alphaCutoff; doubleSided
- Maps: normalScale, occlusionStrength (only matter with textures)
- Transmission and volume: transmissionFactor, thicknessFactor, attenuationDistance (infinity toggle), attenuationColor, ior, dispersion, volumeScatter, multiscatterColorFactor
- Diffuse transmission: diffuseTransmissionFactor, diffuseTransmissionColorFactor
- Specular: specularFactor, specularColorFactor
- Clearcoat: clearcoatFactor, clearcoatRoughnessFactor, clearcoatNormalScale
- Sheen: sheenColorFactor, sheenRoughnessFactor
- Iridescence: iridescenceFactor, iridescenceIor, iridescenceThicknessMinimum and Maximum (nm)
- Anisotropy: anisotropyStrength, anisotropyRotation (degrees in the UI)
- Other: retroreflectionFactor; specularGlossiness and glossinessFactor (legacy KHR_materials_pbrSpecularGlossiness)
Skip internal values: hasTangents, hasNormals, isPointOrLine and the texture slots.

Use EditorModel.editedPBR so edits stay undoable and keep textures. Sliders need ranges from the glTF extension specs. Changing alphaMode or doubleSided may change PBRMaterial.renderState and batching. The assistant's update tool (#202) could take the same fields later. Scene archives already save uniforms field by field (#163).

- `2026-10-24T17:04:01Z`: Related: #198 (basic material editing).

---

## 209: Composer: light inspector

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T17:47:53Z
updated: 2026-10-24T17:53:00Z
closed: 2026-10-24T17:53:00Z
+++

Selecting a light node shows only Node and Transform, plus spot cone angles for spot lights. Add a Light section that edits every Light field: type (directional, point, spot), color (linear, ColorPicker), intensity, range (with an infinite toggle; point and spot only), and inner and outer cone angles (spot only, keep the existing AngleEditor). Also show the light's categoryBitMask if lights use one. Edits go through EditorModel.setLight, so they stay undoable. Inner cone must stay at or below outer. Disabled when the node is locked. Possibly add 'casts shadows' if SceneGraphShadows gets per-light settings (#88).

---

## 210: Composer: Drop to Floor command

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T17:47:53Z
updated: 2026-10-24T17:56:01Z
closed: 2026-10-24T17:56:01Z
+++

Add a 'Drop to Floor' command (Scene menu, node context menu, maybe a shortcut) that moves each selected node down or up so the bottom of its world bounds sits at y = 0. Keep x and z. Use SceneGraph.worldBounds(of:) and adjust the local translation through the parent's world transform, so nested and rotated nodes land correctly. Apply it to every selected, unlocked node in one undo step (EditorModel.editSelection). Skip nodes without bounds (empty nodes, lights, cameras). Optional later: drop onto the nearest mesh below with a downward hit test instead of y = 0. Also expose it to the assistant (an update option or its own tool).

---

## 211: Composer: show bounding boxes

+++
status: closed
priority: low
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T17:47:54Z
updated: 2026-10-24T17:58:33Z
closed: 2026-10-24T17:58:33Z
+++

Add a Render settings toggle 'Bounding Boxes' that draws world-space bounding boxes as wireframe boxes: for the selected nodes (always, or with the toggle), and optionally for every mesh node. Draw with MetalSprocketsAddOns GraphicsContext3D in the scene pass decorations, as DebugShapes does (#188). Use SceneGraph.worldBounds(of:); hidden or inactive nodes have none. Selected boxes in the accent color, others faint. Saved in editor.json with the other render settings.

- `2026-10-24T17:50:16Z`: Related: #188 (DebugShapes draws the same way).

---

## 212: SceneGraph.flattened() mutates an observed property, crashing SwiftUI when statistics are shown

+++
status: closed
priority: high
kind: bug
labels: area:scenegraph, area:ui, effort:xs
created: 2026-10-24T18:07:22Z
updated: 2026-10-24T18:35:44Z
closed: 2026-10-24T18:35:44Z
+++

Composer crashed with 'AttributeGraph precondition failure: setting value during update' when the Statistics overlay was on.

Stack: SceneView.body, the statistics TimelineView closure (SceneView.swift:237), then SceneGraph.statistics (Queries.swift:22), then SceneGraph.flattened(initialTransform:), then SceneGraph.traversalCount.modify, then ObservationRegistrar.willSet, then GraphHost.flushTransactions, then AG precondition_failure.

Cause: SceneGraph is @Observable, and traversalCount (SceneGraph.swift:204, incremented at :213) is a tracked stored property. flattened() bumps it on every traversal, so any SwiftUI view that reads statistics or flattens the graph during a view update writes an observed property mid-update. SwiftUI forbids that.

Fix: mark traversalCount @ObservationIgnored. It is a diagnostics counter, not view state. Check for other bookkeeping properties on SceneGraph or Node that change while being read (caches, revision counters touched from getters) and do the same.

Regression test: read sceneGraph.statistics inside withObservationTracking and check onChange does not fire. Better, observe the graph and call flattened() and check no change is reported.

The other log lines (DetachedSignatures, ViewBridge error 18, NSColorPicker pasteboard, SmartNameSuggestions 'no importer for io.schwa.scenesprockets-document') look like system noise and are unrelated.

---

## 213: Composer: Insert Model File for a .gltf should explain and offer to pick the resource folder

+++
status: closed
priority: high
kind: bug
labels: area:composer, effort:s
created: 2026-10-24T18:29:52Z
updated: 2026-10-24T18:39:44Z
closed: 2026-10-24T18:39:44Z
+++

Follow-up to #206. Picking a .gltf whose buffers and images are separate files gives no clue why its resources did not load. #206 sets isChoosingFolder = true right after the first file importer returns, to show a second, folder-only importer. In practice the user sees nothing useful. My guess, unverified: the second importer does not appear because it is presented while the first one is still dismissing. The insert then never happens, or happens without its resources.

Wanted: right after the .gltf is picked, show an alert:
- title: 'Allow Access to the Model's Folder'
- message: '<file> loads <n> other files (buffers, textures) from its folder. macOS only lets the app read them if you choose that folder.'
- buttons: 'Choose Folder…' (opens the folder importer in the file's folder, as now) and 'Cancel'
On Cancel, either insert nothing, or insert with the missing resources and say clearly what was skipped. Choose one; skipping the insert is simpler and less surprising.

Also: if the folder importer is cancelled or the wrong folder is chosen, say so in the alert instead of failing silently. Present the folder importer from the alert's button action, not the first importer's completion, so it cannot be swallowed. Count the referenced files with the same JSON scan as ModelFile.needsFolderAccess, so the message can give the number.

- `2026-10-24T18:32:38Z`: Related: #206 (folder access).
- `2026-10-24T18:39:44Z`: Done: after picking a .gltf with separate files, an alert ('Allow Access to the Model's Folder') says how many files it loads. Choose Folder… opens the folder importer from the alert's button. Cancel, a cancelled panel and a wrong folder each give a clear message, and nothing is inserted. Tested: ModelFile.externalFiles and the alert texts. The alert and importer sequence is UI and untested; please try it with glass_of_water.gltf. Unverified: whether SwiftUI calls the folder importer's completion on cancel. The cancel message is checked a turn later to cover both orders.

---

## 214: Gizmo and overlays flicker: probably a Metal 4 synchronization problem (barriers)

+++
status: closed
priority: high
kind: bug
labels: area:renderer, area:ui, effort:m
created: 2026-10-24T18:30:46Z
updated: 2026-10-25T01:00:44Z
closed: 2026-10-25T01:00:44Z
+++

The transform gizmo started flickering in the Composer. Likely a Metal 4 hazard: Metal 4 does not track resource hazards or order passes, so every read-after-write between passes, and between frames, needs an explicit barrier. Not confirmed yet; needs a GPU capture of a bad frame. Ruled out so far: GraphicsContext3DRenderPipeline makes new buffers instead of rewriting them, and ParameterSet retains (makes resident) bound buffers per submission (ParameterSet.swift:244). Uniforms are bound by value.

Per-frame pass order in SceneView: shadow and post passes (compute), then the scene pass (meshes plus decorations: grid, axes, light/camera shapes #188, bounding boxes #211, all GraphicsContext3D or mesh-shader draws), then the overlay hook (SelectionOutline: JumpFloodOutlinePipeline, compute passes over the scene depth, then compositing into the drawable), then ManipulatorOverlayPass (gizmo, mesh shaders, loads drawable color).

Things to check:
1. ManipulatorOverlayPass (SceneViewManipulator.swift:93) has QueueBarrier(after: [.fragment, .dispatch], before: .fragment). The gizmo strokes are mesh-shader draws (object and mesh stages) and the fills are vertex draws. Do color attachment loads, or anything before .fragment, need covering? Should 'before' include .vertex, .object and .mesh?
2. Selection outline to manipulator: JumpFloodOutlinePipeline ends with .barrierAfterPass(after: .dispatch, beforeQueueStages: [.fragment]). Check that the composite into the drawable is fully ordered before the manipulator's load. A blit or render stage might be missing from 'after'.
3. Across frames: when an overlay is set, the scene depth texture is .private and stored (SceneView: metalDepthStencilStorageMode(needsPostPasses || overlay != nil ? .private : .memoryless)). The same depth texture is reused every frame, so frame N+1's scene pass may clear and write it while frame N's outline compute still reads it. Metal 4 does not order separate command buffers on one texture. Needs a barrier or fence at frame start, or a depth texture per frame in flight. The same applies to any other persistent textures: shadow maps, the SelectionOutline jump-flood textures (kept between frames), post-processing targets.
4. Scene-pass decorations draw with depthCompare .always; check none of them read a texture written earlier in the frame without a barrier.
5. Do MetalSprockets' MeshRenderPipeline stages count in QueueBarrier's stage sets (MTLStages .object and .mesh)?

How to confirm: capture a flickering frame (using-gpucapture) and look at the Manipulator pass inputs. Also try with the selection outline off, then with Lights and Cameras off and Bounding Boxes set to None, to see which overlay is involved. Turn on Metal API validation and the Metal 4 shader validation hazard checks if available.

Probably belongs partly in MetalSprockets: a missing frame-to-frame barrier for persistent attachments in RenderView. Move or split the issue once the cause is known.

\- `2026-10-24T18:42:53Z`: Found and fixed two missing barriers by reading the code; no GPU capture yet.
1. The scene pass waited only for dispatch before clearing the depth texture shared by all frames in flight. The previous frame's selection outline and manipulator passes use that depth attachment in the fragment stage, so a new frame could clear depth while the gizmo was still depth-testing. That is gizmo flicker; it applies whenever depth is stored, and the Composer always stores it because it sets an overlay. The barrier now waits for [.dispatch, .fragment].
2. The Selection Mask pass had no barrier while clearing and writing the mask texture, which is kept between frames and still read by the previous frame's jump flood (dispatch) and outline (fragment). That is outline flicker. Added QueueBarrier(after: [.dispatch, .fragment], before: .fragment).
Checked and looked fine: the manipulator pass barrier (its gizmo geometry is CPU-written buffers, made resident per submission); jump flood's own barriers (its first one waits for vertex, fragment, dispatch and blit, and the seeds texture is covered); the outline pass ordering after jump flood.
Leaving open until you confirm the flicker is gone. If it is not, a capture of a bad frame (using-gpucapture) is next. Unverified: whether MTLStageFragment covers attachment load and store actions in Metal 4. If not, those barriers may need more stages.

\- `2026-10-24T21:23:27Z`: GPU capture analysis (~/Desktop/SceneSprocketsComposer.gputrace, 5 frames, M5 Max). The capture includes the a83c9a8c barriers. Per frame: Shadow Casters x7, PBR Transmission Scene, Transmission Mipmaps, scene pass, Selection Mask, JumpFlood, Selection Outline, Manipulator. Barriers decoded:
- scene pass: after dispatch+fragment before vertex+fragment
- Selection Mask: after dispatch+fragment before fragment
- JumpFlood: after vertex+fragment+dispatch+blit before dispatch, ends with dispatch to fragment
- Selection Outline: covered by JumpFlood's end barrier
- Manipulator: after dispatch+fragment before fragment
Shadow Casters have no start barrier, but shadow maps are per submission (depthTexture(forSubmission:)), so frames cannot collide there.
Replayed images: the Manipulator output is pixel-identical in all 5 frames and the gizmo draws correctly. Replay serializes the GPU work, so a timing hazard would not show in it anyway.
No remaining missing barrier found. Open questions: does the flicker still happen with this build? If so, when (always, on hover highlight, while dragging, when toggling overlays)? Next suspects are CPU-side: frames where manipulatorOverlay returns nil (viewport nil, or overlay(viewport:) throws, which is swallowed by try?), or @MSState being matched to the wrong GraphicsContext3DRenderPipeline when the decorations (DebugShapes, BoundingBoxes) appear or disappear and shift element positions.

- `2026-10-25T01:00:39Z`: User confirmed the flicker no longer reproduces. Likely fixed by the barriers added in a83c9a8c; root cause not separately confirmed.

---

## 215: Composer: frame rate drops sharply while dragging

+++
status: closed
priority: high
kind: bug
labels: area:composer, area:ui, effort:m
created: 2026-10-24T18:31:12Z
updated: 2026-10-24T22:13:29Z
closed: 2026-10-24T22:13:29Z
+++

The frame rate drops a lot while dragging, at least with the gizmo; camera orbit not checked yet. Cause not measured yet. Profile first (Instruments Time Profiler plus SwiftUI, and the Frame Timing overlay's CPU phases) before changing anything.

Suspects from the code, unverified:
- every gizmo onChange bumps EditorModel.transformRevision, which every inspector, tree row and helper reads (localTRS, isVisible, isHidden, materials...), so most of the UI re-evaluates each frame of the drag
- ComposerView has .onChange(of: model.editorState) (#204), and editorState is computed: selectedNodes and lockedPaths each walk the whole graph (nodesWithWorldTransforms), plus path lookups. It runs on every body evaluation and then copies the state into the document under a lock
- DebugShapes, BoundingBoxes and the selection outline rebuild their GraphicsContext3D geometry or jump-flood passes every frame while things move
- multi-selection drags (#205) set worldTransform on companions every change, and each set walks parents
- ScenePreviewView recreates the decorations and overlay closures every body pass
- statistics (if on) flatten the whole graph every 0.5 s (#212)

Fix direction: keep drag updates out of SwiftUI's view graph (separate the drag revision from the observed transformRevision, or throttle UI refresh during a drag), make editorState cheap or update it only on drag end, and cache geometry that does not change. Add a benchmark: N nodes, a simulated gizmo drag for M frames, measure main-thread time.

- `2026-10-24T18:32:38Z`: Related: #212 (statistics flatten the graph) and #214 (overlays rebuilt every frame).
- `2026-10-24T18:44:45Z`: Measured the model-side work of one drag frame (DragPerformanceTests.dragFrameCosts; debug build, 500 boxes, 3 selected), in ms per call: continueGizmoDrag 0.005, editorState 1.36 (ComposerView recomputes it on every body pass via onChange(of: model.editorState)), selectedNodes 0.28, isHidden x500 0.11, DebugShapes 0.008, bounding boxes All 1.18, statistics 0.22. About 3 ms in total, so it does not explain a precipitous drop. The likely cost is SwiftUI: every drag step bumps transformRevision, which the tree rows (isHidden, isVisible, lock), the inspector and the decorations closures all read, so the whole sidebar List and inspector re-render every frame. That needs an Instruments trace to confirm. Punting until then. Unblocker: an Instruments trace (SwiftUI and Time Profiler templates) of a 5-second gizmo drag in a scene of about 100 nodes, or permission to change transformRevision into a separate drag counter that only the inspector's transform fields read. Also worth doing anyway: make editorState cheaper (1.4 ms per body pass).
- `2026-10-24T22:02:37Z`: Related: the new issue on closure-based Binding(get:set:) defeating diffing. The tree's List(selection:) and SceneView's camera binding are the likely hot spots.
- `2026-10-24T22:13:29Z`: Confirmed fixed by the user after ed10afff (#223): the tree List's closure selection binding and the rows' dependency on transformRevision were the cause. #224 has the remaining, smaller re-render sources.

---

## 216: Assistant batching isn't happening

+++
status: closed
priority: medium
kind: bug
labels: area:composer, effort:s
created: 2026-10-24T18:34:15Z
updated: 2026-10-24T19:00:06Z
closed: 2026-10-24T19:00:06Z
+++

- `2026-10-24T18:51:13Z`: Triage reading: the model still makes repeated single create and update calls (for example 8 creates) instead of create(count:) or translations / update(translations:), which exist since #200. Likely fix: say so in the tool descriptions and the system prompt (#218); maybe also accept per-node labels and colors.

---

## 217: Telling assistant to make models into glass doesn't work

+++
status: closed
priority: medium
kind: bug
labels: area:composer, effort:s
created: 2026-10-24T18:34:16Z
updated: 2026-10-24T19:08:24Z
closed: 2026-10-24T19:08:24Z
+++

- `2026-10-24T18:51:13Z`: Triage reading: the assistant cannot set transmission or the glass preset. update and setMaterial only take color, metallic and roughness, and MaterialPreset.glass is not reachable from the tools. Fix: a material preset option (plastic, metal, rubber, glass) and transmission and ior fields on update.

---

## 218: Expand the assistant system prompt

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, effort:s
created: 2026-10-24T18:35:54Z
updated: 2026-10-24T19:12:31Z
closed: 2026-10-24T19:12:31Z
+++

AssistantPanel.systemPrompt (SceneSprocketsComposerSupport/AssistantPanel.swift) is short. Expand it to cover:

- The assistant's skills/tools and when to use each.
- Lighting and shadows: how to light a scene well and use shadows.
- Use the "drop to floor" feature when it makes sense, so models don't clip through the floor.
- When creating many models, spread them out; don't stack them all at the origin.
- Aim for creative, good-looking scenes (composition, color, materials).
- Prefer PBR materials over other shaders.

Related: #216 (batching), #217 (glass materials).

---

## 219: Add File > Import menu for models

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:xs
created: 2026-10-24T18:37:07Z
updated: 2026-10-24T19:19:01Z
closed: 2026-10-24T19:19:01Z
+++

Add an Import item to the File menu that imports glTF/GLB and other model formats into the open scene.

---

## 220: Add right-click context menu to the main view

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:s
created: 2026-10-24T18:37:26Z
updated: 2026-10-24T19:24:46Z
closed: 2026-10-24T19:24:46Z
+++

- `2026-10-24T18:51:13Z`: Triage reading: right-clicking in the 3D view should open a context menu for the node under the pointer (selecting it first): Drop to Floor, Hide, Lock, Delete, Frame; and Add when clicking empty space.

---

## 221: Group nodes

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T18:37:26Z
updated: 2026-10-24T19:28:42Z
closed: 2026-10-24T19:28:42Z
+++

- `2026-10-24T18:51:13Z`: Triage reading: Group (Cmd-G) wraps the selected nodes in a new empty parent at their common parent, keeping world transforms; Ungroup (Shift-Cmd-G) moves the children up and removes the empty group. Undoable.

---

## 222: Reorder nodes

+++
status: closed
priority: medium
kind: feature
labels: area:composer, effort:m
created: 2026-10-24T18:37:27Z
updated: 2026-10-24T19:40:01Z
closed: 2026-10-24T19:40:01Z
+++

- `2026-10-24T18:51:13Z`: Triage reading: drag rows in the scene tree to reorder siblings and to reparent, through EditorModel.reparent with an index (undoable, cycles refused, world transform kept). Maybe also Move Up/Down commands.

---

## 223: Composer: closure-based Binding(get:set:) defeats SwiftUI diffing; views re-render every update

+++
status: closed
priority: high
kind: bug
labels: area:composer, area:ui, effort:m
created: 2026-10-24T22:02:37Z
updated: 2026-10-24T22:11:12Z
closed: 2026-10-24T22:11:12Z
+++

Binding(get:set:) holds closures, which SwiftUI cannot compare. A child view that receives one is always seen as changed, so its body re-runs (and usually its children's) on every parent update. The Composer has 34 of them.

Per file, and whether it is likely hot during a drag:
- MaterialSection.swift: 9, yes (the inspector re-renders on transformRevision)
- NodeInspectorView.swift: 7, yes (name; visible, active and locked toggles; transform fields via trs and component and eulerDegrees)
- SceneInspectorView.swift: 6, no (only with nothing selected)
- MultipleSelectionSection.swift: 4, yes with several nodes selected
- LightSection.swift: 4, yes when a light is selected
- ComposerView.swift: 2, alert presentation only
- SceneTreeView.swift: 1, HOT: List(selection: listSelection) gets a new closure binding every body pass, and every row also reads transformRevision (isHidden, isVisible, isLocked), so the whole tree likely re-runs every drag frame
- ScenePreviewView.swift: 1, HOT: SceneView(cameraMatrix: Binding(get: { model.camera.matrix }, set: ...)). The decorations and overlay closures passed to SceneView likewise make SceneView's body (and RenderView setup) re-run on every model change

Fix direction:
- Bind directly to stored model properties with @Bindable key paths (.camera.matrix; a stored list selection set synced with selectedIDs) instead of computed closure bindings. Key-path bindings compare equal.
- Keep unavoidable conversion bindings (degrees, colors, Euler angles, per-component vectors) inside small leaf views, so only the leaf re-runs.
- For SceneView: let its closure parameters be stable (an Equatable wrapper keyed on settings and selection), or move decorations and overlay into objects with identity.
- Together with splitting transformRevision (#215), so rows and toggles stop depending on drag steps.

Measure before and after with the SwiftUI instrument (body update counts during a gizmo drag) and DragPerformanceTests. Not verified yet; found by code inspection while investigating #215.

- `2026-10-24T22:11:12Z`: Fixed the hot spots: the tree's List selection is a key-path binding (EditorModel.treeSelection), SceneView's camera binding is a key path (viewCameraMatrix), and tree rows and the Default Lighting row read visibilityRevision, so a drag step no longer reaches them (tested with withObservationTracking). The rest (inspector leaf views, SceneView's closures) is in a follow-up issue.

---

## 224: Composer: remaining closure bindings: inspector leaf views and SceneView's decorations and overlay closures

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, area:ui, effort:m
created: 2026-10-24T22:11:12Z
updated: 2026-10-25T00:08:04Z
closed: 2026-10-25T00:08:04Z
+++

Follow-up to #223, which fixed the hot spots: the tree's List selection is now $model.treeSelection, SceneView's camera is $model.viewCameraMatrix, and tree rows read visibilityRevision instead of transformRevision.
Left:
- The inspector's Binding(get:set:) conversions (NodeInspectorView trs, component and eulerDegrees; MaterialSection; LightSection; MultipleSelectionSection). Move each into a small leaf view that takes the node and model and builds its binding inside, so only the leaf re-runs. The inspector must update during a drag anyway, so this matters less.
- SceneView's decorations and overlay parameters are closures created in ScenePreviewView's body, so SceneView never compares equal and its body re-runs on every model change. Options: Equatable wrapper values keyed on what they capture (settings, selected ids, revisions), or overlay and decoration objects with identity held by the model.
Measure with the SwiftUI instrument during a drag.

- `2026-10-24T23:49:33Z`: House-rules review adds to this issue: SceneInspectorView has 6 closure bindings (background, color, blur, rotation) and ComposerView has 2 alert isPresented bindings. Use .alert(_:isPresented:presenting:) or item-based alerts. Approach for the inspectors: writable computed properties on EditorModel (for example selectedLight, selectedMaterial(at:)), projected with Binding($model.optional) and key paths, instead of the binding(_:), trs, component and eulerDegrees helpers. Hiding a closure binding in a helper does not make it stable.
- `2026-10-24T23:51:39Z`: Related: #231 (SceneView's camera binding; this issue covers its decorations and overlay closures) and #233 (struct extraction, which can carry the leaf-binding work).
- `2026-10-25T00:08:04Z`: Fixed the inspector and alert bindings. All Binding(get:set:) uses in the Composer are gone. New InspectorProperties.swift adds writable properties and subscripts on EditorModel (selected node, light, multiple selection, materials, environment with an undo action name) and on value types (linearColor, [double:], rotationDegrees, Light cones, isPresent), projected with $model and key paths. The SceneView decorations, overlay and onTapAt closures are a library API design question, split out to #235. The 'measure with the SwiftUI instrument' step was not done. Tests: inspectorPropertiesEditTheSelection, lightConePropertiesKeepInnerInsideOuter.

---

## 225: Composer: option to hide individual axis lines (the green Y line)

+++
status: closed
priority: low
kind: enhancement
labels: area:composer, effort:xs
created: 2026-10-24T22:18:31Z
updated: 2026-10-24T22:26:57Z
closed: 2026-10-24T22:26:57Z
+++

The Y axis line (green) runs straight up through the scene and gets in the way. Add per-axis toggles in Render > Show (X, Y, Z, or a 'Ground Axes Only' option that hides Y), saved in editor.json.
Depends on MetalSprocketsAddOns 'AxisLinesRenderPipeline: choose which axes to draw'. Until then it can pass yAxisColor with alpha 0, because the shader discards alpha-0 fragments, from RenderSettings.decorations.

---

## 226: Composer: show bounding box min, max and size in the inspector

+++
status: closed
priority: low
kind: enhancement
labels: area:composer, effort:xs
created: 2026-10-24T22:22:44Z
updated: 2026-10-25T00:12:42Z
closed: 2026-10-25T00:12:42Z
+++

Selecting a node shows no size information. Add a Bounds section (or rows under Transform) with world-space min [x, y, z], max [x, y, z] and size (max - min), from SceneGraph.worldBounds(of:); also the center. Read-only, with 3 decimals. 'None' for nodes without bounds (empty, light, camera, hidden or inactive). With several nodes selected (#205), show the combined bounds. Must refresh while dragging, so it reads transformRevision; keep it in its own leaf view so it does not make the rest of the inspector depend on drags (#223, #224). Optionally also local-space bounds (Node.subtreeBounds).

---

## 227: ComposerDocument.snapshot reads and renders the live scene graph off the main thread

+++
status: closed
priority: high
kind: bug
labels: area:composer, area:document, effort:m
created: 2026-10-24T22:32:50Z
updated: 2026-10-25T00:41:38Z
closed: 2026-10-25T00:41:38Z
+++

From a concurrency review. ComposerDocument is @unchecked Sendable, and snapshot(contentType:) runs on a background queue when saving on quit (#204). There it encodes sceneGraph (an @Observable class the main actor mutates) with SceneArchive, and renders it with DocumentPreview. It is safe today only because AppKit blocks the main thread during that save; the types do not guarantee it, and other save paths (autosave, Save As while editing) are unverified.
Fix: capture an immutable snapshot on the main actor whenever an undoable edit lands, or right before saving (the encoded bundle data and textures plus the preview PNG), behind the existing lock pattern used for the editor state (updateEditorState). snapshot then only builds the FileWrapper from that capture and never touches the live graph. This needs SceneArchive to encode to data or a temporary directory on the main actor.
Test: change the scene, call snapshot from a detached task while the main actor keeps mutating the graph; with Thread Sanitizer, no race is reported and the saved scene matches the captured state.

\- `2026-10-24T23:51:40Z`: Related: #232 (editor state copied on every body pass).
\- `2026-10-25T00:01:03Z`: Punted (auto-issue-fixer). Investigated: snapshot builds the whole bundle (SceneArchive.write to a temp dir, including copied model files and textures) and renders Preview.png on the GPU. A capture taken on the main actor therefore costs a full save plus a render. The quit-save path calls snapshot off-main with the main thread blocked (#204), so snapshot cannot hop to the main actor without deadlocking, and SwiftUI has no clean 'about to save' hook to capture just before. Options:
(a) Capture the full bundle and preview on the main actor after each undo group closes, coalesced to once per runloop turn. Safe and simple, but every edit pays a save plus a render, which is slow for big glTF scenes.
(b) Build live when snapshot runs on the main thread (normal Save and autosave). Use the last capture from (a) only off-main, so captures are needed only when an app quit might happen; still per-edit cost unless lazily dirtied.
(c) Capture only the cheap parts (encoded scene JSON plus editor state) per edit, and copy model files and textures and render the preview in snapshot from immutable inputs. Needs SceneArchive split into encode on main and write files anywhere, plus a preview built from a copied graph.
Unblocker: which trade-off do you want? I suggest (c), it's the most work but has no per-edit GPU cost.

- `2026-10-25T00:33:42Z`: User chose option (c): capture the cheap parts after each edit, then write files and the preview at save time. Done together with #238.

---

## 228: AnimatedMaterial is @unchecked Sendable mutable state without a lock

+++
status: closed
priority: medium
kind: bug
labels: area:scenegraph, area:assets, effort:s
created: 2026-10-24T22:32:50Z
updated: 2026-10-25T00:03:41Z
closed: 2026-10-25T00:03:41Z
+++

From a concurrency review. SceneSprocketsPBR/GLTFSceneGraph.swift:387: AnimatedMaterial has 'var state' and is mutated from AnimationClip.Property.set, which writes state and material.uniforms. Property is Sendable with @Sendable get and set closures, so clips can cross threads, and two players applying the same material at once race on state and uniforms.
Options: (a) protect state with Mutex<PBRMaterial.AnimatedState> and write uniforms from the locked result; (b) if animation is only applied on one thread (main or render), drop Sendable and @Sendable from AnimationClip.Property. Its closures take a non-Sendable Node, so @Sendable adds no safety, and it is what forces @unchecked here. (b) is more honest; check every caller of Property.get and set and AnimationPlayer before choosing.

- `2026-10-25T00:03:41Z`: Fixed with option (b). AnimationClip.Property and Path are no longer Sendable and their get/set closures are no longer @Sendable. AnimationClip itself was already non-Sendable and no caller relied on sending these. The built-in properties became static computed vars, because a static let of a non-Sendable type is not allowed. AnimatedMaterial dropped @unchecked Sendable. No unit test: the change is to type checking, and the compiler now rejects the race. Core, Composer and Demo build, and all tests pass.

---

## 229: Composer app and extensions build in Swift 5 language mode

+++
status: closed
priority: medium
kind: task
labels: area:composer, effort:s
created: 2026-10-24T22:32:50Z
updated: 2026-10-25T00:09:20Z
closed: 2026-10-25T00:09:20Z
+++

From a concurrency review. The SceneSprocketsComposer, SceneSprocketsQuickLook and SceneSprocketsThumbnail targets use SWIFT_VERSION = 5.0 (pbxproj and SceneSprocketsComposer-Shared.xcconfig), while the packages they use build in Swift 6 mode. Swift 6 data-race checking is off for the app entry point, PreviewViewController and ThumbnailProvider. Set SWIFT_VERSION = 6.0 for all three targets, fix any diagnostics, and keep SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor for the app.

---

## 230: Composer: replace the Task.yield ordering hack in the folder importer

+++
status: closed
priority: low
kind: bug
labels: area:composer, effort:xs
created: 2026-10-24T22:32:51Z
updated: 2026-10-25T00:11:39Z
closed: 2026-10-25T00:11:39Z
+++

From a concurrency review. ComposerView's folder importer (#213) reports 'not inserted' on cancel from .onChange(of: isChoosingFolder) by starting Task { @MainActor in await Task.yield(); ... }, hoping the importer's completion has run by then. yield() does not guarantee that, so a successful pick can still show the cancel message first. Replace it with state: store the importer result, or drop the separate cancel message for the panel and keep only the alert's explicit Cancel. Avoid unstructured tasks for ordering.

- `2026-10-24T23:51:40Z`: Related: #213 (introduced the hack).
- `2026-10-25T00:11:39Z`: Fixed with fileImporter's onCancellation callback (the allowsMultipleSelection variant) instead of onChange + Task.yield. No unit test: the file panel can't be driven from tests. Verify by hand: insert a .gltf with external buffers, choose Cancel in the folder panel; then repeat and pick the right folder (no cancel message should appear).

---

## 231: SceneView: closure-based camera binding rebuilt every body pass

+++
status: closed
priority: high
kind: bug
labels: area:ui, effort:s
created: 2026-10-24T23:49:32Z
updated: 2026-10-24T23:58:47Z
closed: 2026-10-24T23:58:47Z
+++

From a SwiftUI house-rules review. SceneView.cameraBinding (SceneView.swift around line 368) is a Binding(get:set:) rebuilt on every SceneView body pass and passed to CameraControl. SceneView re-runs whenever its parent changes (constantly in the Composer), and closure bindings break SwiftUI's diffing, so camera control and its gesture state get rebuilt. This is in the library, so it affects every app.
Fix: keep one @State camera matrix as the source of truth in SceneView. Pass $camera to CameraControl. Sync the external binding with onChange in both directions, guarded against loops. Measure with the SwiftUI instrument during an orbit in the Composer before and after.

- `2026-10-24T23:51:39Z`: Related: #224 (SceneView's decorations and overlay closures).
- `2026-10-24T23:58:47Z`: Fixed: CameraControl now takes $controlledCameraMatrix (a stable @State). Two onChange handlers sync it with the external or internal camera, guarded against echo loops. No unit test: binding identity across SwiftUI body passes can't be reached from a unit test. Verified by building the core, the Composer and the Demo, and by the existing test suites.

---

## 232: ComposerView recomputes editorState (a full graph walk) on every body pass

+++
status: closed
priority: high
kind: bug
labels: area:composer, area:ui, effort:s
created: 2026-10-24T23:49:33Z
updated: 2026-10-25T00:00:30Z
closed: 2026-10-25T00:00:30Z
+++

From a SwiftUI house-rules review. ComposerView has .onChange(of: model.editorState, initial: true) { document.updateEditorState() }. editorState is computed: selectedNodes and lockedPaths each walk the whole graph. Measured at 1.36 ms per call with 500 nodes (DragPerformanceTests). It runs on every ComposerView body evaluation. Body must stay fast and side-effect free.
Fix: add an editorStateRevision to EditorModel, bumped by every setter that changes saved editor state (camera, render settings, gizmo mode and space, selection, locks, inspector visibility, sidebar), and observe that instead. Or call document.updateEditorState() from those model methods through a callback.

- `2026-10-24T23:51:39Z`: Related: #227. Both are about how editor and scene state reach the document; one capture point on the main actor could serve both.

---

## 233: SwiftUI structure: turn stateful private some View sections into View structs

+++
status: closed
priority: medium
kind: task
labels: area:composer, area:demo, effort:s
created: 2026-10-24T23:49:33Z
updated: 2026-10-25T00:10:48Z
closed: 2026-10-25T00:10:48Z
+++

From a SwiftUI house-rules review ('private var foo: some View is generally an anti-pattern'). Extract into View structs, since these read several properties or have behavior:
- Composer SceneInspectorView: backgroundSection, environmentSection become BackgroundSectionView, EnvironmentSectionView
- Composer ScenePreviewView: contextMenuItems becomes ScenePreviewContextMenuView(model:pointer:)
- Demo NodeInspectorView: generalSection, transformSection, contentSection, cameraSection become ...SectionView
Leave as is: AssistantPanel.missingCredentials (static, no inputs) and SceneNodeRow.row (tiny fragment).

- `2026-10-24T23:51:40Z`: Related: #224 and #234 (conventions cleanup in the same files).

---

## 234: SwiftUI conventions cleanup: View suffixes, NSEvent, padding, previews

+++
status: closed
priority: low
kind: task
labels: area:composer, area:demo, area:ui, effort:s
created: 2026-10-24T23:49:33Z
updated: 2026-10-25T00:15:49Z
closed: 2026-10-25T00:15:49Z
+++

From a SwiftUI house-rules review.
- View suffix: MultipleSelectionSection, LightSection, MaterialSection, AssistantPanel, AddShapeMenu, GizmoToolbarContent (or make it a ToolbarContent type) in the Composer; SceneNodeRow, VectorRow, ColorRow in the Demo.
- ScenePreviewView.isExtendingSelection reads NSEvent.modifierFlags. Use SwiftUI's onModifierKeysChanged to track EventModifiers instead: no AppKit and no #if.
- Hard-coded spacing and padding: SceneView statistics overlay .padding(4) and .padding(8); ComposerView sidebar picker .padding(8); Demo NodeInspectorView HStack(spacing: 8) and (spacing: 6). Keep the color swatch frame. Comment why CodePanel forces a font size (slide code).
- NodeInspectorView ForEach(0..<materialCount, id: \.self) over a range that changes size: iterate materials.indices or give slots stable ids.
- Previews for leaf views: LightSection, MaterialSection, MultipleSelectionSection, DefaultCameraInspectorView, DefaultLightingInspectorView, Demo SceneNodeRow, VectorRow, ColorRow, CodePanel.
The Task.yield hack is #230.

- `2026-10-25T00:15:49Z`: Done. Renamed 9 types plus their files to add the View suffix (word-boundary sed). NSEvent replaced with onModifierKeysChanged, stored in the unobserved PointerTracker. Outer paddings now use the default; the statistics badge keeps its 4 pt inset, with a comment. Demo spacings dropped. CodePanel's font size is commented. The materials ForEach uses indices. Previews added: LightSectionView, MaterialSectionView, MultipleSelectionSectionView, DefaultCamera and DefaultLighting inspectors, Demo VectorRow and ColorRow, CodePanelView. Skipped: SceneNodeRowView (needs a DemoScene) and a FolderAccessRequest preview (alert content). Check by hand that Shift-click still extends the selection: onModifierKeysChanged may need the view to be focused.

---

## 235: SceneView: decorations, overlay and onTapAt closures make SceneView never compare equal

+++
status: closed
priority: medium
kind: enhancement
labels: area:ui, area:composer, effort:m
created: 2026-10-25T00:07:58Z
updated: 2026-10-25T14:08:02Z
closed: 2026-10-25T14:08:02Z
+++

Split out of #224. ScenePreviewView builds SceneView's decorations, overlay and onTapAt closures in its body, so SceneView never compares equal and its body re-runs on every model change. This is a library API design change. Options: (a) Equatable wrapper values keyed on what the closures capture (settings, selected ids, revisions); (b) decoration and overlay objects with identity held by the model, passed by reference. Measure with the SwiftUI instrument during a gizmo drag before choosing.

\- `2026-10-25T00:33:41Z`: Related: #240 (picking and viewport module would replace these closures' viewport rebuilding).
\- `2026-10-25T00:42:28Z`: Punted (auto-issue-fixer) with a recommendation not to do this as written. What I checked: ScenePreviewView's body reads renderSettings, camera (for camera.target), sceneGraph, selectedIDs and selectedNodes. It does not read transformRevision.
- Gizmo drag: only transformRevision changes, so ScenePreviewView and SceneView do not re-run, closures or not.
- Camera orbit: model.camera changes every frame, so ScenePreviewView re-runs. But SceneView must re-run anyway, because its camera binding's value changed.
- Settings or selection changes: the closures really do change (they capture settings and selected ids), so SceneView should re-run.
Making the closures Equatable (keyed wrappers) or turning them into objects would be a public API change with no hot path to gain. It also wouldn't make SceneView equal, since renderers, manipulator, delegate and Camera are existentials.
Not measured with Instruments; this is from reading what each body observes.
Unblocker: OK to close as won't-fix? A cheap related tweak: pass cameraTarget so the preview doesn't observe all of model.camera, if orbit-time body cost ever shows up in a profile. #240 (picking and viewport) covers the closures' duplicated viewport maths.

\- `2026-10-25T14:08:02Z`: Done at the user's request (the earlier punt recommended won't-fix).
- SceneView gains closuresID: AnyHashable? (last init parameter, source compatible) and an isolated '@MainActor Equatable' conformance. Equal only when closuresID is non-nil and equal, and every other input matches:
  - objects by identity (scene graph, point of view, delegate, shadows, audio, manipulator);
  - renderers through Equatable (BlinnPhong and ShaderMaterial renderers are now Equatable; PBRMaterialRenderer by identity; any other renderer counts as changed);
  - cameras by mask, projection matrix and reverse Z; the camera binding by value; fog/post-processing presence captured at creation, because body reads it.
- Composer: ScenePreviewView passes ScenePreviewClosuresID (render settings, selected ids, display scale, outline color, which is everything its closures capture by value) and applies .equatable(). RenderSettings is now Hashable.
- Found along the way: RenderSettings.shadows created a new SceneGraphShadows on every read, so the preview got fresh shadow state on every update. EditorModel now keeps one instance.
Tests: SceneViewEquatableTests (equal with the same inputs and id; unequal for nil or different ids, options, new shadows, camera value, renderer). Not measured with Instruments; body skips happen when ScenePreviewView re-runs with nothing SceneView uses changed.

---

## 236: Architecture: one edit/undo path for scene changes

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, architecture, effort:l
created: 2026-10-25T00:27:37Z
updated: 2026-10-25T00:47:21Z
closed: 2026-10-25T00:47:21Z
+++

From an architecture review (deepening candidate 1).
Cluster: EditorModel's ~15 setters (each registers its own undo and bumps revision counters), editSelection, gizmo drag begin/continue/end, AssistantTurnUndo (swaps the undo manager), SceneTools' string-based edits, InspectorProperties.
Problem: every edit path must remember the same steps: register undo, group it, set an action name, bump the right revision, skip locked nodes. #215, #223 and the test-runner undo-grouping crashes came from this. The same operations exist three times (direct setters, inspector properties, assistant tools).
Dependency category: in-process.
Direction: one deep editing module (for example apply(edit, actionName:)) that owns undo, grouping, lock rules and change notification. Callers describe the change.
Tests: replace the per-setter 'X undoes' tests with boundary tests: apply an edit, undo it, assert on the scene and the change notification.
Next step: run the improve-codebase-architecture interface-design step, then write an RFC.

\- `2026-10-25T00:33:42Z`: Related: #237 (design together: the edit path is the natural owner of change notification), #239.
\- `2026-10-25T00:47:21Z`: Design and implementation:
- EditorModel.perform(actionName, affecting: SceneAspects, change, revert:) is the one way to change the scene undoably. It runs change, calls notify(aspects), and registers revert as the undo step; redo re-runs change. change and revert never register undo themselves.
- EditorModel.transaction(actionName) { ... } groups several performs into one step. It replaces the hand-written begin/end grouping in the gizmo drag end, group, ungroup, move up/down, editSelection and drop to floor.
- notify(_ aspects:) is now the only place that bumps transformRevision, visibilityRevision and environmentRevision. SceneAspects is transform, visibility, label, content, structure, environment; the aspect-to-revision map lives in one function, which sets up #237. bumpRevision() is removed.
- Rewritten: setEnvironment, setTransform, setLocked, setVisible, setActive, delete, insert, reparent, setLabel, setLight, setMaterial. Every registerUndo call outside AssistantTurnUndo is gone.
Behavior changes: rename and structural edits now also bump visibilityRevision, so tree rows refresh. Delete, insert and reparent now notify. Group places the new node before inserting it, so no stray transform undo.
Tests: transformChangeUndoes is replaced by SceneEditBoundaryTests.editUndoesAndRedoes, a parameterized test over 13 kinds of edit. Each case checks that the saved scene.json changes, that undo restores it byte for byte, that redo re-applies it, that the undo name is right and that a revision moved. The case-specific tests (hidden subtree, locked nodes, assistant turn) stay, because they check more than undo.
Not done: SceneTools and InspectorProperties already go through the setters, so they get this for free; no separate rewrite was needed.

---

## 237: Architecture: scene change observation instead of manual revision counters

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, area:scenegraph, architecture, effort:l
created: 2026-10-25T00:27:38Z
updated: 2026-10-25T00:49:49Z
closed: 2026-10-25T00:49:49Z
+++

From an architecture review (deepening candidate 2).
Cluster: SceneGraph.Node (not observable, SceneSprockets #155), EditorModel.transformRevision and visibilityRevision, '_ = transformRevision' and '_ = localTRS(of:)' reads written only to make views update, editorState's graph walks, ComposerDocument.attach's withObservationTracking.
Problem: nodes don't announce changes, so every reader must know which counter to read and every writer which counter to bump. A missing bump leaves a view stale; a too-broad read makes it lag (#215, #223, #232).
Dependency category: in-process.
Direction: a deep change-tracking module, either in the library (observable or revisioned nodes per aspect: transform, visibility, content) or in the editor as the single owner of mutations (pairs with the edit/undo issue).
Tests: replace the counter-bump tests and parts of DragPerformanceTests with 'change X, readers of X see it, readers of Y don't re-run' tests.
Related: #155.

\- `2026-10-25T00:33:42Z`: Related: #236.
\- `2026-10-25T00:49:49Z`: Design call: the change tracking lives in the editor, not the library.
Why not observable nodes in SceneSprockets (#155): the renderer reads node properties for every node every frame. Observation registrar calls on those hot paths cost something for every app, and nothing outside the editor needs it. After #236 every undoable edit goes through EditorModel.perform, so the editor can be the single owner of change notification.
Implemented: one private revision per SceneAspects aspect (transform, visibility, label, content, structure, environment). observe(_ aspects:) is the only reader and notify(_ aspects:) the only writer. The '_ = transformRevision' and '_ = localTRS' reads are gone; readers say what they depend on: localTRS .transform; materials and selectedLight .content; isVisible, isActive and isDefaultLighting .visibility (plus structure and content where needed); bounds transform+visibility+content+structure; the tree observes .structure via outlineRoots and labels via displayName(of:).
Fixes along the way: the tree now refreshes on add, delete and move and on rename (before, it relied on the selection changing). Material and light edits no longer re-run views that only show transforms.
Remaining direct mutations: gizmo drags (notify(.transform) in continueGizmoDrag) and the temporary set-and-restore in reparentKeepingWorldTransform and dropToFloor (restored before returning).
Tests: SceneEditBoundaryTests now checks notification through withObservationTracking. New observersOnlySeeTheirAspect. treeRowStateIgnoresDrags still passes.

---

## 238: Architecture: document save as a main-actor capture plus a thread-free writer

+++
status: closed
priority: medium
kind: enhancement
labels: area:composer, area:document, architecture, effort:l
created: 2026-10-25T00:27:38Z
updated: 2026-10-25T00:41:38Z
closed: 2026-10-25T00:41:38Z
+++

From an architecture review (deepening candidate 3).
Cluster: ComposerDocument (@unchecked Sendable, lock, savedEditorState), SceneArchive.write, EditorState (path encoding), DocumentPreview rendering, the off-main save on quit.
Problem: snapshot needs the live graph (main actor), file I/O, a GPU render and the editor state, in one function that can run on any thread. #227 is punted on this; #204 and #232 also touched it.
Dependency category: local-substitutable (temporary directory, system default Metal device).
Direction: split into a cheap immutable capture made on the main actor and a writer that runs on any thread (files plus preview). See #227 option (c).
Tests: replace the round-trip tests (documentRoundTrips, editorStateRoundTrips, preview tests) with capture-then-write tests, plus 'capture is unaffected by later edits'.
Related: #227, #204, #232.

\- `2026-10-25T00:33:42Z`: Related: #227. User chose option (c); #227 will be fixed as part of this.
\- `2026-10-25T00:41:38Z`: Done together with #227, in one commit. They are one change.
Design: SceneArchive.capture(_:textureCache:) encodes the graph on the owning thread into a Sendable Capture (scene.json data plus texture file data). Capture.write(to:) writes it on any thread, and SceneArchive.write is now capture plus write. MTLTexture is not Sendable, so the capture holds texture bytes, not textures. A TextureCache keyed by texture identity reads each texture back from the GPU once, so later captures only re-encode JSON.
ComposerDocument.attach captures after every undo group close, undo or redo of the editor's undo manager, coalesced to once per main-actor turn.
snapshot: on the main thread it captures fresh and renders the preview from the live graph. Off the main thread it writes the last capture and renders the preview from the bundle it just wrote, so it never touches the live graph.
Limits: an edit with no undo step (mid-drag) is not in an off-main save until its undo step lands. The off-main preview misses anything the archive cannot save (#157/#158).
Tests: offMainSnapshotSavesTheCapturedScene (failed before the fix: saved the live label), captureIsUnaffectedByLaterEdits (core), and snapshotWorksOffTheMainThread now uses attach.

---

## 239: Architecture: one material editing module (PBR rebuild, kinds, presets, parameters)

+++
status: closed
priority: low
kind: enhancement
labels: area:composer, area:materials, architecture, effort:m
created: 2026-10-25T00:27:38Z
updated: 2026-10-25T00:54:19Z
closed: 2026-10-25T00:54:19Z
+++

From an architecture review (deepening candidate 4).
Cluster: MaterialEditing.editedPBR (rebuilds PBRMaterial with the device, 5 callers), MaterialKind conversions, MaterialPreset, PBRParameters tables, MaterialSectionView, SceneTools' material update, setBaseColor.
Problem: the PBR material is a class whose uniforms are mutated in place and shared with the renderer. Each caller re-implements 'copy, change, rebuild, set with undo'; the inspector, the assistant and multiple selection each have their own route.
Dependency category: local-substitutable (system default Metal device).
Direction: a material editing module that takes value-level edits (property, kind, preset, color) and returns or applies the rebuilt material through the edit/undo path.
Tests: replace the separate material-type, preset, PBR-edit and glass tests with one 'edit material property, check the result and undo' suite.

\- `2026-10-25T00:54:18Z`: Design and implementation: edits are values, applied in one place.
- MaterialEdit enum: kind, preset, baseColor, uniforms (closure), doubleSided, blinnPhong (closure). MaterialEdit.applying(_ edits:to:device:) applies a list to one material and returns the new material, or nil if nothing applied.
- It works on a draft, so PBR uniform and double-sided changes pile up and the PBRMaterial is rebuilt once, keeping textures and render state. Edits that don't fit (uniforms on Blinn-Phong, color on a textured diffuse, kind already set) are skipped.
- EditorModel.editMaterials(of:at:actionName:_:) throws, builds every edited material first, then sets them in one transaction (one undo step, nothing changed on error).
- Callers moved: inspector material subscripts (kind, uniforms, double-sided, Blinn-Phong), the preset menu, setBaseColor (multiple selection) and SceneTools' material update (previously ~40 lines of its own conversion and rebuild logic). Only MaterialEdit calls editedPBR and converted now.
Behavior: SceneTools applying a preset and metallic/roughness now rebuilds the PBR material once instead of twice. Kind on the same kind is a no-op, where it used to rebuild PBR and drop textures.
Tests: materialEditsApplyAsValues replaces materialEditsReplaceAndUndo (kind, skip rules, combined PBR edits that keep textures, presets with color, glass). A preset+uniforms case was added to the edit/undo boundary test. Existing PBR-parameter and glass tests pass unchanged.

---

## 240: Architecture: one picking and viewport module for clicks, menus, decorations and gizmo

+++
status: closed
priority: low
kind: enhancement
labels: area:composer, area:ui, architecture, effort:m
created: 2026-10-25T00:27:38Z
updated: 2026-10-25T00:57:38Z
closed: 2026-10-25T00:57:38Z
+++

From an architecture review (deepening candidate 5).
Cluster: SceneView onTapAt hit test, DebugShapes.hitTest, EditorModel.node(at:viewSize:), SceneViewport built in 3 places, gizmo hit filters, decoration and overlay closures (#235).
Problem: clicking, the context menu and decorations each rebuild the camera, projection and viewport and pick in their own order (light and camera shapes first, then meshes). The closures also stop SceneView comparing equal.
Dependency category: in-process.
Direction: one viewport and picking value (camera, projection, size, display scale) with pick(at:) that applies the shape-first rule; decorations and overlays take it instead of rebuilding it.
Tests: replace the DebugShapes hit tests and the Composer pick tests with pick-at-point tests at one boundary.
Related: #235, #220.

\- `2026-10-25T00:33:41Z`: Related: #235.
\- `2026-10-25T00:57:38Z`: Design and implementation: one viewport constructor, one editor picking function.
- Core: SceneViewport.init(cameraMatrix:camera:viewSize:drawableSize:) builds the viewport the way SceneView draws it, converting reverse-Z projections to standard depth. SceneView.viewport() and SceneView's own tap hit test both use it now (the hit test used to build a separate ViewProjection). New test viewportFromCameraCastsTheProjectionsRays checks it gives the projection's own rays for standard, reversed and reversed-infinite depth.
- Composer: EditorModel.viewport(viewSize:) and node(at:in:) hold the single pick rule (light and camera shapes first when shown, then the nearest mesh in the camera's category mask). Clicks (onTapAt) and the context menu (node(at:viewSize:)) both call it; ScenePreviewView no longer re-implements shape-first or uses SceneView's mesh hit. The context menu's viewport also now handles reverse-Z correctly (it used the raw projection matrix before; shape hits only used x and y, so no visible bug).
Not changed: the decorations closure still builds its viewport from the render context's matrices. That is the per-frame render camera, not a pick, so it stays. #235 (closures) stays punted.
Tests: the core test above; the existing nodeUnderPointer and debugShapesDrawAndPickLightsAndCameras pass.

---

## 241: Composer crashes in a SwiftUI force-unwrapped binding while the assistant builds a scene

+++
status: closed
priority: critical
kind: bug
labels: area:composer, area:ui, effort:s
created: 2026-10-25T03:57:17Z
updated: 2026-10-25T04:00:21Z
closed: 2026-10-25T04:00:21Z
+++

Repro (user): ask the assistant to create a scene. The app stops with EXC_BREAKPOINT on the main thread in SwiftUICore BindingOperations.ForceUnwrapping.get(base:), under ProjectedLocation.update chains (5 levels deep) during DynamicBody.updateValue / GraphHost.flushTransactions. No app frames in the backtrace; console noise (DetachedSignatures, ViewBridge) looks unrelated.
ForceUnwrapping is what Binding($optional) produces. When the optional becomes nil while a view still holds the unwrapped binding, reading it traps. Likely cause (not verified): the unwrapped bindings added in #224 (commit c7159c8f):
- NodeInspectorView: if let light = Binding($model.selectedLight)
- MaterialSectionView: Binding($model[materialKind: index]), Binding($model[blinnPhong: index, actionName:]), uniforms(_:) -> Binding($model[pbrUniforms: index, actionName:]); then projected further (dynamicMember, .linearColor, [double:]), which matches the nested ProjectedLocation frames.
These read the *selected* node. The assistant changes the selection and the materials (kind conversions, deletes) between view updates, so an inspector built for the old selection can re-read its binding after the value turned nil, for example a material that is no longer Blinn-Phong or PBR, or a selection that is no longer a light.
Fix direction: don't unwrap model-derived optionals with Binding($x). Give the subscripts non-optional values with a harmless default on get and a no-op set when missing (or key the sections by node id and material kind with .id(...) so they are rebuilt). Then reproduce with a test that changes the selection or material kind while a hosted inspector is alive, if one can be made to trap.

- `2026-10-25T04:00:21Z`: Fixed. The inspector no longer uses Binding($optional) on model-derived values. selectedLightForEditing and the materialKind, blinnPhong and pbrUniforms subscripts are non-optional: they read a default when the light or material is missing or of another kind, and writes then do nothing (MaterialEdit already skips edits that don't fit). The sections still decide whether to show from the optional values (selectedLight, model[material:]). New InspectorCrashTests host NodeInspectorView in an NSHostingView and change the light or material kind under it, then remove them. Before the fix the test process died with SIGTRAP (signal 5), the same trap as the report; after it, both pass. Not tried in the running app with the assistant.

---

## 242: Composer: pink garbage frames in complex scenes while the inspector is visible and the camera moves

+++
status: open
priority: high
kind: bug
labels: area:renderer, area:composer, effort:m
created: 2026-10-25T14:33:10Z
updated: 2026-11-04T20:44:59Z
+++

Video: '/Users/schwa/Shared/Desktop Stuff/Pink Bug.mov' (stays there until fixed). Scene: 114 meshes, 792,746 triangles, imported BMW glTF, PBR, no lights.
Observations (user):
- With the inspector hidden, complex scenes render fine while orbiting.
- With the inspector shown (second half of the video), complex scenes get pink garbage.
- When the camera stops (SwiftUI state stops updating), the pink stops.
- SwiftUI and AppKit compositing may use Metal 3; the renderer uses Metal 4.
What the video shows (frame scan at 30 fps from 6 s): only one corrupted frame, at about 7.17 s. The bottom ~2/3 of the viewport is tiled pink and black/white blocks with contour-like bands, while the top of the same frame (background, frame timing overlay) is correct. The tiling and the clean top band look like undefined texture memory being shown or sampled for part of the drawable, rather than a wrong shader color. That is a guess, not verified. FPS ~100 at the time (frame # ~36219).
Hypotheses to check, none confirmed:
1. Frame overlap or synchronization: when SwiftUI is busy (inspector re-rendering while the camera's @State changes), main-thread and Core Animation timing shift. A drawable, depth or intermediate texture could be presented or read before the Metal 4 queue finished writing it (missing waits or barriers between our passes and presentation). Related to #214's barrier work.
2. A shared intermediate texture (SelectionOutline targets, post-pass or depth copies, PBR prepass) reused by the next frame while the previous frame's GPU work or composition still reads it, with more than one frame in flight.
3. Memoryless or private depth: SceneView switches metalDepthStencilStorageMode and texture usage based on needsPostPasses or overlay. If a SwiftUI update flips those mid-flight (MTKView reallocates attachments), the next frame could see uninitialized memory. The inspector being visible means more SwiftUI updates; #235's equatable() may change how often SceneView re-runs.
Next steps: capture a GPU trace (gpucapture) during an orbit with the inspector visible and find the frame; turn on Metal API validation and shader validation; try maximumDrawableCount and frames-in-flight changes; log when MTKView attachment settings change; check whether disabling the selection outline, bounding boxes and statistics overlay avoids it.

\- `2026-10-25T14:51:25Z`: More info (user): it is much better in a Release build than in Debug, but still happens, much less often. My reading (not verified): this points at timing, not logic. Slower CPU-side work in Debug (Swift unoptimized SwiftUI and inspector updates, the per-frame scene walk, encoding) widens the window for a race, which fits a synchronization or reuse bug (hypotheses 1 and 2) more than a deterministic wrong state. Useful next check: make Release slower on purpose (sleep a few ms in the frame closure, or in SwiftUI updates) and see whether the rate goes back up.
\- `2026-10-25T15:45:31Z`: GPU capture analysis (/tmp/pinkcap/orbit.gputrace, Debug build, inspector visible, 120 frames):
- Each frame is one MTL4CommandBuffer (3 allocators, so up to 3 frames in flight) with passes: PBR Transmission Scene, Transmission Backdrop, Back Faces, Mipmaps, the main scene pass (drawable + MTKView depth), Selection Mask, JumpFlood, Selection Outline.
- PBR Transmission Scene (@tex10 RGBA16Float color, @tex11 depth), Selection Mask (@tex8) and MTKView depth (@tex7) are the same textures in every frame. Only the drawable alternates.
- Every pass starts with a Metal 4 queue barrier EXCEPT 'PBR Transmission Scene', the first pass of the frame. It clears and re-renders @tex10/@tex11 with nothing ordering it after the previous frame's main pass, whose fragment shaders sample @tex10, or the previous frame's mipmap and backdrop blits. Metal 4 does not order submissions on a queue, so under CPU load (Debug, busy SwiftUI) frames bunch up and overlap: a likely cause of the garbage. Fits all observations: timing-dependent, only while the camera moves (identical frames hide stale reads), only in scenes with transmission.
- Checked and fine: the GraphicsContext3D join buffer is created each frame and removed from the residency set 3 frames later (matches frames in flight); outline mask, JumpFlood and depth passes have queue barriers.
- The replayer failed to load the trace (XPC connection interrupted), so I could not fetch images of the bad frame from it.
Fix: MetalSprocketsPBR #22, commit 168a00f6 (local, not pushed): QueueBarrier(after: [.fragment, .blit], before: .fragment) at the start of the PBR Transmission Scene pass.
To finish: push MetalSprocketsPBR, update the MetalSprocketsPBR pin in the 4 Package.resolved files, re-test in Debug with the inspector visible, and re-capture to confirm the barrier is on the first pass.

- `2026-11-04T20:48:50Z`: Checked: the MetalSprocketsPBR fix (168a00f6, queue barrier before the PBR Transmission Scene pass) is pushed and included in MetalSprocketsPBR 0.0.3, which SceneSprockets already resolves (Package.resolved pins 693714e4, tag 0.0.3). No code change left here. Not closing: the bug is timing-dependent and needs a manual repro (Debug build, inspector visible, orbit the BMW scene). Unblocker: confirm the pink frames are gone, then close.
- `2026-11-07T15:49:55Z`: Autonomous run: re-checked. The resolved MetalSprocketsPBR checkout has QueueBarrier(after: [.fragment, .blit], before: .fragment) at the start of the PBR Transmission Scene pass (PBRTransmissionPass.swift:147), so the fix is in the build. Punting: the bug is timing-dependent and only reproduces by hand (Debug build, Composer inspector visible, orbiting the BMW glTF scene); no automated test can show it. Unblocker: run that repro once; if no pink frames appear, close.

---

## 243: README says Blinn-Phong supports only point lights, but it lights directional and spot lights

+++
status: closed
priority: low
kind: documentation
labels: effort:xs, area:docs
created: 2026-10-30T14:40:28Z
updated: 2026-11-04T21:00:41Z
closed: 2026-11-04T21:00:41Z
+++

README Limitations says: "The Blinn-Phong shader supports only point lights."

The Blinn-Phong fragment shader handles BLINN_PHONG_LIGHT_DIRECTIONAL and BLINN_PHONG_LIGHT_SPOT, and ShadowsDemo uses directional and spot lights with BlinnPhongSceneMaterial. A directional sun light renders correctly in an external app (TreeAppreciator).

Expected: the README matches the shader.

---

## 244: Package.swift uses local path dependencies, so external consumers resolve sibling checkouts

+++
status: closed
priority: medium
kind: none
labels: release
created: 2026-10-30T14:40:28Z
updated: 2026-11-01T22:36:24Z
closed: 2026-11-01T22:36:24Z
+++

Package.swift on main depends on MetalSprockets and MetalSprocketsPBR with `.package(path: "../MetalSprockets")` and `.package(path: "../MetalSprocketsPBR")`, marked "TEMP #242: local fix, do not commit". Commit 3fdd7a98 ("Switch to local package dependencies…") is on main.

A package outside the MetalSprockets folder can only use SceneSprockets through an absolute local path, and only on a machine with those sibling checkouts. TreeAppreciator (~/Projects/Scratch/TreeAppreciator) has to use `.package(path: "/Users/schwa/Projects/Current/MetalSprockets/SceneSprockets")`.

---

## 245: Deprecation warnings when building SceneSprockets

+++
status: closed
priority: low
kind: task
labels: effort:xs, area:renderer, area:ui
created: 2026-10-30T14:40:28Z
updated: 2026-11-04T21:00:18Z
closed: 2026-11-04T21:00:18Z
+++

Building a consumer app (Xcode 27.2) shows two warnings from SceneSprockets:

```
Sources/SceneSprockets/UI/SceneViewManipulator.swift:34: 'init(viewMatrix:projectionMatrix:isReversedDepth:viewSize:)' is deprecated: replaced by 'init(viewMatrix:projectionMatrix:isReverseZ:viewSize:)'
Sources/SceneSprockets/Renderer/SceneGraphRenderer.swift:333: 'reversedDepth' is deprecated: renamed to 'reverseZ'
```

---

## 246: Blinn-Phong ignores per-vertex colors

+++
status: closed
priority: low
kind: enhancement
labels: effort:s, area:renderer
created: 2026-10-30T14:40:29Z
updated: 2026-11-04T20:54:17Z
closed: 2026-11-04T20:54:17Z
+++

The Blinn-Phong vertex input has only position, normal and textureCoordinate. A mesh with a `.color(0)` attribute renders with the material colour only.

Procedural meshes with many colours (for example a low-poly tree with varied leaf shades) must be split into one submesh and one material per colour. TreeAppreciator uses about 15 submeshes per tree for this.

---

## 247: No gradient or procedural sky background without PBR

+++
status: closed
priority: low
kind: feature
labels: effort:m, area:renderer
created: 2026-10-30T14:40:29Z
updated: 2026-11-04T20:57:50Z
closed: 2026-11-04T20:57:50Z
+++

With only BlinnPhongMaterialRenderer, `SceneGraph.Environment.Background` can be `.none` or a flat `.color`. `.environment` needs a PBR environment map and the PBR renderer.

To get a sky gradient, TreeAppreciator draws an inside-out sphere mesh with an emission texture. That mesh is ordinary geometry, so it is fogged, counts in scene bounds and needs castsShadow false.

---

## 248: SceneView cannot show more than one scene graph or viewport in one view

+++
status: open
priority: low
kind: feature
labels: effort:l, area:ui
created: 2026-10-30T14:40:29Z
updated: 2026-11-04T20:45:00Z
+++

Comparing two scenes side by side (TreeAppreciator shows two trees with a shared camera) needs two SceneViews. Each one makes its own RenderView, drawable, shadow maps, particle runtimes and pipeline setup, so a new pair pays the setup cost twice.

SceneView has no way to draw several scene graphs into split viewports of one RenderView. SceneGraphElement inside a custom RenderView is possible, but then SceneView features (camera control, onTapAt with SceneViewport, actions, constraints, particles advance) must be rebuilt by hand.

- `2026-11-04T20:59:53Z`: Looked at SceneView (one RenderView, one SceneGraphElement, one camera/manipulator, onTapAt with one SceneViewport). Punting: this needs API design decisions the code cannot answer. (1) Shape of the API: a SceneView taking [(sceneGraph, camera, rect)] viewports, a separate MultiSceneView, or making SceneGraphElement + a reusable 'scene runtime' (actions/constraints/particles advance, tap handling) public so apps compose their own RenderView. (2) Camera control: shared camera across viewports (TreeAppreciator's case) vs per-viewport manipulators, and which viewport gets gestures. (3) Shared resources: one shadow map per viewport or reused across them; particle runtimes per scene graph. (4) onTapAt must report which viewport was hit. Unblocker: pick (1) and (2); the TreeAppreciator side-by-side case with one shared camera is a good first target.

---

## 249: Bundled third-party glTF assets have no license or attribution

+++
status: closed
priority: medium
kind: documentation
labels: area:docs, release
created: 2026-11-01T22:28:08Z
updated: 2026-11-01T22:36:24Z
closed: 2026-11-01T22:36:24Z
+++

Demo/Packages/SceneSprocketsDemos/Sources/SceneSprocketsDemos/Resources/ contains Fox.glb and DiffuseTransmissionPlant.glb. They appear to come from the Khronos glTF sample models, which can carry attribution-required licenses (e.g. CC-BY).

Nothing in the repo (README, LICENSE, or a NOTICE/credits file) states their source, authors, or licenses. This blocks a public open-source release.

---

## 250: SceneGraph storage is not shared with ECS-based apps (SwiftECS backend umbrella)

+++
status: closed
priority: low
kind: feature
labels: umbrella, area:scenegraph, effort:xl, has-subtasks
depends: 263, 264, 265, 266, 267, 268, 269
created: 2026-11-04T19:49:40Z
updated: 2026-11-05T23:02:28Z
closed: 2026-11-05T23:02:28Z
+++

Umbrella issue: move SceneGraph storage onto SwiftECS, mostly hidden behind the current API.

## Goals

- Keep the public API (`SceneGraph`, `Node`, properties, traversal) working for most users without changes.
- Give ECS-based apps direct access to the underlying `World`. They can attach their own components to scene entities and run systems over them.
- Let the renderer and simulation use ECS queries instead of tree traversal where that helps.

## Reasoning

- `Node` already acts like an entity with optional parts: content, light, camera, physics body, skin, morph data, particles, audio, LOD, actions. These map naturally to components.
- SwiftECS has a `ChildOf` relationship that can model the hierarchy.
- Today, apps built around an ECS must mirror their state into the scene graph by hand. A shared storage removes that duplication.

## Known problems to resolve

- Toolchain: SwiftECS requires Swift 6.4. SceneSprockets is on tools 6.2.
- Observation: `Node` is `@Observable`. Direct writes to the `World` do not notify SwiftUI.
- Revisions and transactions are updated in `Node` `didSet`. Direct ECS writes skip them, so caches, revisions and undo can go stale.
- Identity: `Node` is a reference type with a weak `parent` and `ObjectIdentifier` ids. The mapping between entities and nodes, and node lifetime after entity destruction, is undefined.
- Child order: `children` is ordered. `ChildOf` may not be.
- Per-access cost: property reads through the `World` may slow per-frame code that walks nodes.
- Archive, clone and per-node caches (`boundsCache`, `deformationCache`, `runningActions`) depend on the current storage.

## Planned sub-steps (to be filed separately)

1. Spike: `Node` backed by an entity for transform, content and hierarchy only. Existing tests pass.
2. Renderer flatten/culling uses ECS queries.
3. Revisions and observation driven from component change events.
4. Remaining node features, archive and clone.
5. Public `world` escape hatch and documentation for ECS-based apps.

\- `2026-11-04T19:50:06Z`: Additional goal: interop in both directions.

- Embed a scene graph into an app's existing SwiftECS World: SceneGraph uses a World it does not own and does not create its own.
- Or embed an app's ECS into a scene graph: the app attaches its own components and systems to the World that SceneGraph owns.

Open questions:
- Ownership and lifetime of the World when SceneGraph does not own it.
- Several scene graphs in one World: which entities belong to which graph (a root entity, or a scene membership component).
- Entities that the app creates with scene components but without a Node: does SceneGraph adopt them, ignore them, or create Nodes lazily.
- Systems order: where SceneSprockets' own systems (actions, constraints, physics, particles) run in the app's pipeline.

- `2026-11-04T20:45:00Z`: Related: #251 (large-world precision) and #252 (Float time) matter for the simulation-heavy apps this targets.
- `2026-11-05T17:23:44Z`: Sub-issues (in dependency order): #263 toolchain → #264 per-access cost / change events → #265 spike → #266 revisions/observation → #267 renderer queries → #268 remaining features/archive/clone → #269 World-sharing API.
- `2026-11-05T23:02:29Z`: Closed: all subtasks done (#263-#269, follow-ups #271-#281). Open follow-ups: #270 (steady-state node access cost, measure later) and #282 (SwiftECS is still a local path dependency).

---

## 251: Shaders lose precision far from the world origin

+++
status: closed
priority: medium
kind: bug
labels: effort:m, area:renderer
created: 2026-11-04T20:38:00Z
updated: 2026-11-04T20:52:18Z
closed: 2026-11-04T20:52:18Z
+++

ShaderMaterialTransforms passes modelMatrix, modelViewProjectionMatrix and cameraPosition as 32-bit floats in world space. In large scenes (SidraLine places units 50-100 km from the origin) a float only resolves about 4-8 mm there, so anything a shader derives from world positions close up is quantized.

Seen in SidraLine (its issue #40): flat-face normals from dfdx/dfdy of the world position show per-pixel speckle on objects near the camera. A 14 mm per-pixel step comes out as 11.7 or 15.6 mm from pixel to pixel. The app works around it in its own shaders by building a camera-relative position from (modelMatrix[3] - cameraPosition) plus the local offset; every ShaderMaterial user far from the origin has to do the same.

## Proposed fix (per schwa)

Provide camera-relative transforms to materials: subtract the camera position from model translations on the CPU in double precision, and pass a camera-relative model matrix with a rotation-only view matrix, so shaders never see large world coordinates.

\- `2026-11-04T20:43:11Z`: Target use cases: games like Harpoon or Kerbal Space Program.

- Very large coordinate ranges: ocean theaters of hundreds to thousands of km, or whole solar systems. Float32 world positions cannot cover these even at coarse precision.
- The camera moves across the full range and views objects close up anywhere in it, so precision is needed near the camera, wherever the camera is.
- Several views of the same world at very different scales (tactical map vs close-up 3D).
- Related: #252 (Float time) has the same kind of precision loss over long runs.

- `2026-11-04T21:06:14Z`: Follow-ups: #253 (Blinn-Phong), #254 (PBR), #255 (Float scene graph positions for very large worlds).

---

## 252: Time values use Float (precision loss, no units)

+++
status: open
priority: low
kind: enhancement
labels: area:scenegraph, effort:l
created: 2026-11-04T20:42:33Z
updated: 2026-11-04T20:45:00Z
+++

Times, durations and delta times are plain `Float` across the public API: `Action` durations, `advanceActions(by:)`, `applyConstraints(deltaTime:)`, `Transaction.animate(duration:)`, particle `time` and `advanceParticles(by:)`, animation clip time and blending, `SceneView`, and physics stepping (~70 sites in Action, Animation, AnimationBlending, Particles, Constraint, Transaction, SceneView, SceneGraphPhysicsWorld, ModelIOSceneGraph).

Problems:
- Float32 has about 7 significant digits. Accumulated or absolute times (long-running particle `time`, animation playhead, elapsed time) lose sub-millisecond precision after hours, causing jitter.
- A bare number does not say its unit (seconds assumed) and does not separate durations from points in time.
- Inconsistent with platform time types (`TimeInterval`/`Double`, `Duration`, `ContinuousClock.Instant`) that callers usually have.

- `2026-11-04T20:54:25Z`: Looked at the ~70 sites. Punting: this is a public API break across actions, animation, particles, constraints, transactions, SceneView and physics, and the target type is a design decision the code cannot answer. Options seen: (a) TimeInterval/Double everywhere (simple, matches CADisplayLink and AVFoundation); (b) Swift Duration for durations plus Double for accumulated time (typed, but awkward arithmetic and no Float conversion in shaders); (c) Double only for accumulated/absolute time (particle time, animation playhead), keep Float for small per-frame deltas and durations. Also: whether to keep Float overloads as deprecated shims. Unblocker: pick a/b/c and say whether to keep deprecated Float overloads.
- `2026-11-04T21:10:48Z`: Part of #255 (very large worlds).

---

## 253: Blinn-Phong loses precision far from the world origin

+++
status: closed
priority: medium
kind: bug
labels: area:renderer, effort:m
created: 2026-11-04T21:06:11Z
updated: 2026-11-04T21:15:18Z
closed: 2026-11-04T21:15:18Z
+++

Follow-up to #251, which fixed ShaderMaterial and the debug view only.

BlinnPhong.metal computes worldPosition = modelMatrix * position and clip position = frame.viewProjection * world in 32-bit floats, in world space. Far from the origin (SidraLine: 50-100 km) a float resolves only about 4-8 mm, so anything derived from world positions near the camera is quantized:
- flat normals from dfdx/dfdy(worldPosition) for meshes without normals
- the normal-map tangent frame (perturbedNormal uses dfdx/dfdy of the position)
- view direction (cameraPosition - worldPosition) for specular
- point/spot light vectors and shadow-map lookups

Expected: Blinn-Phong surfaces near a camera far from the origin shade like the same scene near the origin.

- `2026-11-04T21:10:48Z`: Part of #255 (very large worlds).

---

## 254: PBR loses precision far from the world origin

+++
status: closed
priority: medium
kind: bug
labels: area:renderer, effort:m
created: 2026-11-04T21:06:11Z
updated: 2026-11-04T21:20:43Z
closed: 2026-11-04T21:20:43Z
+++

Follow-up to #251, which fixed ShaderMaterial and the debug view only.

The PBR path (MetalSprocketsPBR via PBRMaterialRenderer) passes world-space model matrices and camera position as 32-bit floats. Far from the origin (SidraLine: 50-100 km) world positions near the camera are quantized to about 4-8 mm, which affects screen-space derivatives, view vectors, lighting and transmission. The shaders live in MetalSprocketsPBR, so a fix likely spans both packages.

Expected: PBR surfaces near a camera far from the origin render like the same scene near the origin.

- `2026-11-04T21:10:48Z`: Part of #255 (very large worlds).

---

## 255: Umbrella: very large worlds (solar-system scale)

+++
status: open
priority: low
kind: feature
labels: area:scenegraph, effort:xl, umbrella
depends: 256, 257, 258, 259, 260, 261, 253, 254, 252, 262
created: 2026-11-04T21:06:11Z
updated: 2026-11-04T21:19:04Z
+++

Node transforms and accumulated world transforms are simd_float4x4. Float32 resolves about 4-8 mm at 100 km and about 1 km at 1e10 m, so worlds at solar-system scale (Kerbal Space Program style; see #251 comments) cannot be represented, even though the renderers can now draw camera-relative (#251).

Affects: world transform accumulation, bounds, hit testing, culling, physics hand-off, archives.

Related: #250 (ECS storage), #252 (Float time).

\- `2026-11-04T21:10:48Z`: Now an umbrella. Sub-issues:
- #256 Node and world transforms are Float (xl, the big refactor)
- #253 Blinn-Phong precision far from origin (m)
- #254 PBR precision far from origin (m, spans MetalSprocketsPBR)
- #257 Shadows, fog, particles, gizmos, culling use world-space Float (m)
- #258 SwiftJolt double precision unknown (s, investigation)
- #259 Physics cannot run far from origin (l)
- #260 Fast-moving active objects jitter (m)
- #261 One depth range cannot hold parts and planets (l)
- #252 Float time (needs an API decision)
No orbit work planned.

Doable now without a huge refactor: #253, #254, #257, #258. These work with today's Float world transforms (camera-relative rendering helps SidraLine-scale scenes immediately) and do not depend on #256.
Blocked or big: #256 (core refactor); #259 and #260 build on #256 and #258; #261 is a renderer architecture change; #252 waits on a decision.

---

## 256: Node and world transforms are Float

+++
status: open
priority: low
kind: feature
labels: area:scenegraph, effort:xl, subtask
created: 2026-11-04T21:10:37Z
updated: 2026-11-04T21:10:47Z
+++

Node local transforms and accumulated world transforms (SceneGraph.visit/traverse, MeshEntry.worldTransform, bounds, hit testing) are simd_float4x4. Float32 resolves about 4-8 mm at 100 km and about 1 km at 1e10 m, so positions in very large worlds cannot be stored.

Part of #255.

---

## 257: Shadows, fog, particles, gizmos and culling use world-space Float matrices

+++
status: closed
priority: medium
kind: bug
labels: area:renderer, effort:m, subtask
created: 2026-11-04T21:10:37Z
updated: 2026-11-04T21:19:14Z
closed: 2026-11-04T21:19:14Z
+++

#251 made ShaderMaterial and the debug view camera-relative. These paths still build world-space Float view-projection matrices and lose precision far from the origin: shadow-map light view-projections (Shadows.swift, ShadowMask), FogPass inverseViewProjection, particle simulate/render view matrices, gizmos and SelectionOutline, frustum culling (meshEntriesInFrustum).

Part of #255.

- `2026-11-04T21:19:14Z`: Fixed: shadows (light views, casters, skinned joints, screen-space mask, receiver mask), fog, ambient occlusion, culling and the selection outline are camera-relative. Not done: particles and the transform gizmo, moved to #262. Culling at 2^20 m showed no wrong results in the edge sweep test before the change (camera position exactly representable); the change still removes the large-value math.

---

## 258: SwiftJolt double precision is unknown

+++
status: closed
priority: low
kind: task
labels: area:physics, effort:s, subtask
created: 2026-11-04T21:10:37Z
updated: 2026-11-04T21:21:09Z
closed: 2026-11-04T21:21:09Z
+++

Jolt supports a JPH_DOUBLE_PRECISION build (double positions, float elsewhere). It is not known whether SwiftJolt builds or exposes it, what its API looks like (RVec3), or what it costs. Needed to decide how physics works far from the origin.

Part of #255.

\- `2026-11-04T21:21:08Z`: Findings (SwiftJolt as resolved in SceneSprockets' .build/checkouts):
- Not enabled. CJolt is a prebuilt binary xcframework; Scripts/build-xcframework.sh passes no -DDOUBLE_PRECISION=ON, so Jolt is built in single precision (pins: joltc e6409c5a, JoltPhysics 05fcfbf7).
- The C header supports it: joltc.h has #if defined(JPH_DOUBLE_PRECISION) branches where JPH_RVec3 is three doubles and JPH_RMat4 has a double column3; otherwise JPH_RVec3 is a typedef of JPH_Vec3 (float). The module map does not define JPH_DOUBLE_PRECISION, so Swift sees the float layout.
- The Swift API is float-only: PhysicsWorld.position(of:), setPosition(of:to:), addBody(position:), CompoundChild(position:) etc. take SIMD3<Float>; RVec3 is used in about 40 places (Constraints, BodyLocking, JoltPhysics, Character, VirtualCharacter, Vehicles, ContactListener) and bridged from SIMD3<Float>.
- SceneSprocketsPhysics (SceneGraphPhysicsWorld) passes world-space SIMD3<Float> poses to these.

What enabling it would take, in SwiftJolt: build a second (or replacement) xcframework with DOUBLE_PRECISION=ON; define JPH_DOUBLE_PRECISION for Swift (module map or a separate CJoltDouble module, since one module cannot expose both layouts); change the RVec3/RMat4 bridging to SIMD3<Double>/double matrices; change public position APIs to Double (or add Double overloads). Cost: not measured; Jolt documents double precision as somewhat slower and larger, with only positions in double.

For #259 the alternative needs no SwiftJolt change: keep Jolt in float and simulate in a local frame around the active area (floating origin), shifting body positions when the origin moves.

---

## 259: Physics cannot run far from the world origin

+++
status: open
priority: low
kind: feature
labels: area:physics, effort:l, subtask
created: 2026-11-04T21:10:37Z
updated: 2026-11-04T21:10:47Z
+++

SceneSprocketsPhysics hands world-space Float positions to Jolt. Far from the origin, simulation near the active area loses precision. There is no floating origin or local physics frame around the active area.

Part of #255.

---

## 260: Fast-moving active objects jitter

+++
status: open
priority: low
kind: feature
labels: area:physics, effort:m, subtask
created: 2026-11-04T21:10:37Z
updated: 2026-11-04T21:10:47Z
+++

At orbital speeds (several km/s) the active object's coordinates change by kilometers per second, so precision near it degrades and rendering and physics jitter. There is no reference frame that keeps the active object near rest (KSP's Krakensbane).

Part of #255.

---

## 261: One depth range cannot hold centimeter parts and planets millions of km away

+++
status: open
priority: low
kind: feature
labels: area:renderer, effort:l, subtask
created: 2026-11-04T21:10:38Z
updated: 2026-11-04T21:10:47Z
+++

Reverse-Z Float depth cannot resolve both nearby parts and very distant bodies in one pass. There is no scaled-space pass or multi-range (nested frusta) rendering. Related: #248 (several viewports/passes in one view).

Part of #255.

---

## 262: Particles use world-space Float matrices

+++
status: open
priority: low
kind: bug
labels: area:renderer, effort:m, subtask
created: 2026-11-04T21:19:04Z
updated: 2026-11-07T16:00:59Z
+++

Left over from #257. Particle simulation and drawing (SceneParticleSystem simulate(view:) and runtime render(projection:view:), MetalSprocketsParticles) and the transform gizmo (TransformGizmo, GraphicsContext3DRenderPipeline with projection * view) still work in world-space Float, so far from the origin they jitter or misplace like the other paths did before #251/#253/#257. Particle positions live in MetalSprocketsParticles buffers, so a fix spans that package.

Part of #255.

- `2026-11-07T16:00:59Z`: Transform gizmo part fixed: the overlay draws camera-relative (origin minus camera position, computed in Double) with a rotation-only view, and SceneViewport.worldSizeOfPoint (which sizes the handles) projects camera-relative too. New SceneViewport.rotationOnlyViewMatrix inverts the camera rotation alone, so it stays precise far away. Test drawsTheSameFarFromOrigin (translate/rotate/scale at 2^20) failed before with 1159-9846 of 40000 pixels differing; now passes. Title narrowed to the particle part, which is still open: particle positions live in MetalSprocketsParticles buffers, so it needs a change in that package.

---

## 263: Package tools version 6.2 is below SwiftECS's required 6.4

+++
status: closed
priority: low
kind: task
labels: area:scenegraph, effort:s, subtask
created: 2026-11-05T17:23:12Z
updated: 2026-11-05T17:34:51Z
closed: 2026-11-05T17:34:51Z
+++

Part of #250. SwiftECS requires Swift tools 6.4; SceneSprockets declares 6.2, so the package cannot depend on SwiftECS. Raising the version affects all downstream apps.

- `2026-11-05T17:34:51Z`: Tools version 6.4; SwiftECS added as local path dep of SceneSprockets. macOS build + 289 tests pass.

---

## 264: Unknown per-access cost of World-backed node properties

+++
status: closed
priority: low
kind: task
labels: area:scenegraph, subtask, effort:m
depends: 263
created: 2026-11-05T17:23:35Z
updated: 2026-11-05T17:37:32Z
closed: 2026-11-05T17:37:32Z
+++

Part of #250. It is not known whether reading/writing node properties through a SwiftECS World is fast enough for per-frame code that walks nodes, nor whether SwiftECS reports component changes. Both determine whether the World can be the source of truth for node data. Needs measurement against current Node storage.

\- `2026-11-05T17:37:32Z`: Findings (Release build, M-series Mac, 100k nodes/entities, best of 5, float4x4 component):

| Access | ns/op |
|---|---|
| Node.transform read | 25.6 |
| Node.transform write | 135.9 |
| Entity[T] read (random access by handle) | 491.1 |
| Entity.set write, no observer | 1267.8 |
| Entity.set write, 1 observer | 1347.2 |
| world.query read | 19.7 |
| query ComponentRef write, no observer | 47.1 |
| query ComponentRef write, 1 observer | 114.2 |

- Per-entity access through Entity handles is ~19x slower for reads and ~9x slower for writes than Node properties. A Node that forwards each property to world lookups would make tree-walking code much slower.
- Query iteration matches or beats Node property access (reads ~0.8x, writes ~0.35x).

Change events:
- SwiftECS has per-component-type observers: World.observe(T.self) delivers .added/.removed/.changed synchronously. Writes through Entity.set/subscript, ComponentRef.value and system field writes all emit .changed.
- SwiftUI observation is coarse: World is @Observable with one storage revision (MutationCoordinator). Any mutation invalidates every view that read any component. Node today has per-property observation. World.batchingObservation coalesces invalidations.

Benchmark was a temporary test, not committed.

---

## 265: Node cannot be backed by an ECS entity (transform, content, hierarchy)

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:l
depends: 264
created: 2026-11-05T17:23:36Z
updated: 2026-11-05T18:22:56Z
closed: 2026-11-05T18:22:56Z
+++

Part of #250, sub-step 1. Node stores transform, content and hierarchy itself. Unresolved: entity<->Node mapping, Node lifetime after entity destruction, and ordered children vs ChildOf. Done when existing tests pass with these parts entity-backed.

\- `2026-11-05T17:37:50Z`: Read SwiftECS's ChildOf/RelationshipStorage and counted Node property use in Sources (worldTransform 119, content 36, transform 23, parent 17, children 12). Punting: three design decisions are not settled, and #264's numbers make the first one costly to get wrong.

1. Source of truth. Entity-handle access is ~19x slower to read and ~9x slower to write than Node properties (#264). Should Node (a) forward every property to the World, (b) keep a cached ComponentRef/column location so each access skips the lookup (this breaks when the entity's archetype changes), or (c) keep its own storage and mirror into the World?
2. Identity and lifetime. Should Node.id become the EntityID? What should a Node do when its entity is destroyed from outside: trap, or report detached and return defaults?
3. Child order. ChildOf keeps children in insertion order (OrderedSet) but has no insert-at or move. Use a sibling-index component, or add ordered insert to SwiftECS?

Unblocker: choose for 1-3 (my suggestion: 1b, Node.id = EntityID with detached state, sibling-index component).

- `2026-11-05T17:40:46Z`: Decisions (per schwa): 1b — Node caches its component storage location and refreshes it when the archetype changes. 2 — Node.id becomes EntityID; a Node whose entity is destroyed elsewhere becomes detached (no parent, default values, no trap). 3 — sibling-index component for child order.
- `2026-11-05T18:07:48Z`: Decision update (per schwa): no private Worlds. A Node keeps local storage until it is attached under a SceneGraph's root. On attach it creates an entity in the graph's World with its own pre-assigned random EntityID and reads/writes through the World. On detach it copies values back to local storage. Needs SwiftECS: public createEntity(id:) and a public structural-change counter.

---

## 266: Direct World writes skip revisions, transactions and observation

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:l
depends: 265
created: 2026-11-05T17:23:36Z
updated: 2026-11-05T18:29:21Z
closed: 2026-11-05T18:29:21Z
+++

Part of #250, sub-step 3. Revisions, transactions/undo and @Observable notifications are driven from Node didSet. Writes made directly to the World bypass them, leaving caches, undo and SwiftUI stale.

- `2026-11-05T17:37:57Z`: Punting: blocked by #265. Node data is not stored in the World yet, so no direct World write can skip revisions or observation. Relevant from #264: SwiftECS emits synchronous per-type .changed events from every public write path, and World observation is one coarse revision. Unblocker: the design decisions on #265.

---

## 267: Renderer flatten and culling walk the node tree instead of querying

+++
status: closed
priority: low
kind: enhancement
labels: subtask, effort:l, area:renderer
depends: 266
created: 2026-11-05T17:23:37Z
updated: 2026-11-05T22:54:16Z
closed: 2026-11-05T22:54:16Z
+++

Part of #250, sub-step 2. Flatten/culling traverse the tree. boundsCache and deformationCache live on Node and are not available to ECS queries.

\- `2026-11-05T17:38:01Z`: Punting: blocked by #265 and #266. The renderer can't query the World for transforms, content, bounds or deformation until Node stores them there (#265), and query results can't be trusted until direct writes keep revisions and caches correct (#266). Relevant from #264: query iteration costs about the same as Node property access, so this step looks fast enough. Unblocker: the design decisions on #265.
\- `2026-11-05T18:30:02Z`: Checked what flatten and culling read per node: content and transform (in the World since #265), plus isShown (isVisible/isActive, inherited), inheritedOpacity, pivot, categoryBitMask, lightCategoryBitMask, renderingOrder, skin, skinVertices, morphTargets/morphWeights and mesh/subtree bounds, none of which are in the World. Punting: blocked by #268 (moves those fields), and it needs a design decision. World transform, visibility and opacity depend on ancestors, so a query can only replace the tree walk if something stores those per entity first. Traversal currently costs ~95 ns/node (#270), so speed alone may not justify it. Unblocker: decide whether SceneGraph should keep computed WorldTransform/visibility/opacity components (updated from revisions, and readable by ECS apps), or whether the renderer should keep walking the tree and #267 should close as not needed.
\- `2026-11-05T22:07:56Z`: Update: #268 is done, so every field flatten and culling read is now in the World. The design decision from the previous comment is still open: should SceneGraph keep computed WorldTransform/visibility/opacity components per entity, so the renderer can query them? New input from #270: per-node getters now cost ~280-300 ns per node in traversal (pre-ECS ~100). Reading columns through queries skips most of that, so this is now also the main path to recovering traversal speed. Punting until that decision is made.
\- `2026-11-05T22:17:09Z`: Question 1 (design): Should SceneGraph keep computed WorldTransform, visibility and opacity components per entity, so the renderer (and ECS apps) can query them instead of walking the tree? If not, keep the tree walk and close this. Suggested: yes; it is also the likeliest way to recover traversal speed (#270).
\- `2026-11-05T22:18:31Z`: Answer 1: yes
\- `2026-11-05T22:49:44Z`: Implemented #267-Q1 (yes) in a working copy and measured it; not committed, reverted. Design tried: one NodeWorldStateComponent per entity (world transform, inherited isShown, inherited opacity, depth-first order), dirty-subtree updates from Node.bump, full pass on hierarchy change, flatten by World query sorted by order. All 320 tests passed.

Release, 100k nodes (10k groups of 10), ns/node, back-to-back:
| case | tree walk (current) | World state + query |
| one transform changed | ~293 | ~275-295 |
| root transform changed (all dirty) | ~295 | ~575-595 (1,400 before caching refs) |
| hierarchy changed | ~375 | ~665-700 |

Why: computing world state still needs a tree walk; on top of that each node is written to the World, and the query plus a sort over all entities costs about as much as the old walk. Per-node World reads dominate in both. So this does not speed up rendering, and my earlier suggestion that it would recover #270's cost was wrong.

The other benefit, ECS apps querying world transforms, has no consumer until #269.

- `2026-11-05T22:49:44Z`: Question 1 (decision): Querying world state for rendering measured slower than the tree walk (2x when the root or hierarchy changes, no gain otherwise; see comment). Keep the tree walk for rendering and close this, and add world-state components later with #269 only if ECS apps need them? Suggested: yes.
- `2026-11-05T22:54:16Z`: Answer 1: Yes (per schwa: follow suggestion). Keep the tree walk for rendering; add world-state components with #269 only if ECS apps need them.
- `2026-11-05T22:54:16Z`: Closed per #267-Q1: the renderer keeps the tree walk (World queries measured slower). World-state components may come later with #269 if ECS apps need them.

---

## 268: Remaining node features, archive and clone are not entity-backed

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:xl, has-subtasks
depends: 267, 274, 275, 276, 277, 278, 279, 280
created: 2026-11-05T17:23:37Z
updated: 2026-11-05T19:49:24Z
closed: 2026-11-05T19:49:24Z
+++

Part of #250, sub-step 4. Lights, cameras, physics bodies, skin, morph data, particles, audio, LOD, actions/runningActions, archive and clone still use Node storage.

- `2026-11-05T19:12:50Z`: Split (per schwa): #274 shared storage mechanism → #275 skin/morph, #276 physics/LOD, #277 particles/audio, #278 action state, #279 visibility/opacity/masks/pivot/rendering order/label (added to scope) → #280 archive/clone tests. Lights and cameras are already in the World as content (#265). Constraints and subdivision filed separately as #281.
- `2026-11-05T19:49:24Z`: All subtasks closed (#274-#280). Constraints and subdivision were done separately in #281.

---

## 269: No API for sharing a World between SceneGraph and an ECS app

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:l
depends: 268
created: 2026-11-05T17:23:38Z
updated: 2026-11-05T23:01:40Z
closed: 2026-11-05T23:01:40Z
+++

Part of #250, sub-step 5. Apps cannot pass their own World to SceneGraph or reach SceneGraph's World. Open: World ownership/lifetime when not owned; several graphs in one World; entities with scene components but no Node; ordering of SceneSprockets systems (actions, constraints, physics, particles) in the app's pipeline. Needs docs.

\- `2026-11-05T17:38:07Z`: Punting: blocked by #265-#268. SceneGraph has no World holding node data yet, so there is nothing to share or hand to an app. The open questions in this issue (World ownership, several graphs in one World, entities without a Node, system ordering) also depend on the identity and source-of-truth decisions on #265. Unblocker: the design decisions on #265.
\- `2026-11-05T22:08:10Z`: Punting: the ownership/lifetime questions in this issue are still open, and they decide the API shape. Concrete questions:
1. First step: expose SceneGraph.world (read/write) and make the Node*Component types public under their current names? Direct writes still have gaps: #271 destroy, #272 animation, #273 hierarchy.
2. SceneGraph(world:) for an app-owned World: should SceneGraph hold it strongly (it lives as long as any graph using it) or weakly (app must keep it alive)?
3. Several graphs in one World: tag entities with a scene-membership component holding the graph's root EntityID?
4. Entities with Node components but no Node: ignore them (suggested), or create Nodes lazily?
5. System ordering: leave actions/constraints/particles/physics as SceneGraph methods the app calls (today), or register them as SwiftECS systems in the World's pipeline?

My suggestions: 1 yes, but only after #271/#273 are decided; 2 strong; 3 yes; 4 ignore; 5 keep methods for now.

- `2026-11-05T22:17:09Z`: Question 1 (decision): Expose SceneGraph.world and make the Node*Component types public now, or wait until #271 and #273 are decided? Suggested: wait.
- `2026-11-05T22:17:09Z`: Question 2 (decision): For SceneGraph(world:) with an app-owned World, should the graph hold the World strongly or weakly? Suggested: strongly.
- `2026-11-05T22:17:10Z`: Question 3 (design): Several graphs in one World: tag each entity with a component holding its graph's root EntityID? Suggested: yes.
- `2026-11-05T22:17:10Z`: Question 4 (decision): Entities that have Node components but no Node (created by the app): ignore them, or create Nodes for them lazily? Suggested: ignore.
- `2026-11-05T22:17:11Z`: Question 5 (decision): Actions, constraints, particles and physics: keep them as SceneGraph methods the app calls, or register them as SwiftECS systems in the World's pipeline? Suggested: keep the methods for now.
- `2026-11-05T22:18:39Z`: Answer 1: wait
- `2026-11-05T22:18:53Z`: Answer 2: strongly
- `2026-11-05T22:18:59Z`: Answer 3: sure
- `2026-11-05T22:19:06Z`: Answer 4: ignore
- `2026-11-05T22:19:13Z`: Answer 5: yes

---

## 270: Node property access is slower for nodes in a graph

+++
status: open
priority: low
kind: enhancement
labels: area:scenegraph, effort:m, subtask
depends: 265
created: 2026-11-05T18:22:50Z
updated: 2026-11-05T19:26:38Z
+++

Part of #250. After #265, nodes under a SceneGraph's root read transform and content through the World. Release build, 100k nodes, best of 5 (noisy machine): attached transform read ~64 ns vs ~34 ns before; attached write ~220 ns vs ~180 ns; detached read ~38 ns vs ~28 ns. Each attached read registers observation on both the Node and the World and takes a column lock. Traversal measured 75-153 ns per node vs ~102 ns before; the noise is too high to say more.

\- `2026-11-05T18:27:51Z`: After #266 (Release, 100k nodes, two runs): attached write ~360-390 ns (was ~220 after #265, ~180 before ECS). Node writes now go through SwiftECS's change observer, which SceneGraph uses to catch direct World writes. My guess is the cost is in the observer dispatch passing the component as 'any Component' (boxing a LocalTransform), not profiled. Attached read 70-98 ns; traversal ~95 ns/node (baseline ~102).
\- `2026-11-05T19:40:58Z`: After #279 (8 more fields in the World; traversal now reads isVisible, isActive, pivot and transform through the World): traversal 181-199 ns/node over 3 runs (was 81-167 before #279, ~102 before ECS). Attached transform read 93-100 ns. Each field read checks the binding's structuralRevision and the field's cached ref separately.
\- `2026-11-05T22:07:08Z`: Profiled the benchmark with Time Profiler. Two findings:
1. Main cause: every structural change anywhere in the World (add/remove of any node, app components) invalidated every node's cached field refs, so the next pass re-looked-up all of them (dictionary hashing, String(describing:) in ComponentType.init, conformance checks). Traversal right after one add+remove: 9,480 ns/node. Fixed by tracking the entity's own storage location (new World.storageLocation(of:) in SwiftECS, archetype serial + row) and re-making refs only when that moves: now ~300-340 ns/node.
2. Steady state is still slower than before ECS: attached read ~100-110 ns (pre-ECS ~28), traversal ~280-300 ns/node (pre-ECS ~100), write ~490-540 ns. Profile shows this spread across retain/release, exclusivity checks, NodeFieldStorage copies and the column lock in ComponentRef. Tried making NodeFieldStorage a class: no measurable gain, reverted.

Leaving open for the steady-state cost. Further gains likely need SwiftECS changes (lock-free serial reads in ComponentRef) or the renderer reading columns via queries (#267) instead of per-node getters.

- `2026-11-05T22:17:11Z`: Question 1 (decision): Steady-state node access is still about 2-3x slower than before the ECS work. Keep this open until #267 (queries) or a lock-free SwiftECS read path lands, or accept the cost and close it? Suggested: keep open.
- `2026-11-05T22:19:29Z`: Answer 1: keep open - but we'll measure cost later
- `2026-11-06T00:25:58Z`: Autoresearch session (#283), commit 'Speed up node access and writes after the ECS port': traversal 276 -> ~153 ns/node, write 511 -> 260, flatten 296 -> ~155, read 107 -> ~45, create+attach 65,800 -> ~38,000. Pre-ECS reference: traversal ~100, read ~30, write ~180. Remaining traversal cost is mostly ComponentRef retain/release; further gains likely need a non-retaining SwiftECS read path.
- `2026-11-06T01:29:09Z`: Second autoresearch session (#283), geomean of the 5 benchmark metrics 419 -> 284 (-32%). Mostly SwiftECS: entity location holds its archetype, lazy ComponentType names, typed entity creation, specialized swapRemove and change dispatch, reuse of the last creation archetype, skipping storage publish with no observers. SceneSprockets: typed node creation, static key paths for Observation, cheaper transaction check. Now (ns/node): traversal ~142, flatten ~137, read ~38, write ~192, create+attach ~13,000. Pre-ECS: traversal ~100, read ~30, write ~180.

---

## 271: Node keeps its parent after its entity is destroyed outside the scene graph

+++
status: closed
priority: low
kind: bug
labels: area:scenegraph, effort:s, subtask
depends: 265
created: 2026-11-05T18:22:50Z
updated: 2026-11-05T22:40:32Z
closed: 2026-11-05T22:40:32Z
+++

Part of #250. Decision on #265: a Node whose entity is destroyed from outside becomes detached with no parent and default values. After #265 it gets default values and no entity, but it stays in its parent's children and keeps its parent, so traversal still visits it.

Repro: make a graph with root and child; destroy the child's entity via graph.world; child.parent is still root and root.children still contains child.

\- `2026-11-05T18:27:51Z`: Also: destroying a node's entity emits no component .removed events, so the scene graph revision does not change either; renderer caches keep showing the node until something else bumps the revision.
\- `2026-11-05T19:36:37Z`: Tried: a test (destroy a middle child's entity via graph.world; expect child.parent == nil, root.children without it, a structure revision bump, and the grandchild's entity gone) fails all 6 checks. Then made SwiftECS's removeEntity emit .removed component events, so SceneGraph could react. Reverted: SwiftECS deliberately does not do that. 'entity lifecycle changes notify storage without synthesizing component events' (MutationBoundaryTests) and 2 other tests fail with it.

Punting: SceneGraph has no cheap, eager way to learn that an entity was destroyed. It only notices on the node's next read, and pruning the tree from inside a getter (often during traversal or a SwiftUI update, see #212) is unsafe. Scanning all nodes on every structuralRevision change costs O(n) per structural edit.

Unblocker: OK to add an entity-level destroy observer to SwiftECS (e.g. World.observeDestroyed { entityID in ... }), separate from component events, so the existing design stays? Or accept lazy detection plus a pruning pass at a safe point (e.g. start of SceneGraph.advanceActions / each frame)?

- `2026-11-05T22:17:07Z`: Question 1 (decision): Should SwiftECS get an entity-destroy event (separate from component events) so SceneGraph can remove a node from the tree when its entity is destroyed elsewhere? If not, SceneGraph would detect it lazily and prune at a safe point each frame. Suggested: add the event.
- `2026-11-05T22:19:38Z`: Answer 1: yes

---

## 272: Direct World writes to node transforms are not animated by Transaction.animate

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, effort:m, subtask
depends: 266
created: 2026-11-05T18:27:51Z
updated: 2026-11-05T22:37:15Z
closed: 2026-11-05T22:37:15Z
+++

Part of #250. Inside SceneGraph.Transaction.animate, Node setters record the old transform so it can animate. Writing NodeTransformComponent directly to the graph's World inside the block changes the value at once with no animation. SwiftECS's change event only carries the new value.

- `2026-11-05T22:07:27Z`: Looked at the event path. Punting: needs a design decision. Animating a direct World write needs the old value, and SwiftECS's ComponentEvent.changed carries only the new one. Options: (a) add the old value to SwiftECS change events (breaking public API, affects every observer); (b) keep a per-node copy of each field just for this, which brings back the duplicated storage #250 removes; (c) decide direct World writes are not implicitly animated (simulation code usually does not want it), document it on Transaction.animate and close this. My suggestion is (c). Which one?
- `2026-11-05T22:17:08Z`: Question 1 (decision): Should direct World writes inside Transaction.animate be animated? That needs old values in SwiftECS change events (breaking) or a per-node copy of every field. Suggested: no; document it on Transaction.animate and close this.
- `2026-11-05T22:19:47Z`: Answer 1: no
- `2026-11-05T22:37:15Z`: Closed per #272-Q1 (no): direct World writes are not animated; documented on Transaction.animate.

---

## 273: Direct ChildOf or sibling-index edits in the World do not change the node tree

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, effort:m, subtask
depends: 266
created: 2026-11-05T18:27:51Z
updated: 2026-11-05T22:58:03Z
closed: 2026-11-05T22:58:03Z
+++

Part of #250. The node tree owns the hierarchy and copies it into the World as ChildOf and SiblingIndexComponent. Changing either directly in the World leaves Node.parent and Node.children as they were, so rendering and traversal ignore the edit. SwiftECS has no events for relationship changes.

\- `2026-11-05T22:07:42Z`: Checked SwiftECS: relationship edits (setParent, addRelationship, removeRelationship) emit no events, so SceneGraph cannot learn of a direct ChildOf change. SiblingIndexComponent edits do emit .changed, but applying them needs a rule for duplicate or out-of-range indices.

Punting: needs design decisions, related to #271. Options: (a) add relationship-change and entity-destroy observers to SwiftECS (one decision for both #271 and #273), then sync the node tree from them, with the rule 'sort children by sibling index, ties keep their current order'; (b) declare the World's ChildOf and SiblingIndexComponent a read-only mirror of the node tree, document it for ECS apps (#269), and close this. Which one?

- `2026-11-05T22:17:08Z`: Question 1 (decision): Should SwiftECS get relationship-change events so direct ChildOf edits update the node tree? If not, ChildOf and SiblingIndexComponent become a read-only copy of the node tree, documented for ECS apps. Suggested: add the events, together with #271's destroy event.
- `2026-11-05T22:17:08Z`: Question 2 (design): If direct edits are synced: when sibling indices clash or are out of range, sort children by index with ties keeping their current order?
- `2026-11-05T22:19:54Z`: Answer 1: yes
- `2026-11-05T22:20:01Z`: Answer 2: unsure
- `2026-11-05T22:54:16Z`: Q2 decided (per schwa: follow suggestion): sort children by sibling index, ties keep their current order; a direct ChildOf edit places the child last among its new siblings.

---

## 274: Each World-backed node property repeats its own storage code

+++
status: closed
priority: low
kind: task
labels: area:scenegraph, subtask, effort:m
depends: 266
created: 2026-11-05T19:12:42Z
updated: 2026-11-05T19:34:36Z
closed: 2026-11-05T19:34:36Z
+++

Part of #268. localTransform and content each have their own component type, getter, setter (local storage vs ComponentRef, writeFromNode, Observation, revision bump) and change handling in NodeStore. Moving more fields to the World would copy that per field.

Acceptance: transform and content use one shared mechanism; adding a field needs only its component and a short declaration; existing tests pass.

---

## 275: Skin and morph data are not stored in the World

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:m
depends: 274
created: 2026-11-05T19:12:42Z
updated: 2026-11-05T19:44:54Z
closed: 2026-11-05T19:44:54Z
+++

Part of #268. skin, skinVertices, morphTargets and morphWeights live on Node. ECS apps cannot read or change them through the graph's World.

Acceptance: these fields are in the World for nodes in a graph; direct World writes bump the right revision; morphWeights implicit animation (Transaction) still works through the Node API; existing skin/morph tests pass.

---

## 276: Physics bodies and levels of detail are not stored in the World

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:s
depends: 274
created: 2026-11-05T19:12:42Z
updated: 2026-11-05T19:42:17Z
closed: 2026-11-05T19:42:17Z
+++

Part of #268. physicsBody and levelsOfDetail live on Node.

Acceptance: both are in the World for nodes in a graph; direct World writes bump the structure revision; physics and LOD tests pass.

---

## 277: Particle systems and audio players are not stored in the World

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:s
depends: 274
created: 2026-11-05T19:12:42Z
updated: 2026-11-05T19:43:41Z
closed: 2026-11-05T19:43:41Z
+++

Part of #268. particleSystems and audioPlayers (arrays of shared objects) live on Node.

Acceptance: both are in the World for nodes in a graph; clone still shares particle systems and does not copy audio players; particle and audio tests pass.

---

## 278: Action state is not stored in the World

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:m
depends: 274
created: 2026-11-05T19:12:42Z
updated: 2026-11-05T19:46:07Z
closed: 2026-11-05T19:46:07Z
+++

Part of #268. runningActions and actionSpeed live on Node, so an ECS app cannot see or drive a node's actions.

Acceptance: both are in the World for nodes in a graph; actions keep running when a node moves inside a graph; action tests pass.

---

## 279: Visibility, opacity, masks, pivot, rendering order and label are not stored in the World

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, subtask, effort:m
depends: 274
created: 2026-11-05T19:12:43Z
updated: 2026-11-05T19:40:58Z
closed: 2026-11-05T19:40:58Z
+++

Part of #268 (added to its scope per schwa). isVisible, isActive, opacity, pivot, categoryBitMask, lightCategoryBitMask, renderingOrder and label live on Node. Flatten and culling (#267) need these.

Acceptance: these fields are in the World for nodes in a graph; direct World writes bump the same revision the Node setters do; existing tests pass.

---

## 280: Archive and clone are untested for nodes in a graph

+++
status: closed
priority: low
kind: task
labels: area:scenegraph, subtask, effort:s
depends: 275, 276, 277, 278, 279
created: 2026-11-05T19:12:43Z
updated: 2026-11-05T19:49:16Z
closed: 2026-11-05T19:49:16Z
+++

Part of #268. Archive and clone go through Node's public properties and are tested with nodes outside a graph. After the fields move to the World, nodes inside a graph are not covered.

Acceptance: tests archive and clone subtrees that are in a graph, including one with app components on its entities; any bug found is fixed.

---

## 281: Constraints and subdivision are not stored in the World

+++
status: closed
priority: low
kind: feature
labels: area:scenegraph, effort:m
depends: 274
created: 2026-11-05T19:12:43Z
updated: 2026-11-05T19:48:17Z
closed: 2026-11-05T19:48:17Z
+++

Part of #250. constraints (and their accelerationStates) and subdivisionLevel/subdivisionBase live on Node. Not covered by #268's subtasks.

---

## 282: SwiftECS is a local path dependency, so SceneSprockets does not build elsewhere

+++
status: closed
priority: medium
kind: task
labels: area:scenegraph, effort:s
created: 2026-11-05T23:02:28Z
updated: 2026-11-06T04:47:21Z
closed: 2026-11-06T04:47:21Z
+++

Package.swift depends on SwiftECS with .package(path: "../../Current/SwiftECS"). The SwiftECS changes SceneSprockets needs (#263-#281, SwiftECS #46-#49) are committed only locally; SwiftECS has no pushed release tag. Any other checkout, including CI, fails to resolve the package. Related: #250.

- `2026-11-06T04:47:21Z`: Fixed: Package.swift depends on https://github.com/schwa/SwiftECS, upToNextMinor from 0.1.0 (resolves 0.1.1).

---

## 283: Node access performance has no reproducible benchmark

+++
status: closed
priority: low
kind: task
labels: area:scenegraph, effort:m
created: 2026-11-05T23:08:55Z
updated: 2026-11-06T00:25:58Z
closed: 2026-11-06T00:25:58Z
+++

Node and scene graph performance since the ECS port (#250, #270) was measured only with temporary test files, which were deleted. There is no permanent benchmark to compare changes against, or for an autoresearch loop to optimize.

Metrics used so far (Release, 100k nodes, ns per node):

| Metric | What it represents | Current | Before ECS |
|---|---|---|---|
| Flatten after one transform change | per-frame render prep while animating | ~280-300 | ~300 |
| Traversal (graph.visit) | simulation passes (actions, constraints, particles) | ~280-300 | ~100 |
| Attached transform read | per-property cost | ~100-140 | ~30 |
| Attached transform write | animation and physics writes | ~500-700 | ~180 |
| Create + attach | loading and adding nodes | ~9,700 | not measured |

Noise: back-to-back runs of the same code on the development machine varied by 30-40%, larger than many of the differences being measured.

Related: #270.

- `2026-11-06T00:25:58Z`: Fixed by 'Add a node performance benchmark (#283)': NodePerformanceBenchmark.swift, SCENESPROCKETS_BENCHMARK=1, Release, run alone.

---

## 284: No DocC catalog for SceneSprockets

+++
status: closed
priority: medium
kind: documentation
labels: release, area:docs, effort:l
created: 2026-11-06T18:01:40Z
updated: 2026-11-07T00:29:14Z
closed: 2026-11-07T00:29:14Z
+++

The package has no Documentation.docc catalog: no landing page, no articles, no topic groups. Usage docs live in README.md and Documentation/Features.md, which DocC does not build. The other products (SceneSprocketsBlinnPhong, SceneSprocketsPBR, SceneSprocketsPhysics, SceneSprocketsAudio, SceneSprocketsGizmos, SceneSprocketsShaderMaterial) have no documentation landing pages either. SwiftECS has a catalog with a landing page and GettingStarted, Systems, Relationships, Observation, ParallelSystems and Performance articles.

- `2026-11-07T00:29:14Z`: Fixed: Documentation.docc catalogs for all seven targets. SceneSprockets has a landing page with curated topic groups and five articles (Getting Started, Rendering, Animation, Change Tracking and Queries, Working with the World), taken from the old Documentation/Usage.md, which is removed. The other six products have landing pages with an overview and topics. just check-docs (warnings as errors) passes; article code samples compiled in a temporary test file. README links point at the articles (all paths checked); the demo-test notes moved to Demo/Packages/SceneSprocketsDemos/README.md.

---

## 285: Documentation is not published and DocC warnings are not checked

+++
status: closed
priority: medium
kind: task
labels: release, area:docs, area:ci, effort:s
created: 2026-11-06T18:01:40Z
updated: 2026-11-06T18:12:05Z
closed: 2026-11-06T18:12:05Z
+++

No workflow builds the DocC documentation or publishes it to GitHub Pages, and nothing fails on DocC warnings (broken symbol links, missing parameter docs). SwiftECS has docc.yml (Pages) and docc-check.yml (warnings as errors).

- `2026-11-06T18:12:05Z`: Fixed: added swift-docc-plugin, .github/workflows/docc-check.yml (DocC with warnings as errors on push/PR) and .github/workflows/docc.yml (publish to GitHub Pages on main). Both build one combined archive for all seven library targets; documentation/ lists the modules and the Pages root redirects there. Verified locally: both command lines exit 0 with zero DocC warnings. Not verified on GitHub: the workflows pin Xcode 27.2 because Package.swift needs tools 6.4 (#291); whether macos-26 runners have it is unchecked. Pages must be enabled in the repo settings (source: GitHub Actions).

---

## 286: No CI

+++
status: closed
priority: high
kind: task
labels: release, area:ci, effort:m
created: 2026-11-06T18:01:40Z
updated: 2026-11-07T00:55:37Z
closed: 2026-11-07T00:55:37Z
+++

No GitHub Actions workflow builds or tests the package, the demos or Composer, or runs SwiftLint. SwiftECS has swift.yml and xcode.yml, generated by 'xcb ci generate --warnings-as-errors'.

- `2026-11-07T00:55:37Z`: Fixed: swift.yml (SwiftLint --strict; package build and tests with warnings as errors; Composer support tests) and xcode.yml (demo app for macOS, iOS and visionOS; Composer app for macOS), generated with 'xcb ci generate --xcode 27.2 --warnings-as-errors' plus a hand-added Composer job and test step. Verified locally: all of those pass. Fixes needed on the way: visionOS build failed (Ray3D ambiguous with the Spatial framework in TransformGizmo), test warnings (deprecated reversedDepth, unused values, a redundant #require, an always-true 'is') and leftover try after the Composer lint change. Not verified on GitHub: that macos-26 runners have Xcode 27.2, and that the GPU tests run on the runner VM's GPU.

---

## 287: Demos test catalogMatchesAppAndIDsAreUnique fails

+++
status: closed
priority: medium
kind: bug
labels: release, area:demo, area:ci, effort:s
created: 2026-11-06T18:01:40Z
updated: 2026-11-06T18:08:07Z
closed: 2026-11-06T18:08:07Z
+++

The SceneSprocketsDemos test catalogMatchesAppAndIDsAreUnique fails on main. CI that runs the demo tests will be red.

- `2026-11-06T18:08:07Z`: Fixed: the test was stale. SceneGraphDemos.all appends TreeAppreciatorDemoView (a custom DemoView, not a catalog Demo) after the catalog. The test now checks that the app lists the catalog demos first, in order, and that all app IDs are unique.

---

## 288: No root SwiftLint config and existing lint violations

+++
status: closed
priority: medium
kind: task
labels: release, area:ci, effort:m
created: 2026-11-06T18:01:40Z
updated: 2026-11-06T23:23:01Z
closed: 2026-11-06T23:23:01Z
+++

Only Demo/ and SceneSprocketsComposer/ have .swiftlint.yml; the library sources and tests have no config. The demos report about 163 violations. 'swiftlint --strict' as run in SwiftECS's CI would fail.

- `2026-11-06T23:23:02Z`: Fixed for the root package and the demos: root .swiftlint.yml (strict only_rules for Sources/ and Tests/, excludes Demo/ and SceneSprocketsComposer/, which keep their own configs), Tests/.swiftlint.yml relaxing force unwrap/cast, optional collections, identical operands, indentation (inline JSON) and prefer_key_path (#expect cannot expand key paths to rethrowing functions). Demo/.swiftlint.yml now excludes build output and turns off size and naming rules. swiftlint --strict is clean in both. Composer's 255 violations are split out as #296.

---

## 289: No Swift Package Index config

+++
status: closed
priority: low
kind: task
labels: release, area:docs, effort:xs
created: 2026-11-06T18:01:41Z
updated: 2026-11-06T18:12:50Z
closed: 2026-11-06T18:12:50Z
+++

There is no .spi.yml, so Swift Package Index would not link to the hosted docs or know which targets to document.

- `2026-11-06T18:12:50Z`: Fixed: .spi.yml links Swift Package Index to the GitHub Pages docs (https://schwa.github.io/SceneSprockets/documentation/, the combined archive from #285), like SwiftECS.

---

## 290: No Justfile for docs preview and check

+++
status: closed
priority: low
kind: task
labels: release, area:docs, effort:xs
created: 2026-11-06T18:01:41Z
updated: 2026-11-06T18:33:27Z
closed: 2026-11-06T18:33:27Z
+++

There is no Justfile with recipes to preview the docs and build them with warnings as errors, as SwiftECS has (preview-docs, check-docs).

- `2026-11-06T18:33:27Z`: Fixed: Justfile with preview-docs (target parameter, default SceneSprockets) and check-docs (combined archive for all seven library targets, warnings as errors; same command as the DocC Check workflow). Verified: check-docs exits 0; preview-docs serves documentation/scenesprockets (HTTP 200 on localhost:8080).

---

## 291: Swift tools version does not match the documented requirement

+++
status: closed
priority: medium
kind: bug
labels: release, area:scenegraph, effort:s
created: 2026-11-06T18:01:41Z
updated: 2026-11-06T22:15:37Z
closed: 2026-11-06T22:15:37Z
+++

Package.swift declares swift-tools-version 6.4, but README.md says Swift 6.2. Either the README is wrong or users on Swift 6.2 cannot resolve the package. SwiftECS lowered its tools version to 6.2 for release.

- `2026-11-06T18:08:36Z`: Tried to resolve. Findings: the manifest uses no 6.4-only features; all direct dependencies declare tools 6.2 or lower (transitive swift-collections resolves a 6.4 release, but older releases support 6.2); no code gates on compiler 6.3/6.4 or OS 27. Punting: this machine has only Swift 6.4.x toolchains (Xcode 27.2, 27.3 beta, swift-6.4.1), so I cannot check that the sources compile with Swift 6.2, and which version to support is a product decision. Unblocker: decide whether the release supports Swift 6.2 (lower tools to 6.2 and verify on Xcode 26.x, e.g. via CI from #286) or requires 6.4 (change the README).
- `2026-11-06T22:15:38Z`: Fixed per user: swift-tools-version lowered to 6.2 to match the README; the package is still built with the Swift 6.4 compiler. Root package builds with 0 warnings, 327 tests pass, demos build, check-docs passes. DocC workflow comments updated (they still pin Xcode 27.2).

---

## 292: README is not ready for a public release

+++
status: closed
priority: medium
kind: documentation
labels: release, area:docs, effort:m
created: 2026-11-06T18:01:41Z
updated: 2026-11-07T00:19:09Z
closed: 2026-11-07T00:19:09Z
+++

README.md has no screenshot, no installation snippet (.package(url:...)), no feature list linking to docs, and no docs link. It links MetalSprocketsPBR as ../MetalSprocketsPBR, which is broken on GitHub. Much of the README is detailed usage that would belong in DocC. SwiftECS's README is a short pitch, captioned screenshot, linked feature list, requirements, install snippet, short usage, docs link and license.

- `2026-11-07T00:19:09Z`: Fixed: README rewritten after SwiftECS's: pitch, captioned Gears screenshot (Images/gears.png), feature list linked to the DocC pages (paths checked against a local build), requirements, install snippet, product table, a short compiled usage sample, demos, limitations, docs link, license. Broken ../MetalSprocketsPBR link removed. Detailed usage moved to Documentation/Usage.md (until the DocC catalog, #284); two stale claims fixed there (fade actions and IK exist). The install snippet assumes the first tag is 0.1.0 (#295).

---

## 293: Docs are not written in Simple English

+++
status: closed
priority: low
kind: documentation
labels: release, area:docs, effort:m
created: 2026-11-06T18:01:41Z
updated: 2026-11-07T15:11:02Z
closed: 2026-11-07T15:11:02Z
+++

The README, Documentation/Features.md and any new DocC articles have not been reviewed against the Simple English (ASD-STE100) rules used for SwiftECS's docs.

- `2026-11-07T15:11:02Z`: Fixed: README, CHANGELOG, demo package README, the Features.md intro, and all DocC pages reviewed against the simple-english skill (pragmatic mode): sentences at most 25 words, no should/may/might/could/would, no semicolons outside code, passive voice with a known agent made active, conditions before commands, one instruction per sentence, American spelling (modeled). The Features.md tables were not rewritten; their content is out of date (save/load, debug views, gizmos and the ECS are listed as missing). just check-docs passes.

---

## 294: Unused code has not been checked before release

+++
status: closed
priority: low
kind: task
labels: release, area:scenegraph, effort:s
created: 2026-11-06T18:01:42Z
updated: 2026-11-06T18:36:42Z
closed: 2026-11-06T18:36:42Z
+++

There is no Periphery config, and the public API has not been checked for unused or leftover declarations. SwiftECS has a .periphery.yml.

- `2026-11-06T18:36:42Z`: Fixed: .periphery.yml (retain public, assign-only properties and protocol func params; report only Sources/ and Tests/), with the two-step scan command for Swift Build in a comment. Removed two unused imports (SceneSprocketsAudio in Node.swift, SceneSprocketsBlinnPhong in FlattenTests.swift). Other findings were false positives: Hashable cache-key and GPU-layout properties, public protocol parameters, and SwiftUI @State twoFingerClaim (periphery:ignore). The scan now reports no unused code. Dependency checkouts also have findings; not ours, not changed.

---

## 295: No release tag or release notes

+++
status: open
priority: medium
kind: task
labels: release, effort:s
created: 2026-11-06T18:01:42Z
updated: 2026-11-06T18:03:14Z
+++

SceneSprockets has no version tag and no release notes, so SwiftPM users cannot depend on a version, and there is no summary of what the first release contains.

- `2026-11-06T18:12:40Z`: Release notes added in CHANGELOG.md under 'Unreleased' (products, features, link to README limitations). Left open: the version number and the git tag are for the user to choose and create; when tagging, rename 'Unreleased' to the version. Also noticed Documentation/Features.md is stale: save/load (SceneArchive), debug views and gizmos (SceneSprocketsGizmos) are marked not done, and the entity-component system is struck through although nodes now live in a SwiftECS World. The notes follow the code, not that table.

---

## 296: SceneSprocketsComposer has 255 SwiftLint violations

+++
status: closed
priority: medium
kind: task
labels: release, area:composer, area:ci, effort:m
created: 2026-11-06T23:22:52Z
updated: 2026-11-07T00:08:46Z
closed: 2026-11-07T00:08:46Z
+++

Linting SceneSprocketsComposer/ with its own .swiftlint.yml reports 255 violations, so 'swiftlint --strict' fails there. Largest groups: sorted_enum_cases 40, vertical_whitespace_between_cases 34, discouraged_optional_collection 34, explicit_enum_raw_value 30, variable_shadowing 20, discouraged_default_parameter 18, multiline_arguments 10, and size rules (function_parameter_count, closure_body_length, file_length, cyclomatic_complexity, type_body_length). The root package and the demos lint clean (#288).

- `2026-11-07T00:08:46Z`: Fixed pragmatically: turned off burden rules in Composer's config (enum case order and raw values, blank lines between cases, default parameters, optional collections/booleans, shadowing, multiline arguments, empty blocks, size rules, redundant_discardable_let), ran --fix, added accessibility labels to the visibility/lock icons and hid the decorative CPU icon. swiftlint --strict is clean; Composer builds with 0 warnings; 52 support tests pass.

---

## 297: A test writes past a texture's width (AGX 'Region width OOB' assertion)

+++
status: closed
priority: low
kind: bug
labels: area:renderer, effort:s
created: 2026-11-07T00:55:29Z
updated: 2026-11-07T15:07:41Z
closed: 2026-11-07T15:07:41Z
+++

Running the SceneSprockets test suite prints, twice:

AGX: Texture read/write assertion failed: (xoffset + width) <= ALIGNGRAN_NPOT(getViewLevelWidth(mipmapLevel), block_width) && "Region width OOB"

All tests pass. Tests run in parallel, so the log does not show which test triggers it; it appears near nonReceiversAreNotDarkened, blinnPhongSkinnedBoxFollowsJoint, textShapeHasUnitNormals and ambientOcclusionDarkensContactsOnly. Seen with Xcode 27.2 on Apple silicon.

- `2026-11-07T15:07:41Z`: Fixed: a test bug, not a renderer bug. ambientOcclusionDarkensContactsOnly read its 'open floor' point [2, 0, 2], which projects to pixel (72, 56), outside the 64x64 texture; getBytes then read out of bounds (the AGX assertion), and the test's second expectation compared garbage. pixel() now requires the pixel to be inside the texture, and the open point is [1.5, 0, 1.5]. The full suite runs with no AGX assertion.

---

## 298: Blinn-Phong and ShaderMaterial deform morph targets and skins on the CPU every frame

+++
status: open
priority: low
kind: enhancement
labels: area:renderer, effort:l
created: 2026-11-07T15:41:12Z
+++

The PBR renderer deforms morph targets and skins on the GPU. Blinn-Phong and ShaderMaterial meshes are deformed on the CPU each frame (SceneGraph.MeshEntry.deformed(revision:)), which is slow for large meshes. Listed under Limitations in the README.

---

## 299: Lights beyond 8 shadow map slices cast no shadow

+++
status: open
priority: low
kind: enhancement
labels: area:renderer, effort:m
created: 2026-11-07T15:41:12Z
+++

SceneGraphShadows has 8 shadow map slices: a directional or spot light takes one, a point light six. Lights that do not fit cast no shadow; SceneGraphShadows.droppedLightCount counts them (#68). A scene with two point lights already loses one light's shadows. Listed under Limitations in the README.

---

## 300: ShaderMaterial meshes get every light's shadow, not only the lights that light them

+++
status: open
priority: low
kind: bug
labels: area:renderer, effort:m
created: 2026-11-07T15:41:12Z
updated: 2026-11-07T15:41:13Z
+++

Blinn-Phong and PBR sample each light's shadow while shading (#102), so a light darkens only what it lights. ShaderMaterial meshes are darkened afterwards by a screen-space pass that applies all lights' shadows together, so a shadow from one light also darkens areas that other lights light. Listed under Limitations in the README.

---

## 301: glTF animation channels with unsupported pointers are skipped

+++
status: open
priority: low
kind: enhancement
labels: area:assets, area:animation, effort:s
created: 2026-11-07T15:41:13Z
+++

GLTFSceneGraph skips KHR_animation_pointer channels whose pointer it does not support, such as camera xmag and aspectRatio, and reports '<n> animation channels skipped' in warnings. Listed under Limitations in the README.

---

## 302: Model I/O loading skips skins, blend shapes and orthographic cameras

+++
status: open
priority: low
kind: enhancement
labels: area:assets, effort:l
created: 2026-11-07T15:41:13Z
+++

ModelIOSceneGraph does not import skins or blend shapes, and imports only perspective MDLCameras (orthographic cameras are skipped). glTF loading supports all three. Listed under Limitations in the README.

---

## 303: Hit testing, bounds and PBR conversion need vertex buffers in shared storage

+++
status: open
priority: low
kind: enhancement
labels: area:scenegraph, effort:m
created: 2026-11-07T15:41:13Z
updated: 2026-11-07T15:41:14Z
+++

Positions for hit tests, bounds and PBR model conversion are read from mesh vertex buffers on the CPU. Meshes whose vertex buffers use private storage cannot be hit-tested, have no bounds, and cannot be converted. Listed under Limitations in the README.

---

## 304: Keynote has no level of detail slide

+++
status: open
priority: low
kind: feature
labels: area:demo, effort:s
created: 2026-11-07T15:44:43Z
+++

Levels of detail (Node.levelsOfDetail, like SCNLevelOfDetail) are not shown anywhere in the Keynote demo. Nothing on a slide shows a node switching meshes as its distance from the camera changes.

---

## 305: Keynote has no debug views slide

+++
status: open
priority: low
kind: feature
labels: area:demo, effort:m
created: 2026-11-07T15:44:43Z
+++

The debug views (SceneGraphDebugMode: shaded, normals, texture coordinates, UV checker, world position, wireframe) and material channels (SceneGraphMaterialChannel) are not shown in the Keynote demo. The demo framework (SceneDemo) has no way to set a debug mode or material channel on the view for one slide.

---

## 306: Keynote has no transform gizmo or selection outline slide

+++
status: open
priority: low
kind: feature
labels: area:demo, effort:m
created: 2026-11-07T15:44:43Z
+++

SceneSprocketsGizmos (TransformGizmo, SelectionOutline) is not shown in the Keynote demo. The Keynote's SceneView has no manipulator or overlay, so a slide cannot show the gizmo's handles or an outline around a selected node.

---

## 307: Keynote has no slide for the SwiftECS world

+++
status: open
priority: low
kind: feature
labels: area:demo, effort:m
created: 2026-11-07T15:45:06Z
updated: 2026-11-07T15:45:07Z
+++

The Keynote demo does not show that node data lives in a SwiftECS World (SceneGraph.world, #250), or that an ECS app can query and write node components directly.

## Proposed slide (per schwa)
3D boids: a flock of nodes moved by a SwiftECS system that reads and writes NodeTransformComponent through sceneGraph.world. SwiftECS has a 2D Boids demo with a parallel flocking system to draw from.

---
