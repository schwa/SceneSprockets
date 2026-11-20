@testable import SceneSprockets
import Testing

// #591: the frame's pass decisions, without rendering.

private func plan(_ configure: (inout SceneFramePlan.Inputs) -> Void) -> SceneFramePlan {
    var inputs = SceneFramePlan.Inputs()
    configure(&inputs)
    return SceneFramePlan(inputs)
}

@Test
func plainFrameHasOnlyTheScenePass() {
    let result = plan { _ in }
    #expect(result.ambientOcclusion == nil)
    #expect(result.postPasses.isEmpty)
    #expect(!result.hasPostPhase)
    #expect(!result.scenePassStoresDepth)
    #expect(result.drawsText)
}

@Test
func postPassesRunInOrder() {
    let result = plan {
        $0.hasPostTargets = true
        $0.hasShadowFrame = true
        $0.hasAmbientOcclusionSettings = true
        $0.opaqueCount = 2
        $0.hasFog = true
        $0.adjustsColor = true
    }
    #expect(result.postPasses == [.shadowMask, .ambientOcclusion, .fog, .colorAdjust])
    #expect(result.hasShadowCasterPass)
    #expect(result.scenePassStoresDepth)
}

@Test
func postPassesNeedPostTargets() {
    let result = plan {
        $0.hasAmbientOcclusionSettings = true
        $0.opaqueCount = 2
        $0.hasFog = true
        $0.adjustsColor = true
        $0.hasSoftParticles = true
    }
    #expect(result.ambientOcclusion == nil)
    #expect(result.postPasses.isEmpty)
    #expect(!result.hasSoftParticlePass)
}

@Test
func shadowCoveringEverythingSkipsTheMask() {
    let result = plan {
        $0.hasPostTargets = true
        $0.hasShadowFrame = true
        $0.shadowMasksEverything = true
    }
    #expect(result.postPasses.isEmpty)
    #expect(result.hasPostPhase)
}

@Test
func ambientOcclusionSplitsMixedInShaderEntries() {
    func ambientOcclusion(opaque: Int, inShader: Int) -> SceneFramePlan.AmbientOcclusion? {
        plan {
            $0.hasPostTargets = true
            $0.hasAmbientOcclusionSettings = true
            $0.opaqueCount = opaque
            $0.inShaderAmbientOcclusionCount = inShader
        }.ambientOcclusion
    }
    #expect(ambientOcclusion(opaque: 3, inShader: 0) == .passes(inShaderDepth: false, appliesAsPostPass: true))
    #expect(ambientOcclusion(opaque: 3, inShader: 1) == .passes(inShaderDepth: true, appliesAsPostPass: true))
    #expect(ambientOcclusion(opaque: 3, inShader: 3) == .passes(inShaderDepth: false, appliesAsPostPass: false))
    #expect(ambientOcclusion(opaque: 0, inShader: 0) == nil)
}

@Test
func debugViewSkipsAmbientOcclusionAndText() {
    let result = plan {
        $0.hasPostTargets = true
        $0.isDebug = true
        $0.hasAmbientOcclusionSettings = true
        $0.opaqueCount = 1
    }
    #expect(result.ambientOcclusion == nil)
    #expect(!result.drawsText)
}

@Test
func softParticlesNeedNoMultisampleResolve() {
    let soft = plan {
        $0.hasPostTargets = true
        $0.hasSoftParticles = true
    }
    #expect(soft.hasSoftParticlePass)
    #expect(soft.scenePassStoresDepth)
    #expect(!soft.particlePassStoresDepth)
    let resolved = plan {
        $0.hasPostTargets = true
        $0.hasSoftParticles = true
        $0.resolvesMultisample = true
    }
    #expect(!resolved.hasSoftParticlePass)
}

@Test
func memorylessDepthIsNotStored() {
    #expect(plan { $0.storesDepthRequested = true }.scenePassStoresDepth)
    #expect(!plan {
        $0.storesDepthRequested = true
        $0.depthIsMemoryless = true
    }.scenePassStoresDepth)
}
