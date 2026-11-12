# Changelog

## Unreleased

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
