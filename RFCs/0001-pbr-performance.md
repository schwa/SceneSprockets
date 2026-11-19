# RFC 0001 — PBR performance without forced merging

**Status:** Draft
**Author:** schwa
**Date:** 2026-11-19
**Tracking issue:** #545
**Related issues:** #479, #517, #520, #522, #554, #571, #572; MetalSprockets RFC 0006, MetalSprockets#476, #513, #519, #522

## Summary

The PBR renderer merges opaque, unmorphed triangle primitives into shared buffers (`PBRMergedGeometry`), so one draw
element issues many Metal draws. Merging is fast today, but it exists mostly to work around MetalSprockets' cost per
element, and it makes the renderer harder to change. This RFC records how the renderer performs now. It also lists
other ways to get the same speed, so that merging becomes an optimization the renderer can choose, not a requirement.

## Motivation

Merging has costs (from #545):

- Two drawing paths with different rules: merged (opaque static and skinned) and per-batch (blended, morphed,
  transmissive).
- Live material changes need overrides, and some changes need a model rebuild (#479).
- Geometry is copied into the shared buffers and rebuilt with the model.
- Per-frame material uniform arrays are rebuilt for animated materials (#554).

If per-batch drawing were fast enough, the renderer could drop these costs, or keep merging only where it clearly
helps.

## Goals

- Per-batch drawing within a small margin of merged drawing on the benchmark scenes (target to be agreed; see Open
  questions).
- Keep each improvement measurable with `ms-gltf-render bench` and `bench --no-merging` (#572).
- Prefer improvements that help every renderer (Blinn-Phong, shader materials), not only PBR.

## Non-goals

- Removing merging in this RFC. That decision waits for the measurements below to change.
- New lighting or material features.
- GPU-bound costs (shading, transmission pre-pass). The gap is mostly CPU.

## Measurements

`ms-gltf-render bench` vs `bench --no-merging`. Release, M5 Max (Mac17,6), 1024×1024, 60 frames after 30 warm-up
frames, fastest of 3 rounds. Median ms per frame, CPU / GPU.

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

- Per-batch drawing costs 2–8× more CPU on scenes with many primitives. Single-primitive scenes are equal.
- GPU time is also higher per-batch on some scenes (up to 3.7×). The cause is not known; candidates are per-draw
  binding and state changes, and lost instancing of repeated meshes.
- NodePerformanceTest is 8× slower than its October baseline even when merged (#571). Fix that before comparing it.
- Not measured: memory, energy, Debug builds, the SceneSprockets scene graph path (only `PBRScene` via glTF).

## Where the time goes

Not yet profiled per path. From MetalSprockets RFC 0006 the per-element cost is mostly in reconciliation (update),
then workload encoding. Merging reduces the number of elements, so it skips both. Each alternative below targets one
of these costs.

## Alternatives

Each is independent and can be measured on its own.

### 1. Cheaper elements in MetalSprockets

Lower the per-element cost so per-batch drawing is cheap enough. Continues RFC 0006.

- Reuse draw subtrees that did not change between frames (MetalSprockets#519).
- A closure-free `Draw` element (MetalSprockets#522).
- Do not rebuild `ParameterSet` (MetalSprockets#513) or re-bind argument tables (MetalSprockets#476) for every draw.

Helps every renderer. Largest expected win, largest effort.

### 2. Shared buffers without merged draws

Merging does two things: it puts geometry in shared buffers, and it collapses many draws into one element. Keep the
shared vertex, index and material buffers (one bind per frame) but emit one element per batch with `baseVertex` and
index offsets. This measures how much of the gain comes from fewer elements and how much from fewer buffer binds.

### 3. Instancing repeated meshes

Draw nodes that share a mesh and material as one instanced draw, including outside `EXT_mesh_gpu_instancing`. This
reduces both elements and Metal draws without merging buffers. It may explain part of the GPU difference.

### 4. Indirect command buffers and GPU-driven drawing

Encode the draws once into an indirect command buffer and reuse it across frames; update only transforms and
materials (#517). Culling and LOD selection on the GPU then work on the same buffers (#520, #522). This removes the
per-frame CPU cost per draw, but needs an argument-buffer material layout.

### 5. Material data in argument buffers

Keep material uniforms in long-lived argument buffers (MetalSprockets `ArgumentBuffer`, #579) and update changed
fields in place. This removes the per-frame uniform arrays (#554) and the override rules (#479), whether or not
merging stays.

### 6. Sort and group by pipeline state

Sort per-batch draws by pipeline and material so state changes and argument binds happen once per group. This is
cheap to try and lowers both CPU and GPU cost per draw.

## Proposed direction

1. Fix #571 so the benchmark baselines are trustworthy.
2. Profile merged and per-batch drawing on two scenes (CarConcept, AnimationPointerUVs) and split the gap into
   update, encoding and GPU.
3. Try the cheap alternatives first (2, 5, 6) and record each in a Progress table, as RFC 0006 does.
4. Track MetalSprockets#519 and #522. Re-run `bench --no-merging` after each lands.
5. Decide on #545 when per-batch drawing meets the goal, or when the remaining gap is understood.

## Open questions

- What margin counts as "close enough" for per-batch drawing (for example, within 20% CPU on every benchmark scene)?
- Should merging stay as an opt-in optimization for static scenes after per-batch drawing is fast?
- Does the SceneSprockets scene graph path show the same gap as `PBRScene`?

## Verification

- `just bench-gltf` (merged, compared against the baseline) and `just bench-gltf --no-merging` on every change.
- Existing image tests that compare merged and per-batch output (`MaterialTests`, `MaterialOverrideTests`) stay
  green.
