import Metal
import MetalSprockets
@_exported import MetalSprocketsLighting
import SceneSprockets
import SceneSprocketsShaders
import simd

/// The Blinn-Phong lighting inputs of one frame, for renderers whose shaders call `BlinnPhong::shade` from
/// `BlinnPhongLighting.h`, such as raymarched surfaces.
///
/// Positions are camera-relative (#253): the render origin is ``cameraPosition``.
public struct BlinnPhongShading {
    /// The per-frame uniforms, bound as `BlinnPhongFrame`.
    public var frame: BlinnPhongFrame
    /// The lights, never empty: an empty scene binds one unused light, since `frame.lightCount` is 0.
    public var lights: [LightingLight]
    /// The world-space render origin.
    public var cameraPosition: SIMD3<Float>
    /// The shadow map inputs, when shadows are on.
    public var shadow: Shadows.Sampling?

    /// Creates the lighting inputs from a render context.
    public init(context: RenderContext, ambientLightColor: SIMD3<Float>) {
        let cameraPosition = context.cameraMatrix.columns.3.xyz
        let lights = blinnPhongLights(context.lights, shadowSlices: context.shadow == nil ? [] : context.lightShadowSlices).map { light in
            var light = light
            light.position = cameraRelative(light.position, to: cameraPosition)
            return light
        }
        var frame = BlinnPhongFrame()
        frame.ambientLightColor = ambientLightColor
        frame.lightCount = Int32(lights.count)
        frame.materialChannel = context.materialChannel?.rawValue ?? 0
        frame.exposure = context.environment.exposure
        frame.toneMapping = context.environment.toneMapping.shaderValue
        frame.linearOutput = context.outputIsLinear ? 1 : 0
        // Per view (#379). Stereo eyes sit around the render origin (the center camera), so their positions are not zero.
        let viewProjections = context.stereoViews?.relativeViewProjections(origin: cameraPosition) ?? [context.projectionMatrix * context.viewMatrix.rotationOnlyView]
        let eyePositions = context.stereoViews?.cameraPositions.map { $0 - cameraPosition } ?? [.zero]
        withUnsafeMutableBytes(of: &frame.viewProjections) { buffer in
            let slots = buffer.bindMemory(to: simd_float4x4.self)
            for index in 0 ..< slots.count {
                slots[index] = viewProjections[min(index, viewProjections.count - 1)]
            }
        }
        withUnsafeMutableBytes(of: &frame.cameraPositions) { buffer in
            let slots = buffer.bindMemory(to: SIMD3<Float>.self)
            for index in 0 ..< slots.count {
                slots[index] = eyePositions[min(index, eyePositions.count - 1)]
            }
        }
        self.frame = frame
        self.lights = lights.isEmpty ? [LightingLight()] : lights
        self.cameraPosition = cameraPosition
        self.shadow = context.shadow
    }

    /// The shadow map, its sampler and uniforms for a submission (`MSEnvironmentValues.submissionIndex`), or `nil`
    /// when shadows are off.
    public func shadowBinding(submissionIndex: UInt64) -> (texture: MTLTexture, sampler: MTLSamplerState, uniforms: LightingShadowUniforms)? {
        shadow.map { shadow in
            (shadow.shadowMap.depthTexture(forSubmission: submissionIndex), shadow.shadowMap.sampler, shadow.uniforms)
        }
    }
}

public extension BlinnPhongSceneMaterial {
    /// The material's uniforms with its colors and texture flags. Textures themselves are bound separately.
    var uniforms: BlinnPhongMaterialUniforms {
        resolvedUniforms()
    }
}
