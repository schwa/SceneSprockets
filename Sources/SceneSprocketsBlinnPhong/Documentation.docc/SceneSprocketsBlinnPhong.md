# ``SceneSprocketsBlinnPhong``

Blinn-Phong materials for SceneSprockets.

## Overview

``BlinnPhongSceneMaterial`` has ambient, diffuse, specular and emission colors or textures, a normal map and opacity. Add a ``BlinnPhongMaterialRenderer`` to the renderers of a `SceneView` or `SceneGraphElement` to draw meshes that use it. ``BlinnPhongSceneGraphElement`` is a shortcut for a scene that uses only Blinn-Phong materials.

The renderer draws repeated meshes with automatic instancing and samples each light's shadow while shading.

## Topics

### Materials and Rendering

- ``BlinnPhongSceneMaterial``
- ``BlinnPhongMaterialRenderer``
- ``BlinnPhongSceneGraphElement``
