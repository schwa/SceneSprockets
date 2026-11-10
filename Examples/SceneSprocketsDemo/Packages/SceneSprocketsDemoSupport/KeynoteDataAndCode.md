# Keynote: data and code

This document lists, for each slide of the keynote demo (`KeynoteDemo.swift`), what could be stored as scene data (a `SceneArchive`) and what must stay in code (#345).

## What SceneArchive stores today

- Nodes: label, transform, pivot, visibility, opacity, masks, rendering order.
- Content: shapes, model files, meshes, Blinn-Phong, PBR and ShaderMaterial materials, lights, cameras.
- Constraints, morph targets and weights, skins, physics bodies, particle systems, levels of detail, audio players.
- Scene settings: environment, fog, post-processing.

## Archive gaps that block moving content out of code

| Gap | Slides | Issue |
|---|---|---|
| Running actions (`repeatForever`, sequences) are not saved. | Nearly every slide: spins, orbits, hops, fades. | #179 |
| Animation clips and players are not saved. | glTF & Model I/O, Animation Blending | #179 |
| Shadows, debug mode, selection outline and gizmos are `SceneView` settings, not scene data. | Shadows, Debug Views, Gizmos | |
| No slide or deck structure: titles, order, transitions and notes live in `KeynoteDemo`. | All | |

## Per slide

| Slide | Data | Code |
|---|---|---|
| SceneSprockets | Titles, light. | Breaking the titles into tumbling letters (#311). |
| SceneView | Shapes, frame, code panel. | None, apart from actions. |
| Scene Graph | Sun, planets, moon, ring, orbit paths, lights. | None, apart from the orbit and spin actions. |
| Shapes | Shapes, materials, light. | None, apart from spin actions. |
| Materials | Shapes, materials, lights. | None, apart from spin actions. |
| Lights | Floor, spheres, lights, light markers. | None, apart from the orbit actions. |
| Shadows | Stage, sun, floor, shapes. | Turning shadows on (a `SceneView` setting) and keeping them on through transitions (#326). |
| Fog | Pillars, ground, moon light, fog settings. | Easing the fog in and out with the transition (#333). |
| Opacity & Fades | Spheres, materials. | None, apart from fade actions. |
| Blend Modes | Stripes, discs, materials with render states, labels. | None, apart from the slide action. |
| Glass | Wall, bars, glass shapes. | None, apart from spin actions. |
| PBR Extensions | Shapes, PBR materials. | Turning each piece every frame (actions could do this). |
| Custom Shaders | Shapes, ShaderMaterials. | The shader functions are Metal code. |
| glTF & Model I/O | Model files (plant, pedestal). | Advancing the plant's animation player (#179); adding glow, lights and trails to the fireflies. |
| Actions | Cubes. | The action sequences themselves (#179). |
| Implicit Animation | Cubes. | Shuffling to random positions in a transaction every 1.6 s. |
| Constraints | Cones, ball, look-at constraints. | None, apart from the pivot action that carries the ball. |
| Animation Blending | Model. | Blending clips with a mixer and controller every frame. |
| Deformation | Blob with morph targets, tube with skin. | Changing morph weights and joint transforms over time. |
| Particles | Campfire, geyser, fireworks particle systems. | Flickering the campfire light every frame. |
| Mesh Emitters | Fox model, emitter. | Restarting the fox; feeding the skinned positions to the emitter every frame. |
| Physics | Tray, dice, physics bodies. | Stepping the physics world with tilted gravity; throwing the dice on reset. |
| Post-Processing | Scene, post-processing settings. | Cycling through the grades over time. |
| Level of Detail | Shapes with levels of detail. | Moving the shapes back and forth every frame. |
| Performance | Instanced crates. | Moving the crates in a wave every frame. |
| SwiftECS World | Boid nodes. | The SwiftECS flocking system, run every frame. |
| Hit Testing | Targets. | Making a tapped target hop. |
| Gizmos | Box. | Selecting the box and cycling gizmo modes (`SceneView` settings). |
| Debug Views | Shapes, d20. | Cycling the debug mode (a `SceneView` setting) and its label. |
| Thank You | Title, finale lights, spheres, glass, particle systems. | Revealing the finale 0.5 s after the slide appears; restarting the particles; the title pulse. |

## Summary

- Most slides are data plus simple repeating actions. Saving running actions (#179) would move most of the keynote into stored scenes.
- What remains in code is per-frame logic (physics, boids, morph and joint animation, mesh emitters, fog easing), timed sequences between slides, and `SceneView` settings. These are what a scripting layer (#346) would need to express.
