# Features

This table shows what SceneSprockets has (✅) and does not have yet (⬜). 🧩 means that the feature is possible today with MetalSprockets or a ShaderMaterial, but it needs an example. A ~~struck-through~~ feature is one that we will not add.

The Source column shows where the feature comes from: SceneKit, RealityKit, three.js, Babylon.js, Godot, Unity, Unreal, GameplayKit, Filament, Jolt or glTF. An empty Source means our own idea. Brainstorm means an idea with no source.

## Scene and nodes

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Node hierarchy: add, insert, remove, replace | | SceneKit | |
| ✅ | TRS or matrix transforms, pivot | | SceneKit | |
| ✅ | World space accessors, convert between spaces, `look(at:)` | | SceneKit | |
| ✅ | Visibility, inherited opacity, rendering order | | SceneKit | |
| ✅ | Category masks for cameras, lights, hit tests | | SceneKit | |
| ✅ | `clone()`, `flattenedClone()` | | SceneKit | |
| ✅ | Bounds and scene statistics | | SceneKit | |
| ✅ | Revisions for change tracking | | | |
| ⬜ | Presentation tree | | SceneKit | |
| ⬜ | ~~Entity-component system~~ | | RealityKit, Godot | |
| ⬜ | ~Prefabs / reusable subtrees | | Godot, Unity | |
| ⬜ | Save and load scenes | #52 | SceneKit | |

## Geometry

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Box, sphere, plane, cylinder, cone, capsule, torus | | SceneKit | |
| ✅ | Extruded text | | SceneKit | |
| ✅ | Any SwiftMesh mesh, one material per submesh | | | |
| ✅ | Subdivision | | SceneKit | |
| ✅ | Levels of detail | | SceneKit | |
| ✅ | Automatic instancing | | SceneKit | Blinn-Phong |
| ✅ | Frustum culling | | SceneKit | |
| ⬜ | Segment counts, chamfers, geodesic spheres | #80 | SceneKit | |
| ⬜ | Tube, pyramid, floor, extruded Bézier path | #81 | SceneKit | |
| ⬜ | Flat 2D text | #119 | three.js | MetalSprocketsAddOns has this. |
| ⬜ | Lines with width, sprites | ||MetalSprocketsAddOns has this.|
| 🧩 | Point clouds | | three.js | Point primitives with ShaderMaterial |
| ⬜ | Terrain / heightmaps | | Babylon.js, Godot | |
| ⬜ | Boolean (CSG) meshes in the scene graph | | Godot | SwiftMesh has this |
| ⬜ | Bend, twist, noise modifiers | | Babylon.js | |
| ⬜ | GPU tessellation | | SceneKit | |
| ⬜ | Explicit instancing API | #135 | three.js, RealityKit | |

## Cameras and lights

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Perspective and orthographic cameras | | SceneKit | |
| ✅ | Directional, point, spot lights | | SceneKit | |
| ✅ | Per-node light masks | | SceneKit | |
| ✅ | Default lighting | | SceneKit | |
| ⬜ | Ambient light node, temperature, IES, area lights | #86 | SceneKit, RealityKit | |
| ⬜ | Camera controllers: first person, fly, follow | | three.js | Interaction3D supports this. |
| 🧩 | Multiple viewports, render to texture | | SceneKit, three.js | MetalSprockets render passes and offscreen targets |
| ⬜ | Stereo / immersive rendering | | RealityKit | Already supported in MetalSprockets |

