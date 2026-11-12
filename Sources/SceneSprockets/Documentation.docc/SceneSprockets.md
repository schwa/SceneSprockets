# ``SceneSprockets``

A 3D scene graph for MetalSprockets, with an API modeled on SceneKit.

## Overview

A ``SceneGraph`` holds a tree of ``SceneGraph/Node`` values. Nodes have transforms and content: a mesh with materials, a ``Camera``, or a ``Light``. ``SceneView`` shows a scene graph in SwiftUI. ``SceneGraphElement`` draws it inside a MetalSprockets `RenderView`.

Materials are plain values. A renderer for each material family draws the meshes that use it. The Blinn-Phong, PBR and shader material renderers are in their own products, so an app links only what it uses. To add a material family, write a ``MaterialRenderer``.

SceneSprockets stores node data in a SwiftECS `World`. Your app can query this world and add its own components.

## Topics

### Essentials

- <doc:GettingStarted>
- ``SceneGraph``
- ``SceneGraph/Node``
- ``SceneGraph/Shape``
- ``Camera``
- ``Light``
- ``SceneMaterial``
- ``MaterialTexture``
- ``VideoTexture``

### Rendering

- <doc:Rendering>
- ``SceneView``
- ``ViewDelegate``
- ``SceneGraphElement``
- ``MaterialRenderer``
- ``RenderContext``
- ``Shadows``
- ``SceneGraph/Environment-swift.struct``
- ``SceneGraph/Fog-swift.struct``
- ``SceneGraph/PostProcessing-swift.struct``
- ``MaterialRenderState``

### Animation

- <doc:Animation>
- ``SceneGraph/Action``
- ``SceneGraph/Transaction``
- ``SceneGraph/AnimationClip``
- ``SceneGraph/AnimationPlayer``
- ``SceneGraph/AnimationMixer``
- ``SceneGraph/AnimationStateMachine``
- ``SceneGraph/Constraint``
- ``SceneGraph/MorphTarget``
- ``SceneGraph/Skin``

### Queries and Hit Testing

- <doc:ChangeTracking>
- ``SceneGraph/Revision-swift.struct``
- ``SceneGraph/MeshEntry``
- ``SceneGraph/Hit``
- ``SceneGraph/HitTestOptions``

### Interaction

- ``CameraControl``
- ``ViewManipulator``
- ``Viewport``

### Particles, Text, Physics and Audio

- ``SceneParticleSystem``
- ``SceneText``
- ``SceneGraph/PhysicsBody``
- ``Audio``

### Saving and Loading

- ``Archive``
- ``ArchiveContext``
- ``ArchiveError``
- ``ArchivableMaterial``

### Entity Components

- <doc:WorkingWithTheWorld>
- ``NodeReferenceComponent``
- ``MembershipComponent``
- ``SiblingIndexComponent``
