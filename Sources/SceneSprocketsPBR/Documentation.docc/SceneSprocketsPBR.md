# ``SceneSprocketsPBR``

Physically based materials for SceneSprockets, and loading scenes from glTF and Model I/O.

## Overview

``PBRSceneMaterial`` wraps a MetalSprocketsPBR material: metallic-roughness with most glTF material extensions, such as transmission, volume, clearcoat, sheen, iridescence and anisotropy. Add a ``PBRMaterialRenderer`` to the renderers to draw meshes that use it, and keep one renderer instance across frames so that its model cache is used.

``GLTFSceneGraph`` loads a glTF scene: its hierarchy, meshes with PBR materials, cameras, lights, skins, morph targets and animations. ``ModelIOSceneGraph`` loads any format that Model I/O reads, such as OBJ, PLY, STL, ABC and USD.

## Topics

### Materials and Rendering

- ``PBRSceneMaterial``
- ``PBRMaterialRenderer``

### Loading Scenes

- ``GLTFSceneGraph``
- ``ModelIOSceneGraph``
- ``ModelFile``
- ``ModelFileLoader``
