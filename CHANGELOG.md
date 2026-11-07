# Changelog

## Unreleased

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

- Perspective and orthographic cameras. Directional, point and spot lights, with per-node light masks and default lighting.
- Shadow maps for all light types, with intensity, color, softness, bias, and per-mesh cast and receive settings.
- Color or environment backgrounds, fog, screen-space ambient occlusion, and post-processing (exposure, contrast, saturation, vignette).
- Blend modes, depth and color masks, wireframe, and debug views.

### Materials

- Blinn-Phong: colors, textures, emission, normal maps, opacity.
- PBR metallic-roughness, with most glTF material extensions (transmission, volume, IOR, dispersion, specular, iridescence, anisotropy, sheen, clearcoat, and more), image-based lighting, and shadows.
- Custom shaders through `ShaderMaterial`.
- `MaterialTexture` loads textures from image files, `CGImage`s and asset catalogs. Blinn-Phong takes them with `.texture(contentsOf:device:)`, and `PBRSceneMaterial(device:textures:)` takes base color, metallic-roughness, normal, occlusion and emissive textures.

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
- Model I/O: OBJ, PLY, STL, ABC and USD.