## Rendering

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Shadow maps for all light types | | SceneKit | |
| ✅ | Shadow intensity, color, softness, bias | | SceneKit | |
| ✅ | Per-mesh cast and receive shadows | | SceneKit | |
| ✅ | Background: color or environment with blur | | SceneKit | |
| ✅ | Fog | | SceneKit | |
| ✅ | Exposure, contrast, saturation, vignette | | SceneKit | |
| ✅ | Screen-space ambient occlusion | | SceneKit | |
| ✅ | Blend modes, depth and color masks, wireframe | | SceneKit | |
| ⬜ | Shadow cascades, per-light shadow settings | #88 | SceneKit | |
| ⬜ | HDR, tone mapping, bloom, depth of field | #45 | SceneKit, three.js | |
| ⬜ | Motion blur, film grain, lens flares | | SceneKit, Babylon.js | |
| ⬜ | Anti-aliasing options | | three.js, Godot | FXAA, SMAA, TAA |
| 🧩 | Spatial upscaling (MetalFX) | | Unity, Unreal | MetalSprockets has MetalFXSpatial; MetalSprocketsPBR uses it |
| ⬜ | Temporal upscaling and anti-aliasing (MetalFX) | | Unity, Unreal | MetalSprockets has MetalFXTemporal; needs motion vectors and jitter |
| ⬜ | Ray tracing | | Unity, Unreal, Godot | MetalSprockets can bind acceleration structures |
| ⬜ | Ray-traced shadows | | Unity, Unreal | |
| ⬜ | Screen-space and planar reflections, probes | | SceneKit, RealityKit, Godot | |
| ⬜ | Skybox / procedural sky | | three.js, Godot | |
| ⬜ | Outlines, selection highlights, glow | | three.js, Babylon.js | |
| ⬜ | Shadow-only material, contact shadows | | SceneKit, RealityKit, three.js | |
| ⬜ | Decals | | three.js, Godot | |
| ⬜ | Order-independent transparency | | Babylon.js | |
| ⬜ | Lightmaps, global illumination | | three.js, Godot | |
| ⬜ | Volumetric lighting and fog | | Godot, Filament | |
| ⬜ | Occlusion culling | | Godot | |
| ⬜ | Debug views | | SceneKit, three.js | Normals, bounds, light gizmos |
| ⬜ | Clustered or tiled lighting, deferred shading | | Godot, Unity, Filament | For many lights |
| ⬜ | GPU-driven rendering: indirect draws, GPU culling, mesh shaders | | Unreal | |
| ⬜ | Variable rate shading | | Unreal | Metal rasterization rate maps |
| ⬜ | Gaussian splats | | Babylon.js | See MetalSprocketsGaussianSplats |
| ⬜ | Subsurface scattering | | Unreal, Godot | |
| ⬜ | Hair and fur | | Unreal | |
| ⬜ | Water and ocean surfaces | | Unity, Godot | |
| ⬜ | Foliage with wind | | Unity, Unreal | |
| ⬜ | Impostors for distant objects | | Unreal | |
| ⬜ | 3D labels and annotations | | three.js | |
| ⬜ | SwiftUI views in 3D | | RealityKit | Attachments |

## Materials

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Blinn-Phong: colors, textures, emission, normal map, opacity | | SceneKit | |
| ✅ | Custom vertex and fragment shaders | | SceneKit | |
| ⬜ | Shader modifiers / node material graph | | SceneKit, RealityKit, three.js | |
| 🧩 | Toon and matcap materials | | three.js | ShaderMaterial |
| ⬜ | Video, cube-map and 3D textures | | SceneKit, RealityKit, three.js | |
| ⬜ | Parallax, triplanar, detail maps | | Godot, Babylon.js | |

