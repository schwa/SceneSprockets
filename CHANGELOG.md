# Changelog

## Unreleased

- `SceneView` documents that two views must not draw one scene graph, or share renderer objects, at the same time (#481).
- Path point editing (#619). `PathPointGizmo` (SceneSprocketsGizmos) draws a handle on each point of a node's path and moves a point when you drag its handle, in the plane facing the camera. `ManipulatorGroup` combines manipulators for `sceneManipulator(_:)`. The Composer shows paths and puts point handles on the selected node's path; a point drag is one undo step.
- Clustered lighting no longer drops lights when more than 63 reach one cluster (#628). The cluster is shaded with every light instead, so dense light fields no longer show rectangular tiles. `Lighting::lightList` returns the full light list for such clusters.
- `CharacterController` climbs low steps at any walking speed (#625). Below about 2 units per second, the velocity into the step was cancelled as a steep slope, so the character stood at the step.
- The statistics panel sums GPU passes with the same label into one row ("Simulate ×6"), keeps each row on one line, and its collapsed bar fits its contents instead of the view's width (#621). It redraws four times a second instead of every frame, so it no longer flickers, and the sparkline's scale steps between fixed frame-time ceilings (60, 30, 20, 10, 5 fps) instead of following the history's maximum, so the line no longer jumps when a slow frame enters or leaves it.
- `EditorGizmos.shapes` and `element` take a `gridTransform` that places the grid and axes, which were fixed at the world origin (#617).
- MaterialX node graphs and shaders (#609). Math nodes on constants (`constant`, `add`, `subtract`, `multiply`, `divide`, `min`, `max`, `power`, `mix`, `clamp`, `invert`, `extract`, `combine2`–`4`, `convert`, `dot`) are folded, nodegraph `interfacename` inputs are followed, and an image multiplied by a constant becomes a texture with that factor. `gltf_pbr` and `open_pbr_surface` load too (OpenPBR emission luminance is mapped as 1000 nits = factor 1). Per-pixel nodes are still skipped (#620).
- Path nodes (#607). `Node.path` holds a `SceneGraph.Spline` in the node's space; it moves with the node and is saved in archives. `Constraint.followPath(_:fraction:orientsToPath:)` keeps a node at a fraction along a path node's curve. `EditorGizmos` draws paths (`.paths`, in `.all`) and picks their nodes on click.
- Hit testing lines and points (#605). Set `HitTestOptions.lineAndPointTolerance` (world units) to hit line, line strip and point submeshes the ray passes within that distance of. The hit is the nearest point on the primitive; `triangleIndex` is the segment or point index. 0, the default, never hits them, as before.
- Volumetric fog (#540). `SceneGraph.Fog.scattering` (`density`, `intensity`, `anisotropy`, `stepCount`, `maximumDistance`) marches each pixel's ray in the fog pass: the fog dims what is behind it and scatters every direct light toward the camera (Henyey-Greenstein phase), shadowed by the scene's shadow map, so light beams and shadow shafts show, over the background too. The distance fog still applies afterward; set its color alpha to 0 for volumetric fog alone. Scattered light is added to the renderers' tone-mapped output, so tune `intensity` per scene. The Shadows demo has a Volumetric Fog toggle.
- MaterialX materials (#528), in the `SceneSprocketsMaterialX` library. `MaterialXDocument(url:)` reads a `.mtlx` file and makes a `PBRSceneMaterial` for each `surfacematerial` using `standard_surface` or `UsdPreviewSurface`: base color, metalness, roughness, opacity, emission, IOR, specular, coat, sheen and transmission values, and base color, metalness, roughness, normal, occlusion and emission images, connected directly or through a nodegraph output (`fileprefix` is honored). Separate metalness and roughness images are packed into one texture. Other node graphs are not evaluated (#609); those inputs keep their defaults and appear in `warnings`.
- Clustered light assignment (#519). With 16 or more direct lights, `SceneGraphElement` runs a compute pass that assigns lights to a 16 x 9 x 24 grid of view clusters (`LightingClusters` in MetalSprocketsLighting), and Blinn-Phong and PBR fragments loop over their cluster's lights instead of every light; images match the unclustered result. `SceneGraphElement.lightClustering(_:)` sets `.automatic` (default), `.on` or `.off`. Not used in stereo frames, for batches lit by only some lights (light category masks), or by shader materials, which loop over every light. A cluster holds at most 63 lights. `BlinnPhong::shade` and `PBR::shade` take optional cluster inputs; existing calls are unchanged. New Many Lights demo; `LightClusteringBenchmark` (SCENESPROCKETS_BENCHMARK=1) measured 256 short-range lights at 1920 x 1080 going from 5.2 to 2.3 ms (Blinn-Phong) and 10.0 to 3.7 ms (PBR) on an M5 Max.
- **Breaking:** `GLTFAsset.warnings` is `[GLTFWarning]` instead of `[String]` (#562). Each warning has a `kind` to check in code and a `description` with the old text; use `.map(\.description)` where strings are needed. Non-material extensions (instancing, image-based lights, node visibility, variants) now come from one internal table like the material features, and `Resources.load` is split into steps.
- **Breaking (exhaustive switches):** ambient light nodes (#602). `Light.Kind.ambient` lights every surface in its categories by `color * intensity`, without shading or shadows, like SCNLight's `.ambient`, so ambient light can be animated, archived and masked. `RenderContext.ambientLight` sums a batch's ambient lights; Blinn-Phong adds it to the renderer's `ambientLightColor`, PBR adds it to the diffuse image-based light (`PBRLighting.ambientLight`), and shader materials get `ShaderMaterialLighting.ambientLight` (the `lit` sample uses it). A `switch` over `Light.Kind` needs the new case.
- **Breaking (exhaustive switches):** explicit instancing (#135). `Node.Content.instancedMesh(_:materials:transforms:castsShadow:receivesShadow:)` (and `instancedMesh(_:material:transforms:)`) draws many copies of a mesh from one node, one per transform in the node's space. Each copy becomes its own mesh entry, so every renderer, culling, shadows, levels of detail and hit testing handle it like a mesh node, without a node and entity per copy. `MeshEntry.instanceIndex` and `Hit.instanceIndex` name the copy. Shapes and archives support it. Physics bodies and subdivision do not use instanced meshes yet. A `switch` over `Content` needs the new case.
- **Breaking:** exposure and tone mapping are scene settings for every renderer (#501): `SceneGraph.Environment.exposure` (a multiplier, default 1) and `toneMapping` (`LightingToneMapping`, default PBR Neutral), saved in archives. `PBRMaterialRenderer`'s `exposure` is removed. Blinn-Phong (and surfaces lit with `BlinnPhong::shade`) now tone-maps its output, so bright highlights compress instead of clipping and colors look slightly different; set `toneMapping = .linear` for the old clamped output. Shader materials with `samplesShadows` get `exposure`, `toneMapping` and `linearOutput` in `ShaderMaterialLighting`, and `shaderMaterialDisplayColor` applies them. `RenderContext.outputIsLinear` is set for content drawn behind PBR glass.
- Blinn-Phong binds its textures through argument buffers (#546).
- **Breaking:** all renderers share MetalSprocketsLighting's lights and shadows (#547). Blinn-Phong and shader materials use the glTF `KHR_lights_punctual` falloff that PBR uses (inverse square with a smooth cutoff at `range`, intensity separate from color), so scenes with lights close to surfaces look brighter than before (#548, #549). `BlinnPhongLight`, `BlinnPhongShadowUniforms` and `ShaderMaterialLight` are replaced by `LightingLight` and `LightingShadowUniforms`; `BlinnPhongLighting.h`'s `sliceShadow` by `Lighting::sliceShadow` and `Lighting::shadow`. `ShaderMaterialLighting` keeps only `lightCount` and `receivesShadow`; shader materials with `samplesShadows` also get `shadow` (`LightingShadowUniforms`) and light with `Lighting::sample` and `shaderMaterialShadow(lighting, light, position, shadow, shadowMap, shadowSampler)`. `Shadows.Sampling.uniforms` gives every renderer the same shadow uniforms (#550). Requires MetalSprocketsPBR 0.3.0 and MetalSprocketsGLTF 0.2.0 (#551).
- **Breaking:** requires MetalSprocketsPBR 0.2.6 (immutable `PBRMaterial`), MetalSprocketsGLTF 0.1.1 and MetalSprockets 0.3.3. `PBRSceneMaterial` can now be changed while a view renders it (#479): set `uniforms`, `renderState` or `textureTransforms` on the scene material (or assign a new `pbrMaterial`), and the change shows on the next frame without rebuilding the model unless it moves the material to another pass. glTF meshes that use the same material share one `PBRSceneMaterial`, and material animation changes it the same way.
- **Breaking:** ambient occlusion is a lighting setting: `SceneGraph.Environment.ambientOcclusion` replaces `PostProcessing.ambientOcclusion` (#136). It is computed from a depth pre-pass before shading (a second geometry pass while it is on). Blinn-Phong darkens only its ambient light and PBR only its image-based light (#408, requires MetalSprocketsPBR 0.2.1); emission and direct light are unchanged. Other materials, such as shader materials, are still darkened as a whole after the scene pass. Older archives load their setting.
- Faded meshes blend as one surface instead of back faces then front faces, and glass refracts faded and transparent meshes of other renderers (#327).
- **Breaking (deprecated aliases kept):** prefixes dropped where the plain name does not clash (#370): `SceneArchive`→`Archive`, `SceneArchiveContext`→`ArchiveContext`, `SceneArchiveError`→`ArchiveError`, `SceneAudio`→`Audio`, `SceneCameraControl`→`CameraControl`, `SceneGraphShadows`→`Shadows`, `SceneViewport`→`Viewport`, `SceneGraphRenderContext`→`RenderContext`, `SceneGraphMaterialRenderer`→`MaterialRenderer`, `SceneGraphBackgroundRenderer`→`BackgroundRenderer`, `SceneGraphPrePassRenderer`→`PrePassRenderer`, `SceneGraphDebugMode`→`DebugMode`, `SceneGraphMaterialChannel`→`MaterialChannel`, `SceneGraphMembershipComponent`→`MembershipComponent`, `SceneViewDelegate`→`ViewDelegate`, `SceneViewManipulator`→`ViewManipulator`. `SceneView`, `SceneGraphElement`, `SceneGraphPhysicsWorld`, `SceneGraphShadowMap`, `SceneMaterial` and `SceneParticleSystem` keep their prefix (clashes). `Light.LightType`→`Light.Kind`; `rotateBy(x:y:z:)`/`rotateTo(x:y:z:)`→`rotate(byEuler:)`/`rotate(toEuler:)`; renderer helpers `culledMeshEntries`, `sortedFrontToBack`, `groupedByVertexDescriptor`, `distanceSquared`, `cameraRelative` are no longer public.
- **Breaking:** `BlinnPhongSceneMaterial.normalMap` is a `Source?` (#368). Wrap textures in `.texture(_:)`; a tint scales the decoded normal (`[s, s, 1]` sets bump strength) and `.color(_:)` is one tangent-space normal. Older archives still load.
- **Breaking:** one way to load models (#371). `ModelFile.load(_:materials:)` (and overloads for a loaded `GLTFAsset` or `MDLAsset`) returns a `ModelFile.Result` for every format: `node`, `animations`, `warnings`, glTF `variants` (`names`, `select(_:)`) and `environmentMap`. `GLTFSceneGraph`, `GLTFAsset.makeSceneGraph()` and `ModelIOSceneGraph` are no longer public; Model I/O's single `animation` is now part of `animations`.
- **Breaking:** `SceneView` has a short initializer, `SceneView(_:pointOfView:renderers:)`, and `scene…` methods for everything else (#369): `sceneCameraControl()`, `sceneDefaultLighting()`, `sceneShadows(_:)`, `sceneAudio(_:)`, `sceneDelegate(_:)`, `scenePlaying(_:)`, `sceneCamera(matrix:target:override:)`, `sceneDefaultCamera(_:)`, `sceneHitTestOptions(_:)`, `onSceneTap(id:perform:)`, `sceneManipulator(_:)`, `sceneDecorations(id:_:)`, `sceneOverlay(id:_:)`, `sceneDebugMode(_:)`, `sceneMaterialChannel(_:)`, `sceneStatistics()`, `sceneFrameTiming()` and `sceneReadableDrawable()`. `SceneView.Options` and `closuresID` are removed; each closure takes its own `id:`. A mesh whose material has no renderer logs a warning once.
- **Breaking:** materials are simpler to make (#368). The `Material` protocol is now `SceneMaterial` (it clashed with SwiftGLTF's `Material`). `BlinnPhongSceneMaterial(color:shininess:opacity:emission:)` makes a material from one color. `PBRSceneMaterial(baseColor:opacity:metallic:roughness:)` takes an RGB color and a separate opacity and no longer throws; `ShaderMaterial.normals()`, `.rim(color:opacity:)` and `.lit(color:opacity:)` no longer throw either.
- **Breaking:** back-face culling lives in `MaterialRenderState.cullMode` (default `.none`) for Blinn-Phong and shader materials (#377). `BlinnPhongSceneMaterial.cullMode` and its initializer parameter are removed; shader materials now cull too. PBR keeps glTF's `doubleSided`. Old archives load their culling.
- **Breaking:** `PBRSceneMaterial` is a final class (#375). It wraps a shared `PBRMaterial`, so copies already shared state; now the sharing is explicit, like `SCNMaterial`.
- **Breaking:** `SceneGraph.hitTest(_:categoryBitMask:)` is removed; pass the mask in `HitTestOptions`: `hitTest(ray, options: .init(categoryBitMask: mask))`. `hitTest(_:options:)` now defaults its options (#376).
- **Breaking:** `ShaderMaterial.isTransparent` is read-only, derived from the new `usesAlphaBlending` and the render state's blend mode, so it reads back what was set (#374). The initializer's `isTransparent:` parameter is now `usesAlphaBlending:`. Archives are unchanged.
- Shorter node construction (#367): `Node.light(_:label:transform:)` and `Node.camera(_:label:transform:)`, so `root.addChild(.light(.point(intensity: 15), transform: .init(translation: [0, 4, 0])))` is one expression. `Light.point(...)` and `Light.directional(...)`, and `castsShadow` on `Light.spot(...)`. `Camera.perspective(...)`, `Camera.orthographic(...)` and `Camera.default`; `SceneView.defaultCamera` is deprecated in favor of `Camera.default`. Aimed nodes use GeometryLite3D's `Transform3D(position:lookingAt:up:)`, so the tutorials no longer need `look(at:)` or local helpers.
- **Breaking:** `Node.transform` is now a GeometryLite3D `Transform3D` and the only stored local transform (#372). `trs`, `localTransform`, `eulerAngles` and `SceneGraph.LocalTransform` are removed. Use `transform.translation`, `transform.rotation` (`.quaternion`, `.euler`), `transform.scale` and `transform.matrix`. Initializers take `transform: Transform3D`; wrap a matrix with `Transform3D(storing:)`. Archives are unchanged.
- **Breaking:** requires GeometryLite3D 0.3: `Transform3D.rotation` is a `Rotation3D` (#378).
- Shadows with `softness` above 1 no longer make a floor shadow itself in bands and stripes (#366).
- `ShaderMaterial` can shade each light with its own shadow: set `samplesShadows`, and use `shaderMaterialShadow` from `ShaderMaterial.h`. `ShaderMaterial.lit(color:)` is a sample (#300).
- Blinn-Phong, shader-material and debug-view meshes are morphed and skinned on the GPU, in a compute pass before the scene pass, instead of on the CPU every frame (#298).
- `SceneView` debug options can be turned on with the `SS_SHOWS_STATISTICS`, `SS_SHOWS_FRAME_TIMING` and `SS_DISABLES_FRAMEBUFFER_ONLY` environment variables (#365).

## 0.0.3

- SwiftLint no longer checks the DocC catalogs.

## 0.0.2

- DocC tutorials, with the `SceneSprocketTutorials` example app.
- One shared Metal device: the API no longer takes `MTLDevice` parameters (#354, #357).
- `addChild(_:)` returns the child. `Node(parent:)` is removed (#361).
- The demo app moved to `Examples/SceneSprocketsDemo`.

## 0.0.1

The first release of SceneSprockets: a format-neutral 3D scene graph for [MetalSprockets](https://github.com/schwa/MetalSprockets), with an API modeled on SceneKit.

SceneSprockets needs Swift 6.2 or later, and iOS, macOS or visionOS 26 or later.

### Products

- `SceneSprockets`: the scene graph, renderer, and `SceneView`.
- `SceneSprocketsBlinnPhong`: Blinn-Phong materials.
- `SceneSprocketsPBR`: PBR materials, glTF loading, and Model I/O loading.
- `SceneSprocketsShaderMaterial`: materials with custom vertex and fragment shaders.
- `SceneSprocketsPhysics`: rigid-body physics on Jolt.
- `SceneSprocketsAudio`: positional audio on nodes.
- `SceneSprocketsGizmos`: transform gizmos and selection outlines.

Optional generators, such as `PointCloud`, are in the separate SceneSprocketsAddOns package.

### Scene graph

- Node hierarchy, TRS or matrix transforms, pivots, and conversion between spaces.
- Visibility, inherited opacity, rendering order, and category masks for cameras, lights and hit tests.
- `clone()`, `flattenedClone()`, bounds, scene statistics, and revisions for change tracking.
- Saving and loading scenes with `SceneArchive`.
- Node data in a [SwiftECS](https://github.com/schwa/SwiftECS) `World`. `SceneGraph.world` gives your queries and systems access to it.

### Geometry

- Box, sphere, plane, cylinder, cone, capsule, torus, tube, pyramid, floor, Utah teapot, extruded text, and extruded path shapes.
- Any SwiftMesh mesh, with one material per submesh.
- Subdivision, levels of detail, automatic instancing, and frustum culling.

### Cameras, lights and rendering

- Built-in camera control in `SceneView`, configured with `sceneCameraControl(_:)`: turntable or arcball, rotate, zoom and pan speeds, and distance and pitch limits.
- Perspective and orthographic cameras. Directional, point and spot lights, with per-node light masks and default lighting.
- Shadow maps for all light types, with intensity, color, softness, bias, and per-mesh cast and receive settings.
- Color or environment backgrounds, fog, screen-space ambient occlusion, and post-processing (exposure, contrast, saturation, vignette).
- Blend modes, depth and color masks, wireframe, and debug views.

### Materials

- Blinn-Phong: colors, textures, emission, normal maps, opacity.
- PBR metallic-roughness, with most glTF material extensions (transmission, volume, IOR, dispersion, specular, iridescence, anisotropy, sheen, clearcoat, and more), image-based lighting, and shadows.
- Custom shaders through `ShaderMaterial`.
- `MaterialTexture` loads textures from image files, `CGImage`s and asset catalogs. Blinn-Phong takes them with `.texture(contentsOf:device:)`, and `PBRSceneMaterial(device:textures:)` takes base color, metallic-roughness, normal, occlusion and emissive textures.
- `VideoTexture` shows an `AVPlayer`'s video in any material texture slot.

### Animation and constraints

- Actions (move, rotate, scale, fade, sequence, group, repeat), with timing modes and per-node speed.
- Implicit animation through transactions.
- Keyframed clips, animation events, blending (mixer, layers, additive), root motion, and an animation state machine.
- Morph targets and skinning.
- Constraints: look-at, billboard, replicator, avoid-occluder, distance, inverse kinematics, acceleration, slider, and custom transforms.

### Physics, particles and interaction

- Static, dynamic and kinematic bodies with box, sphere, capsule, cylinder, convex hull and mesh shapes.
- Mass, friction, restitution, gravity, velocities and impulses.
- GPU particles on nodes, including soft particles and emitters on skinned meshes.
- Ray and segment hit tests, point projection, and frustum queries.
- SwiftUI `SceneView` with camera control, taps and delegates.

### Assets

- glTF: meshes, skins, morph targets, animations, cameras, materials and punctual lights.
- glTF extensions: material variants, animation pointers, node visibility, quantized meshes, GPU instancing and WebP textures. Meshopt compression and KTX2/Basis Universal textures are optional.
- Model I/O: OBJ, PLY, STL, ABC and USD, including USD skins and their joint animation. Model I/O does not expose blend shapes.
