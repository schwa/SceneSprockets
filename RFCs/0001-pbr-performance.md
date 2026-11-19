# RFC 0001 — PBR performance without forced merging

**Status:** Draft · **Tracking:** #545 · **Related:** #479, #517, #520, #522, #554, #571, #572, MetalSprockets RFC 0006

## Summary

The PBR renderer draws opaque batches in two ways:

- **Per-batch:** one element per batch.
- **Merged** (`PBRMergedGeometry`): one element issues the draws of many batches.

Merging does not combine meshes. Each batch still has its own instanced draw, and the vertex and index buffers are
the asset's own. Merging copies each batch's instances and material data into shared buffers.

Merging is faster because MetalSprockets costs time per element. We want per-batch drawing to be fast too, so that
merging is optional.

## How merging works

At build time, a merged set takes the opaque batches that:

- draw triangles,
- have no morph targets,
- are not blended,
- use the default render state.

Skinned and transmissive batches go in their own sets. A set needs at least two batches.

The set copies, for each batch:

- its instances,
- its material uniforms,
- its material textures (one argument buffer).

At draw time, one element binds these buffers once. Then it issues one draw per batch.

## Problems with merging

- There are two draw paths with different rules.
- Material data is copied at build time, so changing a material later has no effect without an override (#479).
- If one material animates, the uniforms of the whole set are rebuilt every frame (#554).
- A texture override builds a new argument buffer for the whole set every frame.

These problems come from copying the material data. They do not come from drawing many batches from one element.

## Measurements

`ms-gltf-render bench` and `bench --no-merging`. Release, M5 Max, 1024×1024. Milliseconds per frame, CPU / GPU.

| Scene | Merged | Per-batch | CPU × | GPU × |
|---|---|---|---|---|
| ABeautifulGame | 1.33 / 0.89 | 2.45 / 0.80 | 1.8 | 0.9 |
| Sponza | 1.34 / 0.25 | 4.50 / 0.40 | 3.4 | 1.6 |
| NodePerformanceTest | 54.3 / 3.99 | 415.0 / 9.84 | 7.6 | 2.5 |
| SimpleInstancing | 0.55 / 0.05 | 0.54 / 0.06 | 1.0 | 1.0 |
| BrainStem | 0.85 / 0.14 | 5.14 / 0.35 | 6.0 | 2.6 |
| RecursiveSkeletons | 1.17 / 0.13 | 4.78 / 0.16 | 4.1 | 1.3 |
| Fox | 0.58 / 0.05 | 0.58 / 0.03 | 1.0 | 0.7 |
| AnimationPointerUVs | 2.93 / 0.30 | 19.27 / 1.12 | 6.6 | 3.7 |
| AlphaBlendModeTest | 0.73 / 0.08 | 0.92 / 0.06 | 1.3 | 0.7 |
| TransmissionTest | 1.48 / 0.61 | 3.25 / 0.58 | 2.2 | 1.0 |
| CarConcept | 2.42 / 0.60 | 9.21 / 1.35 | 3.8 | 2.2 |

- Per-batch drawing uses 2–8× more CPU when a scene has many batches.
- Per-batch GPU time is also higher in some scenes. We do not know why yet.
- NodePerformanceTest is 8× slower than its old baseline (#571). Fix this first.
- Not measured: memory, energy, Debug builds, the scene graph path.

## Options

1. **Keep material data in shared argument buffers** (do first). One long-lived buffer for all materials, used by
   both paths. Change only the fields that change. This fixes #479, #554 and the texture override cost.
2. **Make elements cheaper in MetalSprockets.** MetalSprockets#519, #522, #513, #476. Helps every renderer. Most work.
3. **Bind less per batch.** Bind the shared buffers once, and pass offsets in each draw.
4. **Sort draws by pipeline and material**, so that we bind state once per group.
5. **Indirect command buffers** (#517). Encode the draws once and reuse them. Needs option 1. Enables GPU culling and
   LOD (#520, #522).

## Plan

1. Fix #571.
2. Profile both paths on CarConcept and AnimationPointerUVs.
3. Do option 1, then options 3 and 4. Measure after each change.
4. Measure again when MetalSprockets changes land.
5. Decide #545.

## Open questions

- How close must per-batch drawing be to merged drawing? For example, within 20% CPU?
- After per-batch drawing is fast, do we keep merging as an option?

## Verification

- Run `just bench-gltf` and `just bench-gltf --no-merging` after each change.
- `MaterialTests` and `MaterialOverrideTests` compare both paths. They must pass.
