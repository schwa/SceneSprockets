import CoreGraphics
import Foundation
import Metal
import MetalKit
import MetalSupport

/// Makes material textures from images.
///
/// The textures have mipmaps and keep the image's row order: the top row of the image is at texture coordinate
/// `v = 0`, as in glTF and Model I/O. Use `isColor: true` for colors (base color, diffuse, emission), which are
/// stored in sRGB, and `false` for data such as normal maps, roughness and metalness.
public enum MaterialTexture {
    /// Loads a texture from an image file.
    ///
    /// - Parameters:
    ///   - url: The image file. Any format that Image I/O reads works.
    ///   - isColor: Whether the image holds colors (sRGB) or data (linear).
    /// - Returns: The texture.
    /// - Throws: An error if the file cannot be read or the texture cannot be made.
    public static func load(contentsOf url: URL, isColor: Bool = true) throws -> MTLTexture {
        try colorCorrected(textureLoader().newTexture(URL: url, options: options(isColor: isColor)), isColor: isColor)
    }

    /// Makes a texture from an image.
    ///
    /// - Parameters:
    ///   - image: The image.
    ///   - isColor: Whether the image holds colors (sRGB) or data (linear).
    /// - Returns: The texture.
    /// - Throws: An error if the texture cannot be made.
    public static func load(_ image: CGImage, isColor: Bool = true) throws -> MTLTexture {
        try colorCorrected(textureLoader().newTexture(cgImage: image, options: options(isColor: isColor)), isColor: isColor)
    }

    /// Loads a texture from an image in an asset catalog.
    ///
    /// - Parameters:
    ///   - name: The image's name in the asset catalog.
    ///   - bundle: The bundle that holds the asset catalog, or `nil` for the main bundle.
    ///   - isColor: Whether the image holds colors (sRGB) or data (linear).
    /// - Returns: The texture.
    /// - Throws: An error if the image is not found or the texture cannot be made.
    public static func load(named name: String, bundle: Bundle? = nil, isColor: Bool = true) throws -> MTLTexture {
        try colorCorrected(textureLoader().newTexture(name: name, scaleFactor: 1, bundle: bundle, options: options(isColor: isColor)), isColor: isColor)
    }

    private static func textureLoader() -> MTKTextureLoader {
        MTKTextureLoader(device: _MTLCreateSystemDefaultDevice())
    }

    // MTKTextureLoader can ignore the sRGB option (for example for some CGImages), so color textures that come back
    // linear get an sRGB view of the same data.
    private static func colorCorrected(_ texture: MTLTexture, isColor: Bool) throws -> MTLTexture {
        guard isColor else {
            return texture
        }
        let sRGBFormats: [MTLPixelFormat: MTLPixelFormat] = [.rgba8Unorm: .rgba8Unorm_srgb, .bgra8Unorm: .bgra8Unorm_srgb]
        guard let format = sRGBFormats[texture.pixelFormat] else {
            return texture
        }
        guard let view = texture.makeTextureView(pixelFormat: format) else {
            throw CocoaError(.featureUnsupported)
        }
        return view
    }

    private static func options(isColor: Bool) -> [MTKTextureLoader.Option: Any] {
        [
            .SRGB: isColor,
            .generateMipmaps: true,
            .textureUsage: MTLTextureUsage([.shaderRead, .pixelFormatView]).rawValue,
            .textureStorageMode: MTLStorageMode.private.rawValue
        ]
    }
}
