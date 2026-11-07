# ``SceneSprocketsShaderMaterial``

Draw scene graph meshes with your own Metal shaders.

## Overview

A ``ShaderMaterial`` names a vertex and a fragment function, like SceneKit's `SCNProgram`. It also holds parameters, which the renderer binds by name. Add one ``ShaderMaterialRenderer`` to the renderers. It draws every mesh with a shader material.

The vertex function must declare `constant ShaderMaterialTransforms &transforms`. `ShaderMaterial.h` in `SceneSprocketsShaders` defines it.

## Topics

### Materials and Rendering

- ``ShaderMaterial``
- ``ShaderMaterialRenderer``
