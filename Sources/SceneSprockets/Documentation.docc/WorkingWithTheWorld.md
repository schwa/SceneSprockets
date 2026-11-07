# Working with the World

Query and change nodes through the SwiftECS world that stores them.

## Overview

`sceneGraph.world` is a SwiftECS `World`. Every node under the root is an entity with `Node…Component` values, such as `NodeTransformComponent` and `NodeIsVisibleComponent`. ``NodeReferenceComponent`` links an entity to its node.

An ECS app can add its own components to these entities and query or write the node components directly:

- Writes update the nodes, their revisions and SwiftUI observation, like the node API.
- Transactions do not animate them.
- `ChildOf` and ``SiblingIndexComponent`` edits move nodes in the tree. `setParent(nil)` removes the node from the graph, like `removeFromParent()`. If you destroy an entity, SceneSprockets removes its node from the tree.
- SceneSprockets ignores entities without a node, and `ChildOf` edges to them.

## Share a world

`SceneGraph(root:world:)` uses a world that your app owns. Several scene graphs can share one world. ``SceneGraphMembershipComponent`` identifies the scene graph of each entity.
