import SceneSprocketDemos
import SwiftUI

// A thin shell: the demos live in the Packages/SceneSprocketDemos package (also runnable from the command
// line as the scenesprocket-demos executable).
@main
struct SceneSprocketDemoApp: App {
    var body: some Scene {
        SceneGraphDemosScene()
    }
}
