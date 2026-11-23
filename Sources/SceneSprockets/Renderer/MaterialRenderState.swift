import Metal
import MetalSprockets
import SwiftMesh

/// How a material's draws blend, use depth, write color, fill and cull, like SCNMaterial's blendMode,
/// readsFromDepthBuffer/writesToDepthBuffer, colorBufferWriteMask, fillMode and cullMode. Used by Blinn-Phong and
/// ShaderMaterial. PBR materials use glTF's `doubleSided` instead of `cullMode`.
public struct MaterialRenderState: Sendable, Hashable {
    /// Straight (not premultiplied) alpha.
    public enum BlendMode: String, Sendable, Hashable, CaseIterable, Codable {
        /// Over what is behind, by alpha. Blends only when the material is transparent.
        case alpha
        /// Adds color times alpha.
        case add
        /// Subtracts color times alpha from what is behind.
        case subtract
        /// Multiplies what is behind by the color.
        case multiply
        /// 1 - (1 - behind) * (1 - color): brightens.
        case screen
        /// Writes the color with no blending, even when transparent.
        case replace
        /// Stochastic transparency (#539): drawn with the opaque meshes, writing depth, with alpha turned into hashed
        /// sample coverage, so overlapping see-through surfaces (hair, foliage) need no sorting. Noisy at one sample;
        /// looks best with 4x MSAA. Shader materials get alpha to coverage without the random offset, unless their
        /// shader applies `Lighting::stochasticAlpha` itself.
        case stochastic
    }

    /// How the material's color combines with what is already drawn.
    public var blendMode: BlendMode
    /// Transparent draws never write depth.
    public var writesToDepthBuffer: Bool
    /// False draws on top of what is already drawn.
    public var readsFromDepthBuffer: Bool
    /// The color channels that the draw writes.
    public var colorWriteMask: MTLColorWriteMask
    /// `.lines` draws triangle edges.
    public var fillMode: MTLTriangleFillMode
    /// The faces not to draw. `.none` draws both sides.
    public var cullMode: MTLCullMode

    /// Creates render state. The defaults draw normally, with alpha blending for transparent materials, and draw both
    /// sides of each triangle.
    public init(blendMode: BlendMode = .alpha, writesToDepthBuffer: Bool = true, readsFromDepthBuffer: Bool = true, colorWriteMask: MTLColorWriteMask = .all, fillMode: MTLTriangleFillMode = .fill, cullMode: MTLCullMode = .none) {
        self.blendMode = blendMode
        self.writesToDepthBuffer = writesToDepthBuffer
        self.readsFromDepthBuffer = readsFromDepthBuffer
        self.colorWriteMask = colorWriteMask
        self.fillMode = fillMode
        self.cullMode = cullMode
    }

    /// Add, subtract, multiply and screen blend with what is behind, so they draw with transparent meshes.
    public var blendsWithBackground: Bool {
        switch blendMode {
        case .alpha, .replace, .stochastic: false
        case .add, .subtract, .multiply, .screen: true
        }
    }

    /// MTLColorWriteMask is not Hashable.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        (lhs.blendMode, lhs.writesToDepthBuffer, lhs.readsFromDepthBuffer, lhs.colorWriteMask.rawValue, lhs.fillMode, lhs.cullMode) == (rhs.blendMode, rhs.writesToDepthBuffer, rhs.readsFromDepthBuffer, rhs.colorWriteMask.rawValue, rhs.fillMode, rhs.cullMode)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(blendMode)
        hasher.combine(writesToDepthBuffer)
        hasher.combine(readsFromDepthBuffer)
        hasher.combine(colorWriteMask.rawValue)
        hasher.combine(fillMode)
        hasher.combine(cullMode)
    }
}

/// Order-independent transparency (#494): which materials can be drawn as weighted blended transparency when
/// ``SceneGraph/Environment/orderIndependentTransparency`` is on. Others stay sorted and blended in the scene pass.
public protocol SupportsWeightedTransparency {
    /// Whether this material blends like straight alpha over what is behind, which weighted blending can stand in for.
    var drawsAsWeightedTransparency: Bool { get }
}

