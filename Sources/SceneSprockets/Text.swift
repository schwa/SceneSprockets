import CoreText
import Foundation
import Metal
import MetalSprockets
import simd
#if arch(arm64)
import MetalSprocketsAddOns
#endif

/// Flat text at a node, drawn with GPU glyph outlines (MetalSprocketsAddOns Slug), so it stays sharp at any distance.
///
/// The text lies in the node's XY plane, facing +Z, with the first line's baseline on y = 0 starting at x = 0. One
/// font unit is one scene unit, so `fontSize` is the em height in scene units. The text is unlit and draws after the
/// meshes, depth-tested against them. Unlike ``SceneGraph/Shape/text(_:fontName:fontSize:extrusionDepth:)`` it is not
/// a mesh: it has no material, casts no shadow and is not hit-tested.
public struct SceneText: Hashable, Codable, Sendable {
    /// The text. Newlines start new lines.
    public var string: String
    /// The PostScript or family name of the font.
    public var fontName: String
    /// The em height, in scene units.
    public var fontSize: Float
    /// Linear RGBA color.
    public var color: SIMD4<Float>
    /// The width at which lines wrap, in scene units, or `nil` for no wrapping.
    public var maximumWidth: Float?

    /// Creates text for a node.
    ///
    /// - Parameters:
    ///   - string: The text.
    ///   - fontName: The font's PostScript or family name.
    ///   - fontSize: The em height, in scene units.
    ///   - color: Linear RGBA color.
    ///   - maximumWidth: The width at which lines wrap, in scene units.
    public init(_ string: String, fontName: String = "Helvetica", fontSize: Float = 1, color: SIMD4<Float> = [1, 1, 1, 1], maximumWidth: Float? = nil) {
        self.string = string
        self.fontName = fontName
        self.fontSize = fontSize
        self.color = color
        self.maximumWidth = maximumWidth
    }
}

extension SceneGraph {
    // Visible nodes with text that a camera with `categoryBitMask` sees, with their world transforms.
    func visibleTexts(categoryBitMask: UInt = .max) -> [(text: SceneText, worldTransform: simd_float4x4)] {
        var result: [(text: SceneText, worldTransform: simd_float4x4)] = []
        visit { node, worldTransform in
            if let text = node.text, !text.string.isEmpty, node.categoryBitMask & categoryBitMask != 0 {
                result.append((text, worldTransform))
            }
        }
        return result
    }
}

#if arch(arm64)
// Built glyph meshes, shared by every node and frame that shows the same text.
final class SceneTextMeshCache: @unchecked Sendable {
    static let shared = SceneTextMeshCache()
    // Dropped wholesale past this many entries, so changing text cannot grow it forever.
    private static let limit = 256
    private let lock = NSLock()
    private var scenes: [SceneText: SlugScene] = [:]

    // nil when the text has no visible glyphs.
    func scene(for text: SceneText, device: MTLDevice) throws -> SlugScene? {
        if let scene = lock.withLock({ scenes[text] }) {
            return scene
        }
        let builder = SlugTextMeshBuilder(device: device)
        let font = CTFontCreateWithName(text.fontName as CFString, CGFloat(text.fontSize), nil)
        let linear = CGColorSpace(name: CGColorSpace.linearSRGB)! // swiftlint:disable:this force_unwrapping
        let components = (0 ..< 4).map { CGFloat(text.color[$0]) }
        let foreground = CGColor(colorSpace: linear, components: components)! // swiftlint:disable:this force_unwrapping
        let attributed = NSAttributedString(string: text.string, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): foreground
        ])
        let width = text.maximumWidth.map { CGFloat($0) } ?? .greatestFiniteMagnitude
        builder.buildMesh(attributedString: attributed, maximumSize: CGSize(width: width, height: .greatestFiniteMagnitude))
        let scene: SlugScene
        do {
            scene = try builder.finalize()
        } catch SlugError.noMeshes {
            return nil
        }
        lock.withLock {
            if scenes.count >= Self.limit {
                scenes.removeAll()
            }
            scenes[text] = scene
        }
        return scene
    }
}

extension SceneGraphElement {
    // One Slug draw per text node. The node transform goes into the view-projection, so cached meshes keep their
    // identity model matrix and nodes sharing a text need no per-node buffers.
    static func makeTextElements(_ texts: [(text: SceneText, worldTransform: simd_float4x4)], context: RenderContext, viewportSize: SIMD2<Float>, device: MTLDevice) throws -> [AnyElement] {
        let viewProjection = context.projectionMatrix * context.viewMatrix
        return try texts.compactMap { text, worldTransform in
            guard let scene = try SceneTextMeshCache.shared.scene(for: text, device: device) else {
                return nil
            }
            let constants = SlugFrameConstants(viewProjectionMatrix: viewProjection * worldTransform, viewportSize: viewportSize)
            return try SlugTextRenderPipeline(scene: scene, viewConstants: [constants], depthCompare: (.greater, false)).eraseToAnyElement()
        }
    }
}
#endif
