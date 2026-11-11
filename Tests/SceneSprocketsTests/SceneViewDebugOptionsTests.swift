import MetalSprocketsSupport
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import Testing

// #365: debug options can be turned on from environment variables.
@Test
func debugOptionsComeFromEnvironmentVariables() {
    #expect(SceneView.Options.debugOptions(from: SystemEnvironment(variables: [:])).isEmpty)
    let environment = SystemEnvironment(variables: ["SS_SHOWS_STATISTICS": "1", "SS_SHOWS_FRAME_TIMING": "yes", "SS_DISABLES_FRAMEBUFFER_ONLY": "0"])
    #expect(SceneView.Options.debugOptions(from: environment) == [.showsStatistics, .showsFrameTiming])
    #expect(SceneView.Options.debugOptions(from: SystemEnvironment(variables: ["SS_DISABLES_FRAMEBUFFER_ONLY": " TRUE "])) == .disablesFramebufferOnly)
}

@Test
@MainActor
func environmentDebugOptionsAddToCodeOptions() {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    let renderer = BlinnPhongMaterialRenderer()
    func view(_ options: SceneView.Options) -> SceneView {
        SceneView(sceneGraph: sceneGraph, options: options, renderers: [renderer], closuresID: "a")
    }
    let fromEnvironment = SystemEnvironment.$current.withValue(SystemEnvironment(enabled: ["SS_SHOWS_STATISTICS"])) {
        view([.allowsCameraControl])
    }
    let (withStatistics, withoutStatistics) = SystemEnvironment.$current.withValue(SystemEnvironment(variables: [:])) {
        (view([.allowsCameraControl, .showsStatistics]), view([.allowsCameraControl]))
    }
    #expect(fromEnvironment == withStatistics)
    #expect(fromEnvironment != withoutStatistics)
}
