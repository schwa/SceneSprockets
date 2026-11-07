# ``SceneSprocketsShaderMaterial``

Draw scene graph meshes with your own Metal shaders.

## Overview

A ``ShaderMaterial`` names a vertex and a fragment function and holds parameters that are bound by name, like SceneKit's `SCNProgram`. Add one ``ShaderMaterialRenderer`` to the renderers, and it draws every mesh with a shader material.

The vertex function must declare `constant ShaderMaterialTransforms &transforms`. `ShaderMaterial.h` in `SceneSprocketsShaders` defines it.

## Topics

### Materials and Rendering

- ``ShaderMaterial``
- ``ShaderMaterialRenderer``