## PBR

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Metallic-roughness: base color, metallic, roughness | | glTF core | |
| ✅ | Normal map with scale | | glTF core | |
| ✅ | Occlusion map with strength | | glTF core | |
| ✅ | Emissive color and texture | | glTF core | |
| ✅ | Emissive strength | | GLTF Extension | |
| ✅ | Alpha modes: opaque, mask (cutoff), blend | | glTF core | |
| ✅ | Double-sided materials | | glTF core | |
| ✅ | Texture transforms | | GLTF Extension | Offset, rotation, scale, texCoord set |
| ✅ | Unlit | | GLTF Extension | |
| ✅ | Transmission | | GLTF Extension | Refracts the scene behind |
| ✅ | Volume: thickness, attenuation | | GLTF Extension | |
| ✅ | Index of refraction | | GLTF Extension | |
| ✅ | Dispersion | | GLTF Extension | |
| ✅ | Specular and specular color | | GLTF Extension | |
| ✅ | Iridescence | | GLTF Extension | |
| ✅ | Anisotropy | | GLTF Extension | |
| ✅ | Sheen | | GLTF Extension | |
| ✅ | Clearcoat, clearcoat roughness, clearcoat normal | | GLTF Extension | |
| ✅ | Diffuse transmission | | GLTF Extension | |
| ✅ | Retroreflection | | GLTF Extension | |
| ✅ | Volume scattering | | GLTF Extension | Approximated, no scattering pass |
| ✅ | Specular-glossiness workflow | | GLTF Extension | |
| ✅ | Image-based lighting: studio, uniform color, equirectangular image | | MetalSprocketsPBR | |
| ✅ | Environment intensity, rotation, background with blur | | MetalSprocketsPBR | |
| ✅ | Exposure | | MetalSprocketsPBR | |
| ✅ | Shadows sampled in the PBR shader | | | |
| ✅ | Node opacity | | | Fading PBR materials |
| ⬜ | Render state: depth, color mask, wireframe | #114 | SceneKit | |
| ⬜ | Tone mapping choice (PBR neutral, ACES, AgX, Reinhard, linear); fixed to PBR neutral here | | MetalSprocketsPBR | |
| ⬜ | Debug views | | MetalSprocketsPBR | Base color, alpha, metallic, roughness, normals, tangents… |
| ⬜ | HDR output | #45 | MetalSprocketsPBR | |
| ⬜ | Stereo / immersive rendering | | MetalSprocketsPBR | |
| ⬜ | Image-based light from glTF | | GLTF Extension | |
| ⬜ | IES light profiles | #86 | GLTF Extension | |

## Animation

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Actions: move, rotate, scale, fade, wait, run, sequence, group, repeat | | SceneKit | |
| ✅ | Timing modes, action keys, per-node speed | | SceneKit | |
| ✅ | Implicit animation | | SceneKit | Transactions |
| ✅ | Keyframed clips: transforms, morph weights, custom properties | | glTF, SceneKit | |
| ✅ | Animation events | | SceneKit | |
| ✅ | Player: speed, loop, repeat, autoreverse | | SceneKit | |
| ✅ | Blending: mixer, layers, additive | | RealityKit, Godot | |
| ✅ | Root motion | | Godot, Unity | |
| ✅ | Animation state machine | | Godot, Unity | |
| ✅ | Morph targets | | glTF | |
| ✅ | Skinning | | glTF | |
| ⬜ | Follow a path / spline | | SceneKit, three.js | |
| ⬜ | Tween any property, springs | | RealityKit | |
| ⬜ | Retargeting between skeletons | | Godot | |
| ⬜ | GPU skinning for every renderer | | | |
| ⬜ | Foot IK and look-at heads | | Unity, Unreal | |
| ⬜ | Timeline / sequencer | | Unity, Godot | |
| ⬜ | Lip sync from audio | | Brainstorm | |

## Constraints

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Look-at, billboard, replicator | | SceneKit | |
| ✅ | Avoid-occluder, distance | | SceneKit | |
| ✅ | Inverse kinematics | | SceneKit | |
| ✅ | Acceleration, custom transform | | SceneKit | |
| ✅ | Slider | | SceneKit | Physics |
| ⬜ | Influence factor | | SceneKit | |

## Physics

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Static, dynamic, kinematic bodies | #38 | SceneKit | Jolt |
| ✅ | Box, sphere, capsule, cylinder, convex hull, mesh shapes | | SceneKit | |
| ✅ | Mass, friction, restitution, gravity | | SceneKit | |
| ✅ | Velocity, angular velocity, impulses | | SceneKit | |
| ⬜ | Plane, triangle, tapered capsule, height field shapes | | Jolt | |
| ⬜ | Compound and mutable compound shapes | | Jolt | Only internally, for offset boxes |
| ⬜ | Forces and torques | | Jolt | |
| ⬜ | Linear and angular damping | | Jolt | |
| ⬜ | Gravity factor per body | | Jolt | |
| ⬜ | Mass and inertia overrides | | Jolt | Only mass today |
| ⬜ | Continuous collision | | Jolt | Linear cast motion quality |
| ⬜ | Sleeping / activation callbacks | | Jolt | |
| ⬜ | Joints: fixed, point, hinge, slider, distance, cone | | Jolt, SceneKit, RealityKit | |
| ⬜ | Joints: swing-twist (ragdolls), six-DOF, gear | | Jolt | |
| ⬜ | Joint limits, springs, motors | | Jolt | |
| ⬜ | Contact callbacks with contact points | | Jolt, SceneKit, RealityKit | |
| ⬜ | Sensors / trigger volumes | | Jolt, SceneKit, RealityKit | |
| ⬜ | Raycasts against physics shapes | | Jolt, SceneKit, RealityKit | |
| ⬜ | Shape casts, overlap tests, point queries | | Jolt, SceneKit | |
| ⬜ | Physics debug drawing | | Jolt | Shapes, bounds, velocities, joints |
| ⬜ | Character controllers | #153 | Jolt, Godot | Rigid and virtual: slopes, stairs |
| ⬜ | Wheeled vehicles, motorcycles, tracked vehicles | | Jolt, SceneKit | |
| ⬜ | Physics fields | | SceneKit | |
| ⬜ | Soft bodies, cloth | | Godot | |

