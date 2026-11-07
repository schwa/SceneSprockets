# Rendering

Draw a scene graph with one or more material renderers, and add shadows, fog and post-processing.

## Use a SceneGraphElement

``SceneView`` is the simplest way to show a scene. For more control, put a ``SceneGraphElement`` in a MetalSprockets `RenderView`. Give it one renderer for each material family that the scene uses:

```swift
@State private var pbrRenderer = PBRMaterialRenderer(device: MTLCreateSystemDefaultDevice()!)

RenderView { _, size in
    SceneGraphElement(
        sceneGraph: sceneGraph,
        aspectRatio: Float(size.width / size.height),
        renderers: [BlinnPhongMaterialRenderer(), pbrRenderer]
    )
}
```

- **Camera.** The default camera is the first camera node, at its world transform. To select a different camera node, use `camera:`. To replace the world transform of the camera, for example with an interactive camera, use `cameraMatrix:`.
- **One pass.** All renderers draw in one render pass and share the depth buffer. The pass uses reversed depth (near 1, far 0, compare `.greater`), because MetalSprocketsPBR needs it. ``SceneGraphRenderContext/projectionMatrix`` already contains the depth flip. If you write a renderer, use `.greater` depth tests.
- **Unclaimed meshes.** The element does not draw meshes whose material type has no renderer.
- **Keep the PBR renderer.** `PBRMaterialRenderer` caches its model and rebuilds it only when the structure changes. Keep one instance across frames, for example in `@State`.

## Environment, fog and post-processing

- **Environment.** `sceneGraph.environment` sets the background (none, a color, the environment map with blur, or a sky gradient that works with any renderer) and the image-based lighting map, intensity and rotation. The PBR renderer uses the map for lighting. Blinn-Phong ignores it.
- **Fog.** `sceneGraph.fog` takes a ``SceneGraph/Fog-swift.struct``, like SceneKit's fog properties. A screen-space pass after every renderer blends fog into geometry by camera distance. Fog does not change the background.
- **Post-processing.** `sceneGraph.postProcessing` takes a ``SceneGraph/PostProcessing-swift.struct`` with exposure, contrast, saturation and vignette.

## Shadows

Pass a ``SceneGraphShadows`` to `SceneView(shadows:)` or `SceneGraphElement(shadows:)`. Keep one instance across frames. Directional, spot and point lights cast shadow maps from meshes with `castsShadow`. Blinn-Phong and PBR sample the shadows when they shade a pixel. For other materials, a screen-space pass darkens shadowed pixels after the scene pass, so shadows work with every renderer.

Fog and shadows need a color texture with `.shaderWrite` usage and a depth texture with `.shaderRead` usage. ``SceneView`` configures these textures.

## Custom shaders

`ShaderMaterial(vertexShader:fragmentShader:parameters:)`, in `SceneSprocketsShaderMaterial`, draws a mesh with your own Metal functions, like SceneKit's `SCNProgram`. Add one `ShaderMaterialRenderer()` to the renderers. It draws every `ShaderMaterial`. The vertex function must declare `constant ShaderMaterialTransforms &transforms` (see `ShaderMaterial.h` in `SceneSprocketsShaders`). The renderer binds `parameters` by name.

## Add a material family

A material is a value that conforms to ``Material``. A renderer that conforms to ``SceneGraphMaterialRenderer`` draws the mesh entries that use it. You do not change the scene graph to add one.

```swift
struct UnlitMaterial: SceneSprockets.Material {
    var color: SIMD3<Float>
}

struct UnlitRenderer: SceneGraphMaterialRenderer {
    var materialType: any SceneSprockets.Material.Type { UnlitMaterial.self }

    func makeElement(entries: [SceneGraph.MeshEntry], context: SceneGraphRenderContext) throws -> AnyElement {
        // Draw entries[i].mesh.submeshes[entries[i].submeshIndex] at entries[i].worldTransform.
    }
}
```
