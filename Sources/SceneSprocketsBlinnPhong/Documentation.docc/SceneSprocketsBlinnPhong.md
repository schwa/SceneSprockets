# ``SceneSprocketsBlinnPhong``

Blinn-Phong materials for SceneSprockets.

## Overview

``BlinnPhongSceneMaterial`` has ambient, diffuse, specular and emission colors or textures, a normal map and opacity. To draw meshes that use it, add a ``BlinnPhongMaterialRenderer`` to the renderers of a `SceneView` or `SceneGraphElement`. ``BlinnPhongSceneGraphElement`` is a shortcut for a scene that uses only Blinn-Phong materials.

The renderer draws repeated meshes with automatic instancing. It samples the shadow of each light when it shades a pixel.

## Topics

### Materials and Rendering

- ``BlinnPhongSceneMaterial``
- ``BlinnPhongMaterialRenderer``
- ``BlinnPhongSceneGraphElement``
