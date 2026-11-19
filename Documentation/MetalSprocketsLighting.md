# MetalSprocketsLighting

Lighting shared by MetalSprockets renderers: one light type, shadow-map sampling, environment lighting (LightingEnvironment), per-frame lighting resources, ambient occlusion input, exposure and tone mapping, so PBR, Blinn-Phong, toon and other shaders light a scene the same way. Each renderer keeps its own BRDF. A product of the SceneSprockets package (`.product(name: "MetalSprocketsLighting", package: "SceneSprockets")`).

Lights follow glTF's `KHR_lights_punctual`: inverse-square falloff with a smooth cutoff at `range`, and spot cones between `outerConeCos` and `innerConeCos`.

## Shaders

Include `MetalSprocketsLightingShaders.h` in Metal or Swift. `MetalSprocketsLightingTypes.h` is plain C and shared with Swift. `MetalSprocketsLighting.h` (Metal only) has the `Lighting` namespace:

```metal
const Lighting::LightSample sample = Lighting::sample(light, position);
const float3 shadowing = Lighting::shadow(light, position, shadowUniforms, shadowMap, shadowSampler);
const float3 radiance = sample.radiance * shadowing;
```
