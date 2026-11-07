# Animation

Move nodes with actions, transactions, keyframed clips and constraints, and deform meshes with morph targets and skins.

## Actions

``SceneGraph/Action`` works like SceneKit's `SCNAction`:

```swift
node.run(.sequence([
    .move(by: [0, 1, 0], duration: 1),
    .rotate(by: .pi, around: [0, 1, 0], duration: 1),
]), forKey: "hop")
```

There are actions to move, rotate and scale (by and to), fade, wait, hide, unhide and remove a node, run custom code, and combine actions in sequences, groups and repeats, with timing modes. ``SceneView`` runs actions every frame. Without it, call `sceneGraph.advanceActions(by:)` each frame.

## Implicit animation

``SceneGraph/Transaction`` works like `SCNTransaction`. It animates transform and morph weight changes from their old values:

```swift
SceneGraph.Transaction.animate(duration: 0.5) {
    node.trs.translation = [0, 2, 0]
}
```

Transactions run as node actions, so they need `advanceActions(by:)`. `Transaction.withoutAnimation { }` applies changes immediately.

## Keyframed clips

A ``SceneGraph/AnimationClip`` has channels that animate node translation, rotation, scale, morph weights or custom properties. Interpolation can be step, linear (slerp for rotations) or glTF cubic spline. Call `clip.apply(at:looping:)`, or use a ``SceneGraph/AnimationPlayer`` and call `advance(by:)` each frame. ``SceneGraph/AnimationMixer`` blends clips in layers, and ``SceneGraph/AnimationStateMachine`` switches between them.

## Constraints

``SceneGraph/Constraint`` works like SceneKit's constraints:

```swift
node.constraints = [.lookAt(target: other)]
```

There are look-at, billboard, distance, replicator, avoid-occluder, inverse kinematics and acceleration constraints, and `.transform` for a custom closure. ``SceneView`` applies them every frame after actions. Without it, call `sceneGraph.applyConstraints(pointOfView:)`.

## Morph targets and skins

- **Morph targets.** `node.morphTargets` holds deltas for each vertex, and `node.morphWeights` holds the weights. They are on the node because a mesh cannot hold them.
- **Skins.** `node.skin` (a ``SceneGraph/Skin`` with joint nodes and inverse bind matrices) and `node.skinVertices` hold skinning data. Joints are ordinary nodes, so you animate them like other nodes.

The PBR renderer deforms meshes on the GPU. Blinn-Phong and shader materials deform them on the CPU every frame, which is slower for large meshes.
