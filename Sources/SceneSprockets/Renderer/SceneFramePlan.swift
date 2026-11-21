/// The labels of the GPU intervals that SceneGraphElement reports for each group of passes (#401), through
/// MetalSprockets' `onGPUTimings` and `FrameTimingStatistics.gpuTimings`. SceneView's `sceneFrameTiming()` overlay shows
/// them.
public enum SceneGPUTimingLabel {
    public static let shadowCasters = "Shadow Casters"
    /// Deformation, ambient occlusion depth, renderer pre-passes and particle simulation.
    public static let prePasses = "Pre-Passes"
    /// The scene pass, with the soft particle pass when there is one.
    public static let scene = "Scene"
    public static let shadowMask = "Shadow Mask"
    public static let ambientOcclusion = "Ambient Occlusion"
    public static let fog = "Fog"
    public static let colorAdjust = "Color Adjust"
    public static let autoExposure = "Auto Exposure"
}

// Which passes a SceneGraphElement frame has and in what order, decided from plain facts about the frame so it can be
// tested without rendering (#591). SceneGraphElement.body builds the elements from it.
struct SceneFramePlan: Equatable {
    struct Inputs {
        // The view's color and depth can be read and written by post passes (not stereo, not memoryless).
        var hasPostTargets = false
        var isDebug = false
        var hasAmbientOcclusionSettings = false
        // Opaque entries that draw something, and how many of those apply ambient occlusion in their own shader.
        var opaqueCount = 0
        var inShaderAmbientOcclusionCount = 0
        // A shadow frame was prepared; whether its casters cover the whole view, so no mask pass is needed.
        var hasShadowFrame = false
        var shadowMasksEverything = false
        var hasFog = false
        var adjustsColor = false
        var hasSoftParticles = false
        var hasAutoExposure = false
        // The scene pass resolves MSAA, so a second pass could not reload its samples.
        var resolvesMultisample = false
        var storesDepthRequested = false
        var depthIsMemoryless = false
    }

    enum AmbientOcclusion: Equatable {
        // `inShaderDepth`: a second depth pass of only the in-shader entries, so the apply pass can skip them.
        // `appliesAsPostPass`: some entries do not apply occlusion themselves.
        case passes(inShaderDepth: Bool, appliesAsPostPass: Bool)
    }

    enum PostPass: Equatable {
        case shadowMask, ambientOcclusion, fog, colorAdjust, autoExposure

        var gpuTimingLabel: String {
            switch self {
            case .shadowMask: SceneGPUTimingLabel.shadowMask
            case .ambientOcclusion: SceneGPUTimingLabel.ambientOcclusion
            case .fog: SceneGPUTimingLabel.fog
            case .colorAdjust: SceneGPUTimingLabel.colorAdjust
            case .autoExposure: SceneGPUTimingLabel.autoExposure
            }
        }
    }

    var ambientOcclusion: AmbientOcclusion?
    var drawsText: Bool
    var hasSoftParticlePass: Bool
    var hasShadowCasterPass: Bool
    // After the scene pass, in order: occlusion darkens geometry before fog covers it; color adjustment comes last.
    var postPasses: [PostPass]
    var scenePassStoresDepth: Bool
    var particlePassStoresDepth: Bool

    // Whether the frame needs the post targets at all: caster depth or a post pass.
    var hasPostPhase: Bool { hasShadowCasterPass || !postPasses.isEmpty }

    init(_ inputs: Inputs) {
        if inputs.hasAmbientOcclusionSettings, inputs.hasPostTargets, !inputs.isDebug, inputs.opaqueCount > 0 {
            let inShader = inputs.inShaderAmbientOcclusionCount
            ambientOcclusion = .passes(inShaderDepth: inShader > 0 && inShader < inputs.opaqueCount, appliesAsPostPass: inShader < inputs.opaqueCount)
        }
        drawsText = !inputs.isDebug
        hasSoftParticlePass = inputs.hasPostTargets && inputs.hasSoftParticles && !inputs.resolvesMultisample
        hasShadowCasterPass = inputs.hasShadowFrame
        var postPasses: [PostPass] = []
        if inputs.hasShadowFrame, !inputs.shadowMasksEverything {
            postPasses.append(.shadowMask)
        }
        if case .passes(_, appliesAsPostPass: true) = ambientOcclusion {
            postPasses.append(.ambientOcclusion)
        }
        if inputs.hasPostTargets, inputs.hasFog {
            postPasses.append(.fog)
        }
        if inputs.hasPostTargets, inputs.adjustsColor {
            postPasses.append(.colorAdjust)
        }
        // Last: it meters the finished frame.
        if inputs.hasPostTargets, inputs.hasAutoExposure, !inputs.isDebug {
            postPasses.append(.autoExposure)
        }
        self.postPasses = postPasses
        // The view's depth storage can lag behind the request when the frame is built on a render thread (#393):
        // memoryless depth cannot be stored.
        let storesDepth = inputs.storesDepthRequested && !inputs.depthIsMemoryless
        let hasPostPhase = hasShadowCasterPass || !postPasses.isEmpty
        particlePassStoresDepth = storesDepth || hasPostPhase
        scenePassStoresDepth = particlePassStoresDepth || hasSoftParticlePass
    }
}
