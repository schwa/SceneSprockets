# SceneKit vs MetalSprocketsSceneGraph

A feature-by-feature comparison of SceneKit and MetalSprocketsSceneGraph (MSSG). It describes the code as of this commit. Issue numbers (`#NN`) refer to `ISSUES.md`.

Legend:

- ✅ Equivalent: MSSG has the feature, with about the same behavior.
- 🟡 Partial: MSSG has some of it, or it works differently. The notes give the difference.
- ❌ Missing: MSSG does not have it.
- ➕ MSSG only: SceneKit does not have it, or has no public API for it.

## Summary

| Area | Status | Main gaps |
|---|---|---|
| Scene and nodes | 🟡 | No `presentation` node, no serialization |
| Transforms | ✅ | TRS or matrix, pivot, Euler angles, world-space setters, space conversion, `look(at:)` |
| Geometry | 🟡 | No geometry sources/elements API (uses `MetalMesh`), no GPU tessellation, no `SCNShape` (Bézier extrusion), no tube or pyramid, no segment counts |
| Materials | 🟡 | No `SCNMaterial` with lighting models; no shader modifiers |
| Lights | 🟡 | Directional, point and spot only; no ambient light node, no IES, no area or probe lights |
| Cameras | 🟡 | Perspective only; SSAO, vignette, exposure, contrast and saturation, but no HDR, bloom, depth of field or motion blur (#45) |
| Shadows | 🟡 | Shadow maps for all three light types, but one global setting, max 8 slices |
| Animation | ✅ (different design) | Keyframe clips, blending, layers, state machine, events; no `CAAnimation` interop |
| Actions | 🟡 | No `follow(path:)`, no sound actions, no JavaScript actions |
| Implicit animation | 🟡 | Transform and morph weights only |
| Constraints | 🟡 | Look-at, billboard, distance, IK, replicator, avoid-occluder and transform; no acceleration or slider constraints, no influence factor |
| Morphing and skinning | ✅ | Four influences per vertex; CPU fallback for Blinn-Phong |
| Hit testing | ✅ | Triangles or bounding boxes, rays or segments, with SceneKit-style options |
| Physics | ❌ | Demo-only Jolt integration (#38) |
| Particles | 🟡 | CPU emitters drawn as soft sprites; no textures, image sequences or particle collisions |
| Audio | 🟡 | Positional `AudioPlayer`s on nodes, played by `SceneAudio`; no audio actions |
| Fog and environment | ✅ | Linear and exponent fog; color or IBL background |
| Rendering pipeline | 🟡 (different design) | No `SCNTechnique`, no render delegates at pass level; pluggable material renderers instead |
| SwiftUI view | ✅ | `SceneView` with camera control, default lighting, delegate, tap hit testing |
| Asset import | 🟡 | glTF (wide), Model I/O (OBJ, PLY, STL, ABC, USD); no skins/blend shapes from Model I/O, no native USDZ path (#31) |
| Asset export / archiving | ❌ | #52 |
| Platforms | 🟡 | iOS, macOS and visionOS 26 only; no watchOS or tvOS |

## Scene

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNScene` | `SceneGraph` | ✅ | A class holding `root`, `environment` and `fog`. |
| `SCNScene.rootNode` | `SceneGraph.root` | ✅ | Settable. Replacing it changes `revision`. |
| `SCNScene.background` | `SceneGraph.environment.background` | ✅ | `.none` (keep clear color), `.color(SIMD4)` (linear RGBA), `.environment(blur:)` (draws the environment map, blur 0…1). |
| `SCNScene.lightingEnvironment` | `environment.map`, `environment.intensity`, `environment.rotation` | ✅ | `map` is any `EnvironmentMap`; `PBREnvironment` conforms. Rotation is radians about +Y only. Blinn-Phong ignores the map. |
| `SCNScene.fogStartDistance`, `fogEndDistance`, `fogDensityExponent`, `fogColor` | `SceneGraph.fog: Fog?` | ✅ | Same four parameters. `color.w` scales the maximum amount. Applied as a screen-space compute pass after all renderers, on geometry only (not the background). Needs a readable depth texture. |
| `SCNScene.isPaused` | `SceneView(isPlaying:)` | 🟡 | A view parameter, not a scene property. Freezes delegate time and actions. |
| `SCNScene.physicsWorld` | — | ❌ | See [Physics](#physics). |
| `SCNScene.particleSystems` | Systems on the root node | 🟡 | |
| `SCNScene.screenSpaceReflection…` | — | ❌ | |
| `SCNScene(url:)`, `SCNScene(named:)` | `GLTFAsset.makeSceneGraph(device:)`, `ModelIOSceneGraph(url:device:)` | 🟡 | See [Asset import](#asset-import). |
| `SCNScene.write(to:)` / `NSSecureCoding` | — | ❌ | No save or load (#52). |
| `SCNSceneSource` | — | ❌ | No per-entry loading or progress. |
| `SCNScene.attribute(forKey:)` (start/end time, frame rate, up axis) | — | ❌ | Loaders do not expose asset metadata, except glTF `warnings`. |
| — | `SceneGraph.revision` | ➕ | A `(structure, transform)` pair from one global atomic counter. Compare it to skip work when nothing (or only transforms) changed. |

## Nodes

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNNode` | `SceneGraph.Node` | ✅ | A class. `Identifiable` by object identity. |
| `name`, `childNode(withName:recursively:)` | `label`, `childNode(withLabel:recursively:)` | ✅ | |
| `geometry` / `light` / `camera` (three separate slots) | `content: Content` (`.empty`, `.mesh`, `.light`, `.camera`) | 🟡 | One content per node. glTF nodes with a mesh plus a camera or light get extra child nodes. |
| `addChildNode`, `insertChildNode(_:at:)`, `removeFromParentNode`, `replaceChildNode` | `addChild`, `insertChild(_:at:)`, `removeChild`, `removeFromParent`, `removeAllChildren`, `replaceChild(_:with:)` | ✅ | Cycle-safe (`canAddChild`, precondition). |
| `parent`, `childNodes` | `parent` (weak), `children` | ✅ | Both read-only. |
| `isHidden` | `isVisible` | ✅ | Inverted sense. Hides the subtree from traversal, rendering, bounds and hit testing. |
| `opacity` | `Node.opacity` | 🟡 | Inherited by children. Applied by Blinn-Phong, PBR (a blended copy of the material while fading) and `ShaderMaterial` (`transforms.opacity`). |
| `categoryBitMask` | `categoryBitMask` | ✅ | Default `1`. Matched against camera, light and hit-test masks. Not inherited by children (same as SceneKit). |
| `renderingOrder` | `renderingOrder` | ✅ | Lower draws first. Within one value, each renderer keeps its own order (for example PBR draws opaque before blended). |
| `castsShadow` | `Content.mesh(…, castsShadow:)` | 🟡 | Per mesh content, not per node. |
| — (no SceneKit equivalent) | `Content.mesh(…, receivesShadow:)` | ➕ | Non-receivers are drawn into a mask that the shadow pass skips. |
| `clone()`, `flattenedClone()` | `clone()`, `flattenedClone()` | ✅ | `clone()` shares meshes, materials, skins and constraints, like SceneKit. `flattenedClone()` merges the subtree's meshes on the CPU; nil for mixed vertex layouts, skinned or morphed meshes. |
| `presentation` | — | ❌ | No separate presentation tree. Actions and animations write to the model values directly. |
| `pivot` | `pivot` | ✅ | `composedTransform` is the local transform with the pivot applied. |
| `movabilityHint` | — | ❌ | |
| `entity` (GameplayKit) | — | ❌ | |
| `morpher` (`SCNMorpher`) | `morphTargets`, `morphWeights` | ✅ | See [Morphing and skinning](#morphing-and-skinning). |
| `skinner` (`SCNSkinner`) | `skin`, `skinVertices` | ✅ | See [Morphing and skinning](#morphing-and-skinning). |
| `constraints` | `constraints: [Constraint]` | 🟡 | See [Constraints](#constraints). |
| `physicsBody`, `physicsField` | — | ❌ | |
| `particleSystems` | `particleSystems` | ✅ | Emitted in world space from the node. |
| `audioPlayers` | `audioPlayers` | ✅ | |
| `filters` (Core Image) | — | ❌ | |
| `boundingBox`, `boundingSphere` | `meshBounds`, `subtreeBounds`, `SceneGraph.bounds`, `SceneGraph.worldBounds(of:)` | 🟡 | Axis-aligned boxes only, no spheres. Computed on the CPU from float3 positions (shared storage) and cached per revision. Skinned and morphed meshes report rest-pose bounds. |
| `enumerateChildNodes`, `enumerateHierarchy` | `SceneGraph.visit(worldTransform:includeHidden:_:)`, `traverse` (skip children or stop), `nodesWithWorldTransforms` | ✅ | Depth-first, with the accumulated world transform. Skips hidden subtrees unless asked. |
| — | `revision` per node | ➕ | Changes propagate to ancestors. Used for caches (bounds, deformation, PBR model). |

## Transforms

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `transform` / `simdTransform` | `transform: float4x4` | ✅ | Setting it stores a matrix. |
| `position`, `orientation`, `scale` | `trs: Transform3D` (`translation`, `rotation: simd_quatf`, `scale`) | ✅ | Setting it stores TRS. Reading `trs` from a matrix decomposes it (lossy for skew, perspective, negative scale). |
| `eulerAngles`, `rotation` (axis-angle) | `eulerAngles` (GeometryLite3D `Euler`, ZYX) | 🟡 | No axis-angle property; use `simd_quatf(angle:axis:)`. |
| `worldTransform`, `worldPosition`, `worldOrientation` | Same names, settable | ✅ | Setting keeps the node's local transform kind (TRS stays TRS). |
| `convertPosition(_:from:)`, `convertVector`, `convertTransform` | Same names, `from:`/`to:` | ✅ | `nil` means world space. |
| `look(at:up:localFront:)` | `look(at:up:localFront:)` | ✅ | One-shot. `Constraint.lookAt` keeps tracking a node. |
| `localUp`, `localRight`, `localFront` (class) | — | ❌ | Lights and cameras use −Z forward, like SceneKit. |
| — | `LocalTransform` (`.matrix` or `.trs`) | ➕ | Keeps the form you set, so glTF matrices stay exact. |

## Geometry

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNGeometry` with `SCNGeometrySource` / `SCNGeometryElement` | `MetalMesh` (SwiftMesh) | 🟡 | Vertex buffers plus a vertex descriptor and submeshes, already on the GPU. No source/element API. |
| Multiple elements per geometry | Submeshes | ✅ | `materials[i]` applies to submesh `i`; the last material covers extra submeshes (SceneKit repeats the material list cyclically). |
| Primitive types: triangles, strips, lines, points, polygons | Any `MTLPrimitiveType` | 🟡 | Rendering accepts any type. Hit testing and shadows use triangles and strips only. No polygon type. |
| `SCNBox` | `Shape.box(width:height:length:)` | 🟡 | No `chamferRadius`, no segment counts. |
| `SCNSphere` | `Shape.sphere(radius:)` | 🟡 | No `isGeodesic`, no segment count. |
| `SCNPlane` | `Shape.plane(width:height:)` | 🟡 | XY plane, like SceneKit. No corner radius, no segments. |
| `SCNCylinder` | `Shape.cylinder(radius:height:)` | 🟡 | No segment counts. |
| `SCNCone` | `Shape.cone(topRadius:bottomRadius:height:)` | 🟡 | Pointed when `topRadius` is 0. No segment counts. |
| `SCNCapsule` | `Shape.capsule(capRadius:height:)` | 🟡 | `height` includes caps, like SceneKit. No segment counts. |
| `SCNTorus` | `Shape.torus(ringRadius:pipeRadius:)` | 🟡 | No segment counts. |
| `SCNText` | `Shape.text(_:fontName:fontSize:extrusionDepth:)` | 🟡 | Font by name. No chamfer, no `flatness`, no container frame, no wrapping, no attributed strings. Gets planar XY texture coordinates. |
| `SCNTube`, `SCNPyramid`, `SCNFloor` | — | ❌ | No infinite floor and no floor reflections. |
| `SCNShape` (extruded `UIBezierPath`/`NSBezierPath`) | — | ❌ | |
| Editable parametric geometry | `Node.shape` | ✅ | Setting it rebuilds the mesh and keeps the materials and shadow flags. |
| `subdivisionLevel`, `tessellator`, `wantsAdaptiveSubdivision` | `Node.subdivisionLevel`, `MetalMesh.subdivided(levels:smooth:)` | 🟡 | CPU Loop subdivision of triangle meshes. No GPU tessellation, no adaptive subdivision, no edge creases. |
| `levelsOfDetail` (`SCNLevelOfDetail`) | `Node.levelsOfDetail` (`LevelOfDetail(mesh:distance:)`) | 🟡 | World-space distance only, no screen-space radius. Hit testing uses the full mesh. |
| `edgeCreasesElement` | — | ❌ | |
| Automatic instancing of shared geometry | Blinn-Phong instancing | 🟡 | Blinn-Phong draws repeated mesh+material pairs (same vertex buffers, submesh and material values) as one instanced call. PBR depends on MetalSprocketsPBR. |

## Materials

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNMaterial` (one type, many lighting models) | `Material` marker protocol; one renderer per material type | 🟡 | Different design: each material family has its own `SceneGraphMaterialRenderer`. Add a family without changing the core. |
| `lightingModel = .physicallyBased` | `PBRSceneMaterial` (wraps `PBRMaterial`) | ✅ | Metallic-roughness glTF model, plus many extensions: transmission, volume (thickness, attenuation), IOR, specular, iridescence, anisotropy, sheen, clearcoat, dispersion, diffuse transmission, emissive strength, unlit, texture transforms. Much wider than SceneKit's PBR. |
| `lightingModel = .blinn` / `.phong` | `BlinnPhongSceneMaterial` | 🟡 | Ambient, diffuse and specular as a color or a tinted 2D texture, and `shininess`. Own shaders in this repo. `opacity` and diffuse texture alpha, `emission`, `normalMap` (tangent frame from screen derivatives, no tangent attribute) and `cullMode`. One ambient light color per renderer (`BlinnPhongMaterialRenderer.ambientLightColor`). |
| `lightingModel = .lambert`, `.constant` | — | 🟡 | Use Blinn-Phong with no specular, PBR `unlit`, or a `ShaderMaterial`. |
| `lightingModel = .shadowOnly` | — | ❌ | |
| `SCNMaterialProperty` (contents, intensity, wrap, filter, mip, `contentsTransform`) | PBR texture slots with texture transforms; Blinn-Phong `BlinnPhongSceneMaterial.Source` | 🟡 | No uniform "property" type across materials. |
| `transparency`, `transparencyMode`, `blendMode` | PBR `alphaMode` (opaque, mask, blend); `ShaderMaterial.isTransparent`; Blinn-Phong `opacity`; `MaterialRenderState.blendMode` (Blinn-Phong, `ShaderMaterial`) | 🟡 | Alpha, add, subtract, multiply, screen and replace; not for PBR (#114). Transparent entries draw after opaque ones, farthest first (`Material.isTransparent`). |
| `isDoubleSided`, `cullMode` | PBR `doubleSided`; Blinn-Phong `cullMode` | 🟡 | `ShaderMaterial` has no cull mode setting. |
| `writesToDepthBuffer`, `readsFromDepthBuffer` | `MaterialRenderState` (Blinn-Phong, `ShaderMaterial`) | 🟡 | Transparent draws never write depth. Not for PBR (#114). |
| `colorBufferWriteMask` | `MaterialRenderState.colorWriteMask` (Blinn-Phong, `ShaderMaterial`) | 🟡 | Not for PBR (#114). |
| `fillMode = .lines` (wireframe) | `MaterialRenderState.fillMode` (Blinn-Phong, `ShaderMaterial`) | 🟡 | Not for PBR (#114); MetalSprocketsPBR has a wireframe debug view. |
| `SCNProgram` | `ShaderMaterial` + `ShaderMaterialRenderer` | ✅ | Your own vertex and fragment functions. Gets `ShaderMaterialTransforms` (model, view, projection with reversed depth, MVP, normal matrix, camera position). Named parameters: float…float4, float4x4, texture, sampler, buffer. Built-ins: `.normals()` and `.rim(color:)`. Uses the mesh's vertex descriptor as is. |
| Shader modifiers (`shaderModifiers`, geometry/surface/lighting/fragment entry points) | — | ❌ | |
| `SCNTechnique` | — | ❌ | No multi-pass post-processing graph. |
| — | Mixing material families in one frame | ➕ | Blinn-Phong, PBR and `ShaderMaterial` meshes draw in one pass, sharing the depth buffer. |

## Lights

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNLight` | `Light` as `Content.light` | 🟡 | Fields: `type`, `color`, `intensity`, `range`, `innerConeAngle`, `outerConeAngle` (half-angles, radians). Points down the node's −Z. |
| `.directional` | `.directional` | ✅ | |
| `.omni` | `.point` | ✅ | With `range`. No `attenuationStartDistance`/`attenuationFalloffExponent`; PBR uses glTF range falloff. |
| `.spot` | `.spot` | ✅ | Inner and outer cone. SceneKit uses full angles in degrees. |
| `.ambient` | `BlinnPhongMaterialRenderer.ambientLightColor`; PBR image-based lighting | 🟡 | Not a node. Blinn-Phong's ambient is per renderer. |
| `.IES`, `.probe`, `.area` | — | ❌ | IBL comes from `environment.map` instead of probes. |
| `temperature` | — | ❌ | |
| `categoryBitMask` | `Node.lightCategoryBitMask` | ✅ | Lights only meshes whose `categoryBitMask` shares a bit. Entries are batched by the set of affecting lights. |
| `castsShadow` and shadow settings per light | Global `SceneGraphShadows` | 🟡 | See [Shadows](#shadows). |
| `autoenablesDefaultLighting` | `SceneView.Options.autoenablesDefaultLighting`; `SceneGraphElement(defaultLight:)` | ✅ | A white directional light at the camera when the scene has no lights. |

## Cameras

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNCamera` | `Camera` as `Content.camera` | 🟡 | `projection: any ProjectionProtocol` and `categoryBitMask`. |
| Perspective (`fieldOfView`, `zNear`, `zFar`, `projectionDirection`) | `PerspectiveProjection` (GeometryLite3D) | ✅ | Vertical angle of view. Standard or reversed depth mode; MSSG always renders with reversed depth. |
| `usesOrthographicProjection`, `orthographicScale` | `OrthographicProjection` (GeometryLite3D) | ✅ | `halfHeight` is half the view height; the width follows the aspect ratio. glTF orthographic cameras load from `ymag`. Model I/O orthographic cameras are skipped with a warning. |
| `projectionTransform` (custom) | A custom `ProjectionProtocol` | ✅ | |
| `categoryBitMask` | `Camera.categoryBitMask` | ✅ | Draws only matching nodes; also limits `SceneView` tap hits. |
| `pointOfView` | `SceneGraphElement(camera:)`, `SceneView(pointOfView:)` | ✅ | Defaults to the first camera node. `cameraMatrix` overrides the world transform. With no camera node, `defaultCamera` is used. |
| `wantsHDR`, exposure, tone mapping | `PostProcessing.exposure`; PBR `exposure` | 🟡 | Exposure on low dynamic range color; no HDR or tone mapping. #45. |
| SSAO, vignetting, color grading (saturation, contrast) | `SceneGraph.postProcessing` (`ambientOcclusion`, `vignetteIntensity`, `saturation`, `contrast`) | 🟡 | Screen-space, after fog. SSAO is unblurred (grainy). No color lookup tables. |
| Bloom, depth of field, motion blur, color fringe, film grain | — | ❌ | #45. |
| `wantsExposureAdaptation` | — | ❌ | |
| Camera control (`allowsCameraControl`, `SCNCameraController`) | `SceneView.Options.allowsCameraControl` | 🟡 | Orbit, pan and zoom from Interaction3D, around a target fixed when the view appears. Does not move the point-of-view node; the result is exposed through the `cameraMatrix` binding. No fly or turntable modes, no inertia settings. |

## Shadows

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| Shadow maps from directional and spot lights | `SceneGraphShadows` | ✅ | Directional: orthographic view fitted to the scene bounds. Spot: perspective view of the outer cone. |
| Point light shadows | `SceneGraphShadows` | ✅ | Six 90° views per point light. |
| `shadowMode` (forward, deferred, modulated) | Blinn-Phong and PBR: per light, in the shader (like forward). `ShaderMaterial`: a screen-space mask after the scene pass | 🟡 | The screen-space mask darkens by every light at once. |
| `shadowColor` | `color` and `intensity` | ✅ | Global, not per light. |
| `shadowMapSize` | `resolution` (default 2048) | ✅ | Global, not per light. |
| `shadowBias` | `depthBias`, `slopeScale` | ✅ | Global. Acne is still visible on some lit surfaces (#60). |
| `shadowRadius`, `shadowSampleCount` (soft shadows) | `softness` (PCF half-size in texels) | 🟡 | Global; fixed-width filter, not contact-hardening. |
| `orthographicScale`, `shadowCascadeCount`, `shadowCascadeSplittingFactor`, `automaticallyAdjustsShadowProjection` | Automatic fit to scene bounds | 🟡 | No cascades. |
| `castsShadow` per node / light | `castsShadow` per mesh content | 🟡 | All lights cast (up to the slice limit). |
| — | `receivesShadow` | ➕ | Honored through a receiver mask. |
| Number of shadowing lights | 8 shadow map slices | 🟡 | Directional or spot uses 1, point uses 6. A light that does not fit casts none; see `droppedLightCount`. |
| Skinned casters | GPU skinning in the caster pass | ✅ | Morphed meshes use CPU-deformed positions. |
| Requirements | Color texture `.shaderWrite`, depth `.shaderRead`, depth not memoryless | — | `SceneView` sets these when shadows or fog are on. Otherwise shadows are silently skipped. |

Known bugs: #59 (rare flicker on self-shadowed surfaces), #71 (shadows broken in demos since the demo consolidation).

## Animation

SceneKit animates with `CAAnimation`/`SCNAnimation` and `SCNAnimationPlayer`, keyed by key path. MSSG has its own system.

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNAnimation` / `CAKeyframeAnimation` | `AnimationClip` | ✅ | Channels target `translation`, `rotation`, `scale`, `weights`, or any value through `.property(Property)` (built in: `lightIntensity`, `lightColor`). |
| Interpolation and timing functions | `Interpolation`: `.step`, `.linear` (slerp for rotation), `.cubicSpline` (glTF Hermite) , plus `AnimationPlayer.timingMode` (including `.custom`) | ✅ | |
| `SCNAnimationPlayer` (play, stop, speed, `blendFactor`) | `AnimationPlayer` (`time`, `speed`, `isLooping`, `isPlaying`, `advance(by:)`) | ✅ | |
| `repeatCount`, `autoreverses`, `isAppliedOnCompletion`, `fillMode` | `isLooping`, `repeatCount`, `autoreverses` | 🟡 | Finished clips hold their last frame; no fill modes. |
| `blendInDuration`, `blendOutDuration` | `AnimationController.play(_:fadeDuration:…)` | ✅ | Cross-fades every other track out. |
| `isAdditive` | `AnimationLayer.Mode.additive`, `AnimationController.setAdditive` | ✅ | Adds the clip's offset from rest, scaled by weight. |
| Multiple simultaneous animations with weights | `AnimationMixer` + `AnimationLayer` | ➕ | Normalized-weight blending of override layers; rest pose captured from nodes. |
| — | `AnimationController.blend(_:parameter:syncsPhase:)` | ➕ | One-parameter blend space with phase sync (for example walk/run). |
| — | Root motion (`rootMotionNode`, `rootMotion`) | ➕ | Keeps the root's x/z at rest and reports how far it moved, including across loops. |
| — | `AnimationStateMachine` | ➕ | Named states, ordered transitions with conditions on parameters, normalized time and state time. |
| `animationEvents` (`SCNAnimationEvent`) | `AnimationClip.events` | ✅ | Fired by `AnimationPlayer`, in both directions. Not fired by `AnimationMixer`. |
| `SCNSceneSource` animation extraction | `GLTFSceneGraph.animations`, `ModelIOSceneGraph.animation` | 🟡 | glTF: all clips. Model I/O: keyframed transforms sampled at key times into one clip. |
| Driving | `advance(by:)` each frame | 🟡 | Not driven by `SceneView`; call it from the delegate. |

## Actions

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNAction` | `SceneGraph.Action` | ✅ | Run with `Node.run(_:forKey:completion:)`; advance all with `SceneGraph.advanceActions(by:)` (`SceneView` does this). Actions on hidden nodes still run. |
| `move(by:)`, `move(to:)` | Same | ✅ | |
| `rotate(by:around:)`, `rotate(toAxisAngle:)`, `rotateBy(x:y:z:)`, `rotateTo(x:y:z:)` | `rotate(by:around:)`, `rotate(to: simd_quatf)`, `rotateBy(x:y:z:)`, `rotateTo(x:y:z:)` | ✅ | Euler order: X, then Y, then Z about fixed axes. |
| `scale(by:)`, `scale(to:)` | `scale(by: Float)`, `scale(to: SIMD3)` | ✅ | `scale(by:)` is multiplicative so the total is exact. |
| `fadeIn`, `fadeOut`, `fadeOpacity` | `Action.fadeIn`, `fadeOut`, `fadeOpacity(to:)`, `fadeOpacity(by:)` | ✅ | PBR masked materials lose their alpha cutoff while fading. |
| `hide`, `unhide`, `removeFromParentNode` | `hide()`, `unhide()`, `removeFromParent()` | ✅ | |
| `wait(duration:)`, `wait(duration:withRange:)` | Same | ✅ | |
| `run(_:)`, `customAction(duration:action:)` | `run(_:)`, `custom(duration:_:)` | ✅ | |
| `sequence`, `group`, `repeat`, `repeatForever` | Same | ✅ | Leftover time carries over between steps, so sequences do not drift. |
| `reversed()` | `reversed()` | ✅ | Relative actions and composites reverse; absolute and custom actions return unchanged. easeIn and easeOut swap. |
| `timingMode`, `timingFunction` | `timingMode(_:)`: linear, easeIn, easeOut, easeInEaseOut, `.custom(_:)` | ✅ | |
| `speed` (per action or node) | `Action.speed(_:)`, `Node.actionSpeed` | ✅ | |
| `playAudio`, `javaScriptAction` | — | ❌ | |
| `removeAction(forKey:)`, `removeAllActions`, `hasActions`, `action(forKey:)` | Same, plus `hasAction(forKey:)` | ✅ | |

## Implicit animation

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNTransaction.begin/commit`, `animationDuration` | `Transaction.animate(duration:timingMode:_:completion:)` | 🟡 | Animates transform and morph weight changes only. Runs as node actions keyed `implicit.transform` and `implicit.morphWeights`. |
| `disableActions` | `Transaction.withoutAnimation(_:)` | ✅ | |
| `completionBlock` | `completion:` | ✅ | |
| Nested transactions | — | 🟡 | Task-local; an inner `animate` replaces the outer recorder for its body. |

## Constraints

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNLookAtConstraint` | `Constraint.lookAt(target:worldUp:localFront:)` | ✅ | Falls back to another up vector when looking straight along `worldUp`. No `isGimbalLockEnabled`. |
| `SCNBillboardConstraint` | `Constraint.billboard(freeAxes:)` | ✅ | Any set of `.x`, `.y`, `.z`. |
| `SCNDistanceConstraint` | `Constraint.distance(target:minimum:maximum:)` | ✅ | |
| `SCNIKConstraint` | `Constraint.inverseKinematics(chainRoot:target:iterations:maximumAngle:)` | 🟡 | CCD solver; one angle limit for all joints, no per-joint limits. |
| `SCNReplicatorConstraint`, `SCNAvoidOccluderConstraint`, `SCNTransformConstraint` | `.replicator(…)`, `.avoidOccluder(…)`, `.transform(_:)` | ✅ | Avoid-occluder uses triangle hit tests. |
| `SCNAccelerationConstraint`, `SCNSliderConstraint` | — | ❌ | Acceleration needs frame time in `applyConstraints`; slider needs physics (#38). |
| `influenceFactor`, `isIncremental`, `isEnabled` | — | ❌ | |
| Evaluation | `SceneGraph.applyConstraints(pointOfView:)` | 🟡 | Parents before children, after actions. Sets the local TRS and keeps world scale. `SceneView` calls it each frame. |

## Morphing and skinning

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNMorpher.targets` | `Node.morphTargets: [MorphTarget]` | ✅ | Position, normal and tangent deltas per vertex (not whole target geometries). |
| `SCNMorpher.weights`, `setWeight(_:forTargetNamed:)` | `Node.morphWeights`, `setMorphWeight(_:forTargetNamed:)`, `morphWeight(forTargetNamed:)` | ✅ | Names from `MorphTarget.name`; glTF reads `extras.targetNames`. |
| `calculationMode` (normalized/additive) | Offsets from the base mesh | 🟡 | Equivalent to `.normalized`. No `.additive` (absolute targets added to the base). |
| `unifiesNormals` | — | ❌ | |
| `SCNSkinner` (`bones`, `boneInverseBindTransforms`, `boneWeights`, `boneIndices`) | `Skin` (`joints`, `inverseBindMatrices`) + `Node.skinVertices` | ✅ | Joints are graph nodes. A skin can be shared by several meshes. Four influences per vertex. |
| `baseGeometry`, `baseGeometryBindTransform` | — | 🟡 | Skinned meshes are placed by their joints, not the node transform. |
| GPU morph/skin | PBR: on the GPU (MetalSprocketsPBR). Blinn-Phong and `ShaderMaterial`: on the CPU, cached per revision. Shadow casters: GPU skinning, CPU morphing. | 🟡 | CPU-deformed meshes skip frustum culling. |

## Hit testing and queries

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNSceneRenderer.hitTest(_:options:)` (screen point) | `ViewProjection.ray(through:)` + `hitTest`; `SceneView(onTap:)` | ✅ | `onTap` gets the nearest hit, limited to the camera's mask and `hitTestCategoryBitMask`. |
| `SCNNode.hitTestWithSegment(from:to:options:)` | `SceneGraph.hitTest(segmentFrom:to:options:)` with `options.rootNode` | ✅ | |
| `SCNHitTestResult` (node, geometryIndex, faceIndex, localCoordinates, worldCoordinates, localNormal, worldNormal, `textureCoordinates(withMappingChannel:)`) | `Hit` | ✅ | Plus `localPosition`, `barycentric`, `vertexIndices` and `textureCoordinates(index:)`. No local normal. |
| Options: `boundingBoxOnly`, `backFaceCulling`, `firstFoundOnly`, `sortResults`, `ignoreHiddenNodes`, `searchMode`, `categoryBitMask` | `HitTestOptions`: `categoryBitMask`, `backFaceCulling`, `boundingBoxOnly`, `firstFoundOnly`, `maximumDistance`, `rootNode` | 🟡 | Results are always sorted and hidden nodes always skipped. |
| Deformed geometry | Uses CPU-deformed geometry for skinned and morphed meshes | ✅ | |
| `projectPoint`, `unprojectPoint` | `SceneGraph.projectPoint`, `SceneGraph.unprojectPoint` | ✅ | Static: pass view size, camera and projection matrices. |
| `nodesInsideFrustum(of:)`, `isNode(_:insideFrustumOf:)` | `nodesInsideFrustum(cameraMatrix:projectionMatrix:)`, `isNode(_:insideFrustumWithCameraMatrix:projectionMatrix:)` | ✅ | Conservative bounding-box test. |
| Physics queries (`rayTestWithSegment`, `contactTest`, `convexSweepTest`) | — | ❌ | |

## Physics

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNPhysicsWorld`, `SCNPhysicsBody`, shapes, joints, fields, vehicles, contacts | — | ❌ | The demo package has a Jolt-based physics demo that copies body transforms onto nodes each frame. Physics in the library is #38. |

## Particles and audio

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNParticleSystem` | `ParticleSystem` | 🟡 | Birth rate, lifetime, emitter shapes (point, box, sphere), spread, speed, acceleration, damping, size and color over life, alpha or additive blending, seedable. No textures, image sequences, collisions, fields or orientation modes. |
| `SCNAudioSource`, `SCNAudioPlayer`, positional audio | `AudioPlayer` (buffer or file), `SceneAudio` (AVAudioEngine + environment node), `SceneView(audio:)` | 🟡 | Mono buffers are positioned; listener is the camera. No `playAudio` action. |

## Rendering pipeline

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SCNView`, `SCNRenderer`, `SCNLayer` | `SceneGraphElement` (a MetalSprockets `Element`), `SceneView` | 🟡 | Render into any MetalSprockets `RenderView` or offscreen renderer. No `SCNRenderer`-style render-at-time API. |
| `rendersContinuously`, `preferredFramesPerSecond` | From `RenderView` | 🟡 | |
| `antialiasingMode` (multisampling) | — | ❌ | Not exposed by `SceneView`. |
| `isJitteringEnabled`, temporal antialiasing | — | ❌ | |
| `debugOptions` (bounding boxes, wireframe, physics shapes, light extents, skeletons, cameras) | — | ❌ | The demos have a scene outline and node inspector instead. |
| `showsStatistics` | `SceneView.Options.showsStatistics`, `SceneGraph.statistics` | 🟡 | Frame rate, meshes, triangles, lights. No GPU timings. |
| `snapshot()` | Offscreen rendering via MetalSprockets `OffscreenRenderer` | 🟡 | The demo package's `scenegraph-demos --render` writes PNGs. |
| `prepare(_:shouldAbortBlock:)` | — | ❌ | Pipelines and PBR models build on first use. |
| `SCNSceneRendererDelegate` (`update`, `didApplyAnimations`, `didSimulatePhysics`, `didApplyConstraints`, `willRender`, `didRender`) | `SceneViewDelegate` (`sceneView(updateAtTime:deltaTime:)`, `sceneView(didApplyActionsAtTime:)`, `sceneView(didApplyConstraintsAtTime:)`) | 🟡 | No physics or did-render callbacks. |
| `SCNNodeRendererDelegate` | A custom `SceneGraphMaterialRenderer` | 🟡 | Per material type, not per node. |
| Frustum culling | Blinn-Phong: CPU AABB culling, front-to-back sort | 🟡 | PBR culling is up to MetalSprocketsPBR. `ShaderMaterial` does not cull. |
| Transparency sorting | Within each `renderingOrder`: opaque first, then transparent entries farthest first | 🟡 | Sorted by bounds center, per renderer: transparent entries of different renderers do not interleave. |
| Depth | Reversed depth (near 1, far 0) everywhere | ➕ | Required by MetalSprocketsPBR. |
| Metal / OpenGL | Metal 4 only (MetalSprockets) | 🟡 | |
| — | `SceneGraphBackgroundRenderer` | ➕ | Renderers can draw the environment background. |
| — | Pluggable renderers per material family | ➕ | `SceneGraphElement(renderers:)` hands each family its entries in one render pass. |

## SwiftUI

| SceneKit | MSSG | Status | Notes |
|---|---|---|---|
| `SceneView(scene:pointOfView:options:preferredFramesPerSecond:antialiasingMode:delegate:technique:)` | `SceneView(sceneGraph:pointOfView:options:renderers:delegate:isPlaying:shadows:cameraMatrix:hitTestCategoryBitMask:onTap:)` | ✅ | `renderers` is required (no default). No frame rate, antialiasing or technique parameters. |
| `.allowsCameraControl` | Same | ✅ | See [Cameras](#cameras). |
| `.autoenablesDefaultLighting` | Same | ✅ | |
| `.rendersContinuously`, `.temporalAntialiasingEnabled`, `.jitteringEnabled` | — | ❌ | Always renders continuously. |
| — | `cameraMatrix: Binding<simd_float4x4?>` | ➕ | Read or reset the camera-control transform. |
| — | `onTap` with hit testing | ➕ | |
| — | Automatic default camera | ➕ | With no camera node, frames the scene bounds with a 60° perspective camera. |
| `UIViewRepresentable`-style `SCNView` access | — | 🟡 | Use `RenderView` with `SceneGraphElement` directly. |

## Asset import

| Format / feature | SceneKit | MSSG | Status | Notes |
|---|---|---|---|---|
| `.scn` | ✅ | — | ❌ | |
| USD / USDA / USDC / USDZ | ✅ (native) | Model I/O | 🟡 | Hierarchy, meshes, materials, cameras, lights and keyframed transforms through `MDLAsset`. No skins or blend shapes (#31). |
| OBJ, PLY, STL, ABC | Via Model I/O | `ModelIOSceneGraph` | ✅ | Choose PBR or Blinn-Phong materials. Vertices repacked to position, normal and texture coordinates. |
| Model I/O textures | ✅ | Base color, emission, normal, occlusion, metallic and roughness | ✅ | Metallic and roughness maps are packed into one texture for PBR. Blinn-Phong uses base color only. |
| `.dae` (Collada) | ✅ (macOS) | Model I/O if it can read it | 🟡 | |
| glTF / GLB | ❌ | `GLTFAsset.makeSceneGraph(device:)` | ➕ | Hierarchy, meshes (one submesh per primitive), PBR materials with variants, perspective and orthographic cameras, punctual lights, skins, morph targets, node animations, `EXT_mesh_gpu_instancing` (as child nodes), `KHR_node_visibility`. Not supported: `KHR_animation_pointer` (#54). Returns `nodes` indexed like the document, and `warnings`. |

## Asset export

| SceneKit | MSSG | Status |
|---|---|---|
| `SCNScene.write(to:)` (`.scn`, `.usdz`, `.dae`) | — | ❌ (#52) |
| `NSSecureCoding` archiving | — | ❌ |

## Platforms and concurrency

| | SceneKit | MSSG |
|---|---|---|
| Platforms | iOS, iPadOS, macOS, tvOS, watchOS, visionOS (soft-deprecated in 2025 in favor of RealityKit) | iOS 26, macOS 26, visionOS 26 |
| Language | Objective-C API, Swift overlay | Swift 6.2 |
| Threading | Render thread, `SCNTransaction` locks | Not `Sendable`. Nodes and materials hold Metal objects; use from one thread (`SceneView` drives it from its render closure). |
| Source | Closed | Open, depends on MetalSprockets, MetalSprocketsPBR, MetalSprocketsGLTF, SwiftGLTF, SwiftMesh, GeometryLite3D, Interaction3D |
