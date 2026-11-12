import MetalSprocketsSupport
@testable import SceneSprockets
@testable import SceneSprocketsBlinnPhong
import Testing

// #365: debug settings can be turned on from environment variables.
@Test
func debugFlagsComeFromEnvironmentVariables() {
    #expect(SceneView.DebugFlags(environment: SystemEnvironment(variables: [:])) == SceneView.DebugFlags())
    let environment = SystemEnvironment(variables: ["SS_SHOWS_STATISTICS": "1", "SS_SHOWS_FRAME_TIMING": "yes", "SS_DISABLES_FRAMEBUFFER_ONLY": "0"])
    #expect(SceneView.DebugFlags(environment: environment) == SceneView.DebugFlags(showsStatistics: true, showsFrameTiming: true))
    #expect(SceneView.DebugFlags(environment: SystemEnvironment(variables: ["SS_DISABLES_FRAMEBUFFER_ONLY": " TRUE "])) == SceneView.DebugFlags(keepsDrawableReadable: true))
}

@Test
@MainActor
func environmentDebugFlagsAddToCodeSettings() {
    let sceneGraph = SceneGraph(root: SceneGraph.Node())
    let renderer = BlinnPhongMaterialRenderer()
    func view() -> SceneView {
        SceneView(sceneGraph, renderers: [renderer]).sceneCameraControl()
    }
    let fromEnvironment = SystemEnvironment.$current.withValue(SystemEnvironment(enabled: ["SS_SHOWS_STATISTICS"])) {
        view()
    }
    let (withStatistics, withoutStatistics) = SystemEnvironment.$current.withValue(SystemEnvironment(variables: [:])) {
        (view().sceneStatistics(), view())
    }
    #expect(fromEnvironment == withStatistics)
    #expect(fromEnvironment != withoutStatistics)
}

// #369: a mesh whose material has no renderer is skipped, and the skip is reported.
@Test
func missingRendererIsReported() {
    struct UnrenderedMaterial: SceneMaterial {}
    let root = SceneGraph.Node(content: .mesh(SceneGraph.Shape.box().metalMesh(), material: UnrenderedMaterial()))
    let partitions = partitionMeshEntries(SceneGraph(root: root).meshEntries(), renderers: [BlinnPhongMaterialRenderer()])
    #expect(partitions.flatMap(\.self).isEmpty)
    #expect(MissingRendererWarning.hasReported(UnrenderedMaterial.self))
}
