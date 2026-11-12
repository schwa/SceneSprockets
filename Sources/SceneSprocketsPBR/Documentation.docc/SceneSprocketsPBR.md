# ``SceneSprocketsPBR``

Physically based materials for SceneSprockets, and loading scenes from glTF and Model I/O.

## Overview

``PBRSceneMaterial`` wraps a MetalSprocketsPBR material: metallic-roughness with most glTF material extensions, such as transmission, volume, clearcoat, sheen, iridescence and anisotropy. To draw meshes that use it, add a ``PBRMaterialRenderer`` to the renderers. Keep one renderer instance across frames, because the renderer caches its model.

``ModelFile/load(_:materials:)`` loads a model file and returns a ``ModelFile/Result``: the root node, its animations, warnings and, for glTF, material variants and the image-based light. glTF files keep their hierarchy, meshes with PBR materials, cameras, lights, skins, morph targets and animations. Formats that Model I/O reads, such as OBJ, PLY, STL, ABC and USD, keep their hierarchy, meshes, cameras, lights, skins and joint animation.

## Topics

### Materials and Rendering

- ``PBRSceneMaterial``
- ``PBRMaterialRenderer``

### Loading Scenes

- ``ModelFile``
- ``ModelFileLoader``
