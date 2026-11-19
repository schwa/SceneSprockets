# RFC 0001 — PBR performance without forced merging

**Status:** Draft · **Tracking:** #581 · **Decision:** #545 · **Milestone:** M007 · **Related:** MetalSprockets RFC 0006

## Summary

The PBR renderer draws opaque batches in two ways:

- **Per-batch:** one element per batch.
- **Merged** (`PBRMergedGeometry`): one element issues the draws of many batches.

Merging does not combine meshes. Each batch still has its own instanced draw, and the vertex and index buffers are
the asset's own. Merging copies each batch's instances into one buffer.

Merging is faster because MetalSprockets costs time per element. We want per-batch drawing to be fast too, so that
merging is optional.

## How merging works

At build time, a merged set takes the opaque batches that:

- draw triangles,
- have no morph targets,
- are not blended,
- use the default render state.

Skinned and transmissive batches go in their own sets. A set needs at least two batches.

The set copies the instances of each batch, and records which batch each record draws.

At draw time, one element binds the shared buffers once. Then it issues one draw per batch.

## Materials

Each renderer has one material table (`PBRMaterialTable`, #573). The table has one element for each batch, with
its uniforms, textures and samplers. Both paths read it. A frame writes only the elements that changed.

Before #573, each merged set copied the material data at build time. An animated material then rebuilt the uniforms
of the whole set every frame, and a texture override built a new argument buffer every frame.

## Measurements

`ms-gltf-render bench` and `bench --no-merging`. Release, M5 Max, 1024×1024. Milliseconds per frame, CPU / GPU.

| Scene | Merged, start | Merged, now | Per-batch, now |
|---|---|---|---|
| ABeautifulGame | 1.33 / 0.89 | 1.08 / 0.83 | 2.52 / 1.12 |
| Sponza | 1.34 / 0.25 | 0.65 / 0.20 | 4.68 / 0.38 |
| NodePerformanceTest | 54.3 / 3.99 | 10.3 / 1.51 | 369 / 5.98 |
| SimpleInstancing | 0.55 / 0.05 | 0.57 / 0.06 | 0.58 / 0.06 |
| BrainStem | 0.85 / 0.14 | 0.58 / 0.12 | 4.92 / 0.31 |
| RecursiveSkeletons | 1.17 / 0.13 | 0.78 / 0.07 | 4.88 / 0.17 |
| Fox | 0.58 / 0.05 | 0.61 / 0.05 | 0.62 / 0.04 |
| AnimationPointerUVs | 2.93 / 0.30 | 2.76 / 0.29 | 19.6 / 1.21 |
| AlphaBlendModeTest | 0.73 / 0.08 | 0.69 / 0.07 | 0.95 / 0.06 |
| TransmissionTest | 1.48 / 0.61 | 1.42 / 0.61 | 3.37 / 0.64 |
| CarConcept | 2.42 / 0.60 | 1.56 / 0.57 | 9.53 / 1.35 |

"Start" is before this work. "Now" is MetalSprockets 0.3.6 with the material table.

- Per-batch drawing still uses 2–35× more CPU when a scene has many batches.
- Per-batch GPU time is also higher in some scenes. We do not know why (#578).
- Not measured: memory, energy, Debug builds, the scene graph path.

## Progress

| Change | Result |
|---|---|
| `bench --no-merging` (#572) | Both paths can be measured. |
| MetalSprockets 0.3.6: retain each allocation once (MetalSprockets#581) | NodePerformanceTest 54.3 → 10.3 ms CPU. Every scene faster. Fixes #571. |
| Material table (#573) | Both paths read one table. Static scenes unchanged. AnimationPointerUVs merged 2.34 → 2.76 ms CPU: each frame builds a new argument buffer version (MetalSprockets#582). |

## Options

1. **Material table.** Done (#573). Waits for MetalSprockets#582 to make animated materials cheap.
2. **Make elements cheaper in MetalSprockets.** MetalSprockets#476, #513, #519, #522. Helps every renderer. Most work.
3. **Bind less per batch** (#576). Bind the shared buffers once, and pass offsets in each draw.
4. **Sort draws by material** (#577), so that we bind state once per group.
5. **Indirect command buffers** (#517). Encode the draws once and reuse them. Enables GPU culling and LOD (#520,
   #522).

## Plan

1. Fix MetalSprockets#582, then measure AnimationPointerUVs again.
2. Remove the unused material argument buffers (#575).
3. Try options 3 and 4. Measure after each change.
4. Measure again when MetalSprockets changes from option 2 land.
5. Record a new benchmark baseline (#574).
6. Decide #545.

## Open questions

- How close must per-batch drawing be to merged drawing? For example, within 20% CPU?
- After per-batch drawing is fast, do we keep merging as an option?

## Verification

- Run `just bench-gltf` and `just bench-gltf --no-merging` after each change.
- `MaterialTests` and `MaterialOverrideTests` compare both paths. They must pass.
