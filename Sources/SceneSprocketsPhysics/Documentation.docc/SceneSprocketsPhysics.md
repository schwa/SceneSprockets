# ``SceneSprocketsPhysics``

Rigid-body physics for scene graph nodes, on Jolt.

## Overview

Give a node a `physicsBody`: static, dynamic or kinematic, with a box, sphere, capsule, cylinder, convex hull or mesh shape. A ``SceneGraphPhysicsWorld`` simulates every node with a body. Call `step(deltaTime:)` each frame. The physics world then writes the new positions and rotations to the nodes.

```swift
die.physicsBody = .init(type: .dynamic, shape: .convexHull)
let physics = try SceneGraphPhysicsWorld(sceneGraph: sceneGraph)
physics.setAngularVelocity(spin, of: die)
physics.step(deltaTime: deltaTime)
```

## Topics

### Simulation

- ``SceneGraphPhysicsWorld``