extension Element {
    /// Draw state for ``RenderContext/drawsWeightedTransparency`` (#494): the fragment shader writes
    /// `Lighting::WeightedTransparencyOutput`, color 0 (`.rgba16Float`) accumulates and color 1 (`.r16Float`)
    /// multiplies revealage. Depth is tested, not written.
    public func weightedTransparencyState() -> some Element {
        depthCompare(function: .greater, writes: false)
            .renderPipelineDescriptorTransformer { descriptor in
                let accumulation: MTL4RenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
                accumulation.pixelFormat = .rgba16Float
                accumulation.blendingState = .enabled
                accumulation.rgbBlendOperation = .add
                accumulation.alphaBlendOperation = .add
                accumulation.sourceRGBBlendFactor = .one
                accumulation.destinationRGBBlendFactor = .one
                accumulation.sourceAlphaBlendFactor = .one
                accumulation.destinationAlphaBlendFactor = .one
                let revealage: MTL4RenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[1]
                revealage.pixelFormat = .r16Float
                revealage.blendingState = .enabled
                revealage.rgbBlendOperation = .add
                revealage.alphaBlendOperation = .add
                revealage.sourceRGBBlendFactor = .zero
                revealage.destinationRGBBlendFactor = .oneMinusSourceColor
                revealage.sourceAlphaBlendFactor = .zero
                revealage.destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
    }

    /// Reversed depth. `isTransparent` draws do not write depth and blend by alpha unless the blend mode says otherwise.
    /// `writesBlendedDepth` makes transparent draws write depth anyway: visionOS's compositor needs depth for every
    /// pixel drawn, so pass `context.stereoViews != nil`. `depthFunction` replaces `.greater` when the state reads depth.
    public func materialRenderState(_ state: MaterialRenderState, isTransparent: Bool, writesBlendedDepth: Bool = false, depthFunction: MTLCompareFunction = .greater) -> some Element {
        depthCompare(function: state.readsFromDepthBuffer ? depthFunction : .always, writes: state.writesToDepthBuffer && (!isTransparent || writesBlendedDepth))
            .renderPipelineDescriptorTransformer { descriptor in
                let attachment: MTL4RenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
                attachment.writeMask = state.colorWriteMask
                if state.blendMode == .stochastic {
                    // Alpha to one keeps the stored alpha at 1, as for opaque meshes.
                    descriptor.alphaToCoverageState = .enabled
                    descriptor.alphaToOneState = .enabled
                    return
                }
                let blendMode: MaterialRenderState.BlendMode = state.blendMode == .alpha && !isTransparent ? .replace : state.blendMode
                guard blendMode != .replace else {
                    return
                }
                attachment.blendingState = .enabled
                attachment.rgbBlendOperation = .add
                attachment.alphaBlendOperation = .add
                attachment.sourceAlphaBlendFactor = .one
                attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                switch blendMode {
                case .alpha, .replace, .stochastic:
                    attachment.sourceRGBBlendFactor = .sourceAlpha
                    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
                case .add:
                    attachment.sourceRGBBlendFactor = .sourceAlpha
                    attachment.destinationRGBBlendFactor = .one
                case .subtract:
                    attachment.rgbBlendOperation = .reverseSubtract
                    attachment.sourceRGBBlendFactor = .sourceAlpha
                    attachment.destinationRGBBlendFactor = .one
                case .multiply:
                    attachment.sourceRGBBlendFactor = .destinationColor
                    attachment.destinationRGBBlendFactor = .zero
                case .screen:
                    attachment.sourceRGBBlendFactor = .one
                    attachment.destinationRGBBlendFactor = .oneMinusSourceColor
                }
            }
    }
}

/// Returns an element that draws one submesh with a cull and fill mode.
///
/// For custom ``MaterialRenderer`` types. A plain draw resets the cull and fill mode, so this sets them in
/// the draw itself.
///
/// - Parameters:
///   - submesh: The submesh to draw.
///   - instanceCount: The number of instances.
///   - cullMode: The faces not to draw, usually ``MaterialRenderState/cullMode``.
///   - isMirrored: Whether the model matrix mirrors (negative determinant). Mirroring flips the winding, so the
///     culled side flips too.
///   - fillMode: `.lines` draws triangle edges.
///   - stereoViews: Views to draw to at once with vertex amplification, usually ``RenderContext/stereoViews``.
public func materialDraw(_ submesh: MetalMesh.Submesh, instanceCount: Int = 1, cullMode: MTLCullMode = .none, isMirrored: Bool = false, fillMode: MTLTriangleFillMode = .fill, stereoViews: StereoViews? = nil) -> AnyElement {
    // Always sets the winding, even without culling: shaders read `front_facing` for two-sided lighting (#500), and
    // Metal's default winding is clockwise.
    let indexBuffer = submesh.indexBuffer
    let offset = submesh.indexBufferOffset
    let (primitiveType, indexType, indexCount) = (submesh.primitiveType, submesh.indexType, submesh.indexCount)
    return Draw { encoder in
        stereoViews?.configure(encoder)
        encoder.drawIndexedPrimitives(primitiveType: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer.gpuAddress + UInt64(offset), indexBufferLength: indexBuffer.length - offset, instanceCount: instanceCount)
    }
    // Set through modifiers so the pass tracks them; state set directly on the encoder leaks to later draws (#472).
    .cullMode(cullMode)
    .frontFacing(isMirrored ? .clockwise : .counterClockwise)
    .triangleFillMode(fillMode)
    .useResource(indexBuffer, usage: .read, stages: .vertex)
    .eraseToAnyElement()
}
