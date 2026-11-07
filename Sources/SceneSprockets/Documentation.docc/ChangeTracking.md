# Change Tracking and Queries

Skip work when nothing changed, find meshes and lights, hit-test, and measure bounds.

## Revisions

``SceneGraph/Revision-swift.struct`` has a `structure` value and a `transform` value:

- Hierarchy, content, visibility, skin and morph target edits change `structure`.
- Transform and morph weight edits change `transform`.

If you compare revisions, you can skip work when nothing changed.

## Cached queries

`meshEntries()`, `lightNodes()` and `cameraNodes()` share one traversal. SceneSprockets caches it by revision. Each ``SceneGraph/MeshEntry`` is one submesh of a node, with its material and world transform.

## Hit testing

`sceneGraph.hitTest(_:)` returns every triangle that a GeometryLite3D `Ray3D` hits, nearest first. Each ``SceneGraph/Hit`` has the node, submesh, triangle index, distance, position and normal. Skinned and morphed meshes use their deformed positions. `ViewProjection.ray(through:)` makes the ray for a point in a view.

## Bounds

`node.meshBounds`, `node.subtreeBounds`, `sceneGraph.bounds` and `sceneGraph.worldBounds(of:)` return `BoundingBox3D` values. SceneSprockets caches them by revision.

Position, bounds and hit tests read mesh vertex buffers on the CPU. The buffers must use shared storage.
