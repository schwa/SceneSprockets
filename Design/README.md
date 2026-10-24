# SceneSprocketsComposer icon

Open `SceneSprocketsComposer.icon` in Apple's Icon Composer. It contains a native background gradient, an editable SVG construction grid, and a transparent PNG cube in a separate group. Position, scale, shadows, background, and material settings remain editable. The cube's rendered highlights are part of its artwork; its glass effect is disabled to avoid applying a second effect.

`SceneSprocketsComposer-preview.png` and `SceneSprocketsComposer.icns` were exported through Xcode 27's asset compiler. Compilation succeeded for macOS with a minimum deployment target of 26.0. This design is installed at `../SceneSprocketsComposer/SceneSprocketsComposer/AppIcon.icon`. The app target selects it through `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

Artwork generated with the built-in image generation tool. Generation prompt:

```text
Use case: stylized-concept
Asset type: transparent foreground artwork for a macOS 27 scene editor app icon, SceneSprocketsComposer, assembled in Apple Icon Composer.
Subject: ONE large beautifully sculpted isometric cube, slightly beveled solid geometry, three visible faces. Cool luminous cyan top face, rich cobalt blue left face, violet indigo right face. Precision-machined translucent colored optical glass with restrained internal depth and clean broad surfaces. A thin bright rim defines edges. Simple bold silhouette recognizable at 32 pixels. Sophisticated Apple pro creative-tool aesthetic.
Composition: square 1024 canvas, cube centered horizontally and slightly above center, occupying about 65 percent canvas width and 65 percent height; all artwork within generous transparent margins. View from above, vertical edges vertical. Isolated cube only.
Lighting: refined soft studio highlights, restrained reflections, dimensional and tactile, no sparkles.
Constraints: genuinely transparent background. No icon tile, no rounded square background, no floor, no ground shadow, no grid, no text, no letters, no additional objects, no gears, no orbit rings, no tiny details. This is just ONE independent foreground layer; background and grid will be separate editable layers.
```
