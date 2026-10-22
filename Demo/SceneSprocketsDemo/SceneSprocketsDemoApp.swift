import SceneSprocketsDemos
import SwiftUI

// A thin shell: the demos live in the Packages/SceneSprocketsDemos package (also runnable from the command
// line as the scenesprockets-demos executable).
@main
struct SceneSprocketsDemoApp: App {
    var body: some Scene {
        SceneGraphDemosScene()
    }
}
