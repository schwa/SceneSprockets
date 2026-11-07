# ``SceneSprockets``

A 3D scene graph for MetalSprockets, with an API modeled on SceneKit.

## Overview

A ``SceneGraph`` holds a tree of ``SceneGraph/Node`` values. Nodes have transforms and content: a mesh with materials, a ``Camera``, or a ``Light``. ``SceneView`` shows a scene graph in SwiftUI. ``SceneGraphElement`` draws it inside a MetalSprockets `RenderView`.

Materials are plain values. A renderer for each material family draws the meshes that use it. The Blinn-Phong, PBR and shader material renderers are in their own products, so an app links only what it uses. To add a material family, write a ``SceneGraphMaterialRenderer``.

SceneSprockets stores node data in a SwiftECS `World`. Your app can query this world and add its own components.

## Topics

### Essentials

- <doc:GettingStarted>
- ``SceneGraph``
- ``SceneGraph/Node``
- ``SceneGraph/Shape``
- ``Camera``
- ``Light``
- ``Material``
- ``MaterialTexture``
- ``VideoTexture``

### Rendering

- <doc:Rendering>
- ``SceneView``
- ``SceneViewDelegate``
- ``SceneGraphElement``
- ``SceneGraphMaterialRenderer``
- ``SceneGraphRenderContext``
- ``SceneGraphShadows``
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

- ``SceneCameraControl``
- ``SceneViewManipulator``
- ``SceneViewport``

### Particles, Physics and Audio

- ``SceneParticleSystem``
- ``SceneGraph/PhysicsBody``
- ``SceneAudio``

### Saving and Loading

- ``SceneArchive``
- ``SceneArchiveContext``
- ``SceneArchiveError``
- ``ArchivableMaterial``

### Entity Components

- <doc:WorkingWithTheWorld>
- ``NodeReferenceComponent``
- ``SceneGraphMembershipComponent``
- ``SiblingIndexComponent``
