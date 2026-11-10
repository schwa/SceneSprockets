# SceneSprocketsDemoSupport

This package has the SceneSprockets demos. It contains the `SceneSprocketsDemoSupport` library (all demos and a DemoKit picker, `SceneGraphDemosScene`), the `scenesprockets-demos` executable, and the demo render tests. Each demo has a scene outline, a node inspector, an interactive camera and click-to-pick.

- **Xcode:** `Examples/SceneSprocketsDemo/SceneSprocketsDemo.xcodeproj` is a thin app around `SceneGraphDemosScene`.
- **Command line:** `xcb run scenesprockets-demos` opens the picker. `scenesprockets-demos --list` lists demo IDs. `scenesprockets-demos --render <id> [file.png] [--size 1280x800] [--frames 60]` renders a demo offscreen to a PNG without opening a window.
- **Golden images:** the tests render some demos offscreen and compare them with images in `Tests/SceneSprocketsDemoSupportTests/Golden Images`. If a golden image is missing, the test fails and writes the render to `$TMPDIR/SceneSprocketsDemoSupport-GoldenImages`. Look at the render. If it is correct, copy it into `Golden Images`.
