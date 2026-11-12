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
        case .alpha, .replace: false
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

extension Element {
    /// Reversed depth. `isTransparent` draws do not write depth and blend by alpha unless the blend mode says otherwise.
    public func materialRenderState(_ state: MaterialRenderState, isTransparent: Bool) -> some Element {
        depthCompare(function: state.readsFromDepthBuffer ? .greater : .always, writes: state.writesToDepthBuffer && !isTransparent)
            .renderPipelineDescriptorTransformer { descriptor in
                let attachment: MTL4RenderPipelineColorAttachmentDescriptor = descriptor.colorAttachments[0]
                attachment.writeMask = state.colorWriteMask
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
                case .alpha, .replace:
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

/// Draw resets cull and fill mode, so draws that need them set them in their own closure. Mirrored transforms flip the
/// winding.
public func materialDraw(_ submesh: MetalMesh.Submesh, instanceCount: Int = 1, cullMode: MTLCullMode = .none, isMirrored: Bool = false, fillMode: MTLTriangleFillMode = .fill) -> AnyElement {
    guard cullMode != .none || fillMode != .fill else {
        return Draw(primitiveType: submesh.primitiveType, indexBuffer: submesh.indexBuffer, indexType: submesh.indexType, indexCount: submesh.indexCount, indexBufferOffset: submesh.indexBufferOffset, instanceCount: instanceCount).eraseToAnyElement()
    }
    let indexBuffer = submesh.indexBuffer
    let offset = submesh.indexBufferOffset
    let (primitiveType, indexType, indexCount) = (submesh.primitiveType, submesh.indexType, submesh.indexCount)
    return Draw { encoder in
        encoder.setCullMode(cullMode)
        encoder.setFrontFacing(isMirrored ? .clockwise : .counterClockwise)
        encoder.setTriangleFillMode(fillMode)
        encoder.drawIndexedPrimitives(primitiveType: primitiveType, indexCount: indexCount, indexType: indexType, indexBuffer: indexBuffer.gpuAddress + UInt64(offset), indexBufferLength: indexBuffer.length - offset, instanceCount: instanceCount)
    }
    .useResource(indexBuffer, usage: .read, stages: .vertex)
    .eraseToAnyElement()
}
