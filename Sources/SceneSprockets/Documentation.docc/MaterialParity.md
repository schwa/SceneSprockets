# Material Parity

How each material renderer handles the techniques that apply to the whole scene.

## Overview

Some techniques are applied by the scene renderer to every mesh, so all material families get them the same way.
Others are implemented by each material renderer on its own, and can differ. `MaterialParityTests` renders the same
scene with a Blinn-Phong and a PBR material and checks the effect of each tested technique.

### Applied by the scene renderer

These do not depend on the material renderer.

| Technique | How | Tested |
|---|---|---|
| Fog | A pass over the color and depth after the meshes. | Yes |
| Color adjustment and vignette | A post-processing pass. | Yes (saturation) |
| Debug views | Every mesh is drawn with one debug material. | Yes (every mode) |
| Hidden nodes, category masks | The scene renderer leaves the meshes out. | Yes (hidden) |
| Soft particles | Particles read the scene depth. | No |

### Implemented by each material renderer

| Technique | Blinn-Phong | PBR | Shader material | Tested |
|---|---|---|---|---|
| Material opacity | Blends. | Blends. | Blends. | Yes |
| Node opacity and fades | Blends; closed meshes draw depth first, so they blend once (#327). | Blends; no depth-first pass. | Blends; no depth-first pass. | No |
| Shadows | Samples the shadow map in its shader. | Samples the shadow map in its shader. | Samples the shadow map in its shader. | No |
| Ambient occlusion | Darkens ambient light only. | Darkens image-based light only. | Not applied. | No |
| Transmission backdrop | Not supported. | Glass refracts the meshes drawn before it, except other PBR meshes (#327). | Not supported. | No |
| Morph targets and skinning | GPU deformation. | Its own skinning and morphing. | GPU deformation. | Yes (morph targets) |
| Material channels | Supported. | Supported. | Not supported. | No |
| Stereo and immersive rendering | Supported. | Supported. | Supported. | No |

### Known differences

- Faded closed meshes blend their back faces over their front faces with PBR and shader materials, but not with
  Blinn-Phong (#327).
- Faded PBR meshes behind PBR glass are missing from the glass's backdrop (#327).
- Ambient occlusion darkens a comparable but different light term in Blinn-Phong and PBR (#136, #408).
