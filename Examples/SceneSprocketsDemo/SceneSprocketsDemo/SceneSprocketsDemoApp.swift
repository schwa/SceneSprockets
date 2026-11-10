import SceneSprocketsDemoSupport
import SwiftUI

// A thin shell: the demos live in the Packages/SceneSprocketsDemoSupport package (also runnable from the command
// line as the scenesprockets-demos executable).
@main
struct SceneSprocketsDemoApp: App {
    var body: some Scene {
        SceneGraphDemosScene()
    }
}
