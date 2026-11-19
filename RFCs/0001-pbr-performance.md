# RFC 0001 — PBR performance without forced merging

**Status:** Draft
**Author:** schwa
**Date:** 2026-11-19
**Tracking issue:** #545
**Related issues:** #479, #517, #520, #522, #554, #571, #572; MetalSprockets RFC 0006, MetalSprockets#476, #513, #519, #522

## Summary

The PBR renderer has two ways to draw opaque batches. The per-batch path uses one MetalSprockets element per batch.
The "merged" path (`PBRMergedGeometry`) issues the Metal draws of many batches from one element. It does not combine
meshes: each primitive still has its own draw call, and the vertex and index buffers are the asset's own. What it
combines is per-batch data: instances, material uniforms and material textures.

The merged path is much faster on CPU today (see Measurements), because MetalSprockets' cost grows with the number of
elements. This RFC describes both paths exactly, records their performance, and lists other ways to get the same
speed. The goal is that merging is an optimization the renderer can choose, not a requirement.

## Terms

- **Primitive** (`PBRModel.Primitive`): one glTF mesh primitive. Its vertices and indices are a range of the asset's
  shared vertex and index buffers (`baseVertex`, `indexStart`).
- **Batch** (`PBRModel.Batch`): one primitive with one material, and every placement of it (its instances).
- **Instancing:** one Metal draw for all instances of a batch (`instanceCount`). Both paths use it.
- **Merged set** (`PBRMergedGeometry`): several batches whose Metal draws one element issues. A model has up to three:
  static, skinned and transmissive (`PBRModel.merged`, `mergedSkinned`, `mergedTransmissive`).

## How the two paths draw

### Per-batch (`PBRRenderer.draw(_:)`)

One element per batch. For each batch it binds:

- the asset's vertex buffer, at the primitive's first vertex,
- the batch's instances (its prebuilt buffer, or this frame's posed instances),
- the batch's material uniforms (`material`) and texture argument buffer (`materialResources`).

It then issues one `drawIndexedPrimitives` per instance range. Instances are split into ranges by mirroring, so a
batch is usually one or two Metal draws.

### Merged (`PBRRenderer.mergedDrawCalls`)

Built once per model by `PBRModelBuilder` from the opaque batches. A batch can be in a merged set when
(`PBRMergedGeometry.canMerge`):

- its primitive draws triangles and has no morph targets,
- its material is not blended and has the default render state,
- it is transmissive only in the transmissive set, and skinned only in the skinned set (skinned transmissive batches are
  not merged).

The set also requires every primitive to use the same geometry buffers as the first one, and at least two batches.

At build time the set copies, per batch (a "record"):

- its instances, into one instance buffer, and an instance-to-record table,
- its resolved material uniforms, into one material buffer,
- its material textures, into one argument buffer,
- for skinned sets, its offset into one joint palette.

It does not copy vertices or indices: `vertexBuffer`, `indexBuffer` and `skinVertexBuffer` are the asset's buffers.

At draw time one element binds the vertex buffer, instance records, material buffer, texture argument buffer and view
once. Then it loops over the records, skips culled ones, sets cull mode and front facing, and issues one
`drawIndexedPrimitives` per record with `baseVertex` and `baseInstance`. The merged shaders find each instance's
material through the instance-to-record table.

So the merged path saves MetalSprockets elements and per-batch binds. It issues about the same number of Metal draws
as the per-batch path.

### Per-frame work on the merged path

- Animated poses: posed instances for every record are built into a new array (`instances(pose:)`). If the pose
  mirrors an instance differently from its rest placement, the set is not used that frame and its batches draw per
  batch.