## Particles

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | GPU particles on nodes | | SceneKit | MetalSprocketsParticles |
| ✅ | Effect colliders follow the node | | | |
| ✅ | Soft particles | | three.js, Babylon.js | |
| ✅ | Emitters on skinned meshes | | | |

## Hit testing and interaction

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Ray and segment hit tests with options | | SceneKit | |
| ✅ | Project and unproject points, frustum queries | | SceneKit | |
| ✅ | SwiftUI `SceneView`: camera control, taps, delegates | | SceneKit | |
| ⬜ | Gestures and transform gizmos | #154 | RealityKit, three.js | |

## Assets

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | glTF: meshes, skins, morphs, animations, cameras, materials | | glTF core | |
| ✅ | glTF punctual lights | | GLTF Extension | |
| ✅ | glTF material variants | | GLTF Extension | |
| ✅ | glTF animation pointer | | GLTF Extension | Transforms, morph weights, material properties |
| ✅ | glTF node visibility | | GLTF Extension | |
| ✅ | glTF quantized meshes | | GLTF Extension | |
| ✅ | glTF GPU instancing | | GLTF Extension | |
| ✅ | glTF WebP textures | | GLTF Extension | |
| ✅ | glTF meshopt compression | | GLTF Extension | Optional product |
| ✅ | glTF KTX2 / Basis Universal textures | | GLTF Extension | Optional product |
| ⬜ | glTF Draco compression | | GLTF Extension | |
| ⬜ | glTF Gaussian splats | | GLTF Extension | |
| ⬜ | glTF ASTC textures | | GLTF Extension | |
| ✅ | Model I/O: OBJ, PLY, STL, ABC, USD | | SceneKit | |
| ⬜ | USD/USDZ into a scene graph | #31 | RealityKit | |
| ⬜ | Asset metadata | | SceneKit | Up axis, units, frame rate |
| ⬜ | Async and streaming loading with progress | | Unity, Godot | |
| ⬜ | FBX import | | Unity, Godot | |
| ⬜ | Export to glTF or USD | | Godot | |

## Misc

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ✅ | Positional audio on nodes | | SceneKit | |
| ✅ | Offscreen rendering and video export | | | Demo CLI |
| ⬜ | Spatial audio with occlusion and reverb | | RealityKit | |
| ⬜ | Accessibility for 3D content | | RealityKit | |

## Gameplay and interaction

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ⬜ | Navigation meshes and pathfinding | | GameplayKit, Godot, Unity | |
| ⬜ | Game controller and keyboard input mapping | | Godot, Unity | |
| ⬜ | Haptics | | Brainstorm | |
| ⬜ | Networked scene replication, SharePlay | | RealityKit | |

## Platforms

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ⬜ | AR: anchors, plane detection, people occlusion | | RealityKit | |
| ⬜ | visionOS immersive spaces and hand tracking | | RealityKit | |

## Tools

| Done | Feature | Issues | Source | Notes |
|---|---|---|---|---|
| ⬜ | Scene inspector and editor | | Godot, Unity | The demo inspector is a start |
| ⬜ | Shader hot reload | | Brainstorm | |
| ⬜ | GPU timing overlay per pass | | Unity | |
| ⬜ | Deterministic simulation for tests and replays | | Brainstorm | |
