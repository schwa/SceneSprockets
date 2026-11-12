# ``SceneSprocketsShaderMaterial``

Draw scene graph meshes with your own Metal shaders.

## Overview

A ``ShaderMaterial`` names a vertex and a fragment function, like SceneKit's `SCNProgram`. It also holds parameters, which the renderer binds by name. Add one ``ShaderMaterialRenderer`` to the renderers. It draws every mesh with a shader material.

The vertex function must declare `constant ShaderMaterialTransforms &transforms`. `ShaderMaterial.h` in `SceneSprocketsShaders` defines it.

### Lights and shadows

Set `samplesShadows` to give the fragment function the scene's lights and shadow map. The renderer binds `lighting`, `lights`, `shadowMap` and `shadowSampler` by name. Call `shaderMaterialShadow` from `ShaderMaterial.h` for each light, so that a light's shadow dims only that light, as in Blinn-Phong and PBR. ``ShaderMaterial/lit(color:opacity:)`` is a sample. Without `samplesShadows`, shadows darken the mesh after the scene pass, by all lights at once.

## Topics

### Materials and Rendering

- ``ShaderMaterial``
- ``ShaderMaterialRenderer``