- Animated materials or uniform overrides: uniforms for every record are built into a new array
  (`materials(pose:overrides:)`), even when only one record changes (#554).
- Texture overrides: a new texture argument buffer for the whole set is built every frame
  (`resources(overrides:)`).
- In-place changes to a `PBRMaterial` after the model is built are not seen, because the set uses its prebuilt
  buffers unless an override or animation applies (#479).

## Motivation

The merged path has costs that the per-batch path does not:

- Two drawing paths with different eligibility rules.
- Material data is copied into each set at build time, so material changes need overrides or a rebuild (#479).
- Animated materials and overrides rebuild whole-set arrays or argument buffers every frame (#554).

These costs come from how the merged path stores material and instance data, not from issuing many draws from one
element. If per-batch drawing were fast enough, or material data were stored differently, the renderer could keep
merging only where it clearly helps.

## Goals

- Per-batch drawing within a small margin of merged drawing on the benchmark scenes (margin to be agreed; see Open
  questions).
- Material and instance changes that cost work in proportion to what changed, on both paths.
- Keep each improvement measurable with `ms-gltf-render bench` and `bench --no-merging` (#572).
- Prefer improvements that help every renderer (Blinn-Phong, shader materials), not only PBR.

## Non-goals

- Removing the merged path in this RFC.
- New lighting or material features.
- GPU-bound costs (shading, transmission pre-pass).

## Measurements

`ms-gltf-render bench` vs `bench --no-merging`. Release, M5 Max (Mac17,6), 1024×1024. Each scene: 60 timed frames
after 30 warm-up frames, run 3 times; the table shows the lowest of the 3 medians. Values are ms per frame,
CPU / GPU. CPU is render-thread time to build and encode the frame; GPU is the frame's command buffer time.

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

Findings:

- Per-batch drawing costs 2–8× more CPU on scenes with many batches. Scenes with one batch are equal.
- Per-batch GPU time is higher on some scenes (up to 3.7×). The cause is not known. Both paths issue about the same
  number of Metal draws, so a likely cause is the per-batch buffer and argument binds; this is not verified.
- NodePerformanceTest is 8× slower than its October baseline on the merged path (#571). Fix that before comparing it.
- Not measured: memory, energy, Debug builds, the SceneSprockets scene graph path (only `PBRScene` via glTF).

## Alternatives

Each is independent and can be measured on its own.

### 1. Material data in long-lived argument buffers (proposed first)

Keep every material's uniforms and textures in long-lived argument buffers (MetalSprockets `ArgumentBuffer`, #579),
one element per material, shared by both paths. Write a field when it changes, and index materials by ID from the
draw. This removes, on the merged path, the per-set copies of material data, the per-frame uniform arrays (#554), the
per-frame texture argument buffers for overrides, and the stale in-place changes (#479). The per-batch path binds one
shared buffer and an index, not a buffer per batch.

### 2. Cheaper elements in MetalSprockets

Lower the per-element cost so per-batch drawing is cheap enough. Continues RFC 0006.

- Reuse draw subtrees that did not change between frames (MetalSprockets#519).
- A closure-free `Draw` element (MetalSprockets#522).
- Do not rebuild `ParameterSet` (MetalSprockets#513) or re-bind argument tables (MetalSprockets#476) for every draw.

Helps every renderer. Largest expected win, largest effort.

### 3. Fewer binds on the per-batch path

The per-batch path already draws from the asset's shared vertex and index buffers, but it binds the vertex buffer at
an offset and binds instances and materials for every batch. Bind the shared buffers once per pipeline and pass
`baseVertex` and an instance offset in the draw instead. Morphed batches need local vertex IDs, so they would keep the
offset bind.

### 4. Sort and group by pipeline state

Sort per-batch draws by pipeline and material so state changes and binds happen once per group.

### 5. Indirect command buffers and GPU-driven drawing

Encode the draws once into an indirect command buffer and reuse it across frames; update only transforms and
materials (#517). Culling and LOD selection on the GPU then work on the same buffers (#520, #522). This removes the
per-frame CPU cost per draw. It needs material data in argument buffers (alternative 1).

## Proposed direction

1. Fix #571 so the benchmark baselines are trustworthy.
2. Profile both paths on CarConcept and AnimationPointerUVs, and split the gap into update, encoding and GPU.
3. Do alternative 1. Re-measure both paths.
4. Try alternatives 3 and 4. Record each change in a Progress table, as RFC 0006 does.
5. Re-run `bench --no-merging` after each MetalSprockets change from alternative 2 lands.
6. Decide on #545 when per-batch drawing meets the goal, or when the remaining gap is understood.

## Open questions

- What margin counts as close enough for per-batch drawing (for example, within 20% CPU on every benchmark scene)?
- Should the merged path stay as an opt-in optimization after per-batch drawing is fast?
- Does the SceneSprockets scene graph path show the same gap as `PBRScene`?

## Verification

- `just bench-gltf` (merged, compared against the baseline) and `just bench-gltf --no-merging` on every change.
- Existing image tests that compare merged and per-batch output (`MaterialTests`, `MaterialOverrideTests`) stay
  green.
