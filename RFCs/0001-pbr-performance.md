# RFC 0001 — PBR performance without forced merging

**Status:** Implemented · **Tracking:** #581 · **Milestone:** M007 · **Related:** MetalSprockets RFC 0006

## Summary

The PBR renderer used to draw opaque batches in two ways: one element per batch, or "merged" sets
(`PBRMergedGeometry`) where one element issued the draws of many batches. Merging was much faster, because
MetalSprockets costs time per element, but it was a second draw path with its own rules and copied material data.

Now there is one path. Every batch draws through MetalSprockets' `DrawList` (MetalSprockets#585), which issues many
similar draws from one element. Merged sets and `PBRDrawPlan` are gone (#582).

## How it works

- **Tables, per model.** One table of every batch's instances (rest pose, or a posed table built each frame), one
  table mapping each instance to its material table element, and one table of each element's first joint in a
  palette of every skin.
- **Materials, per renderer.** One material table (`PBRMaterialTable`, #573) with one element per batch: uniforms,
  textures and samplers. A frame writes only what changed. Uniforms are resolved only when a material changed or the
  pose animates it.
- **Shaders.** Every vertex shader reads its instance and its record from the tables; one fragment shader reads the
  material from the record.
- **Draws.** The renderer groups batches by vertex variant and render state (blended batches in back-to-front runs).
  Each group is one pipeline, and consecutive batches on the same geometry are one `DrawList`. Morphed batches, and
  batches drawn with a lines fill mode, keep their own elements: morph targets need per-draw inputs, and `DrawList` has
  no per-row fill mode.

## Measurements

`ms-gltf-render bench`, Release, M5 Max, 1024×1024, CPU ms per frame.

| Scene | Before this work (merged) | Merged, MetalSprockets main | DrawList |
|---|---|---|---|
| NodePerformanceTest | 54.3 | 10.1 | 10.7 |
| CarConcept | 2.42 | 1.67 | 2.4 |
| Sponza | 1.34 | 0.69 | 0.83 |
| AnimationPointerUVs | 2.93 | 2.64 | 2.77 |

Most of the gain came from MetalSprockets fixes found on the way (MetalSprockets#581, #582, #583). The DrawList path
is close to the merged one. CarConcept's extra time is waiting, not CPU work; see #583.

Before this work, drawing each batch as its own element cost 2–35× more CPU than merging (CarConcept 9.2 ms,
NodePerformanceTest 415 ms).

## Done

- `bench --no-merging` to compare the paths (#572; removed with the merged path).
- MetalSprockets: retain each allocation once per submission (MetalSprockets#581), cheaper argument buffer versions
  (MetalSprockets#582), cheaper elements (MetalSprockets#583), DrawList (MetalSprockets#585).
- Per-renderer material table (#573); unused per-material argument buffers removed (#575).
- Every batch through DrawList; merged sets and the draw plan removed (#582).

## Not done

- Indirect command buffers and GPU culling and LOD (#517, #520, #522).
- CarConcept's extra wait (#583).
